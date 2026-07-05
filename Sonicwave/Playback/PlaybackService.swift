import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox
import os

/// Owns the `AVAudioEngine` graph and drives the Option A progressive decode
/// pipeline. Achieves **gapless** playback by decoding every track to one
/// canonical output format and scheduling consecutive tracks back-to-back on a
/// single `AVAudioPlayerNode` (no stop between tracks), pre-buffering the next
/// track via a pull model. See docs/03-playback-engine.md.
///
/// Coordination with `PlayerModel`:
/// - `play(...)` hard-starts a track (used for first play, manual skip, seek).
/// - When a track finishes decoding, the service emits `.wantNext(afterIndex:)`;
///   `PlayerModel` replies with `enqueueNext(...)` (or `enqueueNoMore()`).
/// - As playback crosses a track boundary the service emits `.trackChanged`.
/// - `.ended` fires only when the final track finishes with no successor.
actor PlaybackService {
    private static let log = Logger(subsystem: "nl.huell.sonicwave", category: "playback")

    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    private let client: SubsonicClient
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// Single fixed format for the node connection so tracks play gaplessly.
    private let canonicalFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    private var engineConnected = false

    /// A contiguous region of the node's output timeline belonging to one track.
    private struct TrackSpan {
        let id: String
        let index: Int
        let duration: TimeInterval
        let seekBase: TimeInterval
        var startFrame: AVAudioFramePosition
        var frameCount: AVAudioFramePosition
        var decodeComplete: Bool
    }

    private var spans: [TrackSpan] = []
    private var cumulativeFrames: AVAudioFramePosition = 0
    private var outstandingBuffers = 0
    private var noMoreTracks = false
    private var reportedIndex: Int?
    private var awaitingNext = false

    private var generation = 0
    private var isPaused = false
    private var volume: Float = 1.0
    /// Whether playback has been started for the current hard-start. Used to
    /// pre-roll a buffer before starting the node (prevents startup underruns /
    /// crackle while the network+decoder ramp up).
    private var hasStartedPlayback = false
    /// Seconds of audio to buffer before starting playback.
    private var prerollFrames: AVAudioFramePosition {
        AVAudioFramePosition(canonicalFormat.sampleRate * 2.0)
    }

    private var decodeTask: Task<Void, Never>?
    private var positionTask: Task<Void, Never>?
    private var activity: (any NSObjectProtocol)?

    /// Persisted UID of the chosen output device (nil = system default).
    private var outputDeviceUID: String?
    /// Device the output unit is currently pointed at.
    private var appliedDeviceID: AudioDeviceID?
    /// Watches the system device list: `AVAudioEngineConfigurationChange` does
    /// NOT fire when a *pinned* device vanishes (the output unit just goes
    /// dead), so device arrivals/departures need their own listener.
    private var deviceListObserver: AudioDeviceListObserver?

    init(client: SubsonicClient) {
        self.client = client
        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self)
        self.events = stream
        self.continuation = continuation
        let savedUID = UserDefaults.standard.string(forKey: "outputDeviceUID")
        self.outputDeviceUID = (savedUID?.isEmpty == false) ? savedUID : nil
        engine.attach(node)
        // Rebuild on output route changes (default device changed, device
        // unplugged, hardware format changed) so playback follows the new route.
        _ = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { await self?.handleConfigChange() }
        }
        // The device-list observer is installed lazily (see startObservingDevices):
        // actor stored properties can't be written from the nonisolated init.
    }

    /// Install the device-list listener (idempotent). Called once the engine
    /// first connects — before that there's nothing to re-route.
    private func startObservingDevices() {
        guard deviceListObserver == nil else { return }
        deviceListObserver = AudioDeviceListObserver { [weak self] in
            Task { await self?.handleDevicesChanged() }
        }
    }

    // MARK: - Intent

    /// Hard-start a track from `time` seconds in (default 0). Resets the gapless
    /// timeline. Used for first play, manual skip and seek.
    func play(songId: String, suffix: String?, duration: TimeInterval, index: Int, from time: TimeInterval = 0) {
        generation += 1
        let gen = generation
        hardReset()
        isPaused = false
        emit(.stateChanged(.buffering))
        if time > 0 { emit(.position(time: time, duration: duration)) }
        startDecode(songId: songId, suffix: suffix, duration: duration, index: index,
                    seekBase: time, gen: gen)
    }

    /// Provide the next track to pre-buffer (reply to `.wantNext`).
    func enqueueNext(songId: String, suffix: String?, duration: TimeInterval, index: Int) {
        guard awaitingNext else { return }
        awaitingNext = false
        startDecode(songId: songId, suffix: suffix, duration: duration, index: index,
                    seekBase: 0, gen: generation)
    }

    /// No successor — the current track is the last one.
    func enqueueNoMore() {
        awaitingNext = false
        noMoreTracks = true
    }

    func pause() {
        guard node.isPlaying else { isPaused = true; return }
        node.pause()
        isPaused = true
        stopPositionUpdates()
        endActivity()
        emit(.stateChanged(.paused))
    }

    func resume() {
        guard engineConnected else { return }
        if !engine.isRunning { try? engine.start() }
        node.play()
        isPaused = false
        beginActivity()
        startPositionUpdates()
        emit(.stateChanged(.playing))
    }

    func stop() {
        generation += 1
        hardReset()
        endActivity()
        emit(.stateChanged(.stopped))
    }

    func setVolume(_ value: Double) {
        volume = Float(max(0, min(1, value)))
        engine.mainMixerNode.outputVolume = volume
    }

    // MARK: - Decode pipeline

    private func startDecode(songId: String, suffix: String?, duration: TimeInterval,
                             index: Int, seekBase: TimeInterval, gen: Int) {
        // Begin a new span starting at the current end of the scheduled timeline.
        let span = TrackSpan(id: songId, index: index, duration: duration, seekBase: seekBase,
                             startFrame: cumulativeFrames, frameCount: 0, decodeComplete: false)
        spans.append(span)
        let spanArrayIndex = spans.count - 1

        decodeTask = Task { [weak self] in
            await self?.runDecode(songId: songId, suffix: suffix, index: index,
                                  seekBase: seekBase, spanArrayIndex: spanArrayIndex, gen: gen)
        }
    }

    private func runDecode(songId: String, suffix: String?, index: Int,
                           seekBase: TimeInterval, spanArrayIndex: Int, gen: Int) async {
        let prefs = TranscodePrefs.current()
        // Server-side `timeOffset` only seeks *transcoded* streams; for original
        // files the server ignores it (plays from the start), so we instead decode
        // from 0 and discard output up to the seek point.
        let transcoding = prefs.format != nil
        let serverOffset = (transcoding && seekBase > 0) ? Int(seekBase) : nil
        let skipFrames = (!transcoding && seekBase > 0)
            ? AVAudioFramePosition(seekBase * canonicalFormat.sampleRate) : 0

        let url: URL
        do {
            url = try await client.streamURL(songId: songId, format: prefs.format,
                                             maxBitRate: prefs.maxBitRate, timeOffset: serverOffset)
        } catch {
            if gen == generation { emit(.failed((error as? SubsonicError)?.userMessage ?? error.localizedDescription)) }
            return
        }

        let source = ProgressiveAudioSource(outputFormat: canonicalFormat, skipFrames: skipFrames)
        source.open(fileTypeHint: audioFileTypeHint(forSuffix: suffix))
        let decoded = source.buffers

        let consume = Task { [weak self] in
            for await box in decoded {
                await self?.schedule(box.buffer, spanArrayIndex: spanArrayIndex, gen: gen)
            }
        }

        let loader = DataStreamLoader()
        do {
            for try await chunk in loader.stream(from: url) {
                if gen != generation || Task.isCancelled { break }
                await throttleReadAhead(loader: loader, gen: gen)
                if gen != generation || Task.isCancelled { break }
                source.parse(chunk)
            }
        } catch {
            if gen == generation {
                emit(.failed((error as? SubsonicError)?.userMessage ?? error.localizedDescription))
            }
        }
        source.finish()
        _ = await consume.value
        await decodeComplete(spanArrayIndex: spanArrayIndex, index: index, gen: gen)
    }

    // MARK: - Bounded read-ahead

    /// Cap how far decoding/scheduling runs ahead of the playhead. Both are well
    /// above the pre-roll so playback starts and never starves, but small enough
    /// to avoid scheduling a whole track in one burst (which starved the audio IO
    /// thread → a dropped cycle → a click) and to bound memory.
    private var maxReadAheadFrames: AVAudioFramePosition { AVAudioFramePosition(canonicalFormat.sampleRate * 15) }
    private var minReadAheadFrames: AVAudioFramePosition { AVAudioFramePosition(canonicalFormat.sampleRate * 8) }

    /// Frames scheduled but not yet played (the buffered look-ahead).
    private func readAheadFrames() -> AVAudioFramePosition {
        cumulativeFrames - (currentSampleTime() ?? 0)
    }

    // MARK: - Output device

    /// Choose the output device by UID (nil = system default). Persists and
    /// applies immediately if the engine is live.
    func setOutputDevice(uid: String?) {
        outputDeviceUID = (uid?.isEmpty == false) ? uid : nil
        UserDefaults.standard.set(outputDeviceUID, forKey: "outputDeviceUID")
        guard engineConnected else { return }
        if hasStartedPlayback {
            // A live property swap wedges the graph silently when the new
            // device's hardware format differs (seen with a USB DAC: audio
            // gone until a full rebuild). Rebuild + restart at the playhead
            // instead — a sub-second gap, but reliable on every device.
            recoverPlayback()
        } else {
            applyOutputDevice()
        }
    }

    /// Point the engine's output unit at the selected device (or the current
    /// system default when none is chosen / the chosen one is gone).
    private func applyOutputDevice() {
        guard let au = engine.outputNode.audioUnit else { return }
        let resolved = outputDeviceUID.flatMap { AudioOutputDevices.deviceID(forUID: $0) }
        guard var dev = resolved ?? AudioOutputDevices.defaultOutputID() else { return }
        let status = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global, 0, &dev,
                                          UInt32(MemoryLayout<AudioDeviceID>.size))
        if status != noErr {
            Self.log.error("set output device failed: \(status)")
        } else {
            appliedDeviceID = dev
        }
    }

    /// Engine I/O config changed (route change / default device / format). Keep
    /// the chosen device, then make sure the engine is running and audio resumes.
    private func handleConfigChange() {
        guard engineConnected else { return }
        applyOutputDevice()
        if !engine.isRunning { try? engine.start() }
        if hasStartedPlayback, !isPaused, !node.isPlaying { node.play() }
    }

    /// A device appeared or disappeared. Only Sonicwave's own pinned route is
    /// touched — the system default (and other apps) are never altered. If the
    /// pinned device vanished, recover onto the fallback; if it came back (or
    /// the effective target otherwise changed), re-pin live.
    private func handleDevicesChanged() {
        guard engineConnected else { return }
        let resolved = outputDeviceUID.flatMap { AudioOutputDevices.deviceID(forUID: $0) }
        let target = resolved ?? AudioOutputDevices.defaultOutputID()
        guard let target, target != appliedDeviceID else { return }
        // Whether the pinned device vanished (graph wedged on dead hardware)
        // or returned (re-pin may cross hardware formats), a live property
        // swap isn't trustworthy — rebuild and resume at the playhead.
        Self.log.info("output route target changed; recovering")
        if hasStartedPlayback {
            recoverPlayback()
        } else {
            applyOutputDevice()
        }
    }

    /// Rebuild the route and hard-restart the current track at the playhead —
    /// the reliable way out of a render graph wedged on vanished hardware
    /// (reuses the seek path). Keeps the paused state.
    private func recoverPlayback() {
        let active = activeSpan()
        var position = active?.seekBase ?? 0
        if let active, let sample = currentSampleTime(), sample >= active.startFrame {
            position = active.seekBase + Double(sample - active.startFrame) / canonicalFormat.sampleRate
            if active.duration > 0 { position = min(position, active.duration) }
        }
        let wasPaused = isPaused
        engine.stop()
        applyOutputDevice()
        try? engine.start()
        guard let active else { return }
        play(songId: active.id, suffix: nil, duration: active.duration,
             index: active.index, from: position)
        if wasPaused { pause() }
    }

    /// Back-pressure: once we're `maxReadAheadFrames` ahead, pause the network
    /// transfer and decoding until playback drains the buffer to
    /// `minReadAheadFrames`, then resume. Awaiting frees the actor so scheduling,
    /// buffer completions, and position ticks keep running.
    private func throttleReadAhead(loader: DataStreamLoader, gen: Int) async {
        guard readAheadFrames() >= maxReadAheadFrames else { return }
        loader.pause()
        while gen == generation, !Task.isCancelled, readAheadFrames() >= minReadAheadFrames {
            try? await Task.sleep(for: .milliseconds(80))
        }
        loader.resume()
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, spanArrayIndex: Int, gen: Int) {
        guard gen == generation, spans.indices.contains(spanArrayIndex) else { return }

        if !engineConnected {
            engine.connect(node, to: engine.mainMixerNode, format: canonicalFormat)
            engine.mainMixerNode.outputVolume = volume
            engineConnected = true
            applyOutputDevice()
            startObservingDevices()
            engine.prepare()
            do { try engine.start() } catch {
                emit(.failed("Audio engine failed to start: \(error.localizedDescription)"))
                return
            }
        }

        let frames = AVAudioFramePosition(buffer.frameLength)
        spans[spanArrayIndex].frameCount += frames
        cumulativeFrames += frames

        outstandingBuffers += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { await self?.bufferCompleted(gen: gen) }
        }

        // Pre-roll: only start once enough audio is buffered to avoid underruns.
        if !hasStartedPlayback && !isPaused && cumulativeFrames >= prerollFrames {
            startNodePlayback()
        }
    }

    private func startNodePlayback() {
        guard !hasStartedPlayback, !isPaused else { return }
        hasStartedPlayback = true
        node.play()
        beginActivity()
        startPositionUpdates()
        emit(.stateChanged(.playing))
    }

    private func decodeComplete(spanArrayIndex: Int, index: Int, gen: Int) {
        guard gen == generation, spans.indices.contains(spanArrayIndex) else { return }
        spans[spanArrayIndex].decodeComplete = true
        if spans[spanArrayIndex].frameCount == 0 && spans.count == 1 {
            emit(.failed("Could not decode this track."))
            emit(.stateChanged(.stopped))
            return
        }
        // A track shorter than the pre-roll window: start now rather than wait.
        if !hasStartedPlayback && !isPaused && cumulativeFrames > 0 {
            startNodePlayback()
        }
        // Ready to pre-buffer the successor of this track.
        awaitingNext = true
        emit(.wantNext(afterIndex: index))
    }

    private func bufferCompleted(gen: Int) {
        guard gen == generation else { return }
        outstandingBuffers -= 1
        guard outstandingBuffers <= 0 else { return }
        if noMoreTracks && allDecodeComplete {
            stopPositionUpdates()
            if let last = spans.last { emit(.position(time: last.duration, duration: last.duration)) }
            emit(.ended)
        } else if hasStartedPlayback {
            // Every scheduled buffer has finished playing but more audio is still
            // expected (decode/network hasn't kept up): the node will now render
            // silence until the next buffer arrives — an underrun heard as a
            // gap/crackle. Logged so the cause can be confirmed at runtime.
            Self.log.warning("audio underrun: player node starved (no buffers scheduled, more audio pending)")
        }
    }

    private var allDecodeComplete: Bool { spans.allSatisfy(\.decodeComplete) }

    // MARK: - Seek

    /// Seek re-opens the current track at `time` (Option A has no random access).
    func seek(to time: TimeInterval) {
        guard let active = activeSpan() else { return }
        play(songId: active.id, suffix: nil, duration: active.duration, index: active.index, from: time)
    }

    // MARK: - Position / boundary detection

    private func startPositionUpdates() {
        positionTask?.cancel()
        positionTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .milliseconds(200)) // ~5 Hz
            }
        }
    }

    private func stopPositionUpdates() {
        positionTask?.cancel()
        positionTask = nil
    }

    private func tick() {
        guard let sample = currentSampleTime(), let span = activeSpan(at: sample) else { return }

        if reportedIndex != span.index {
            reportedIndex = span.index
            emit(.trackChanged(index: span.index))
        }
        let rate = canonicalFormat.sampleRate
        let elapsed = span.seekBase + Double(sample - span.startFrame) / rate
        let clamped = span.duration > 0 ? min(elapsed, span.duration) : elapsed
        emit(.position(time: max(0, clamped), duration: span.duration))
    }

    private func currentSampleTime() -> AVAudioFramePosition? {
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else { return nil }
        return playerTime.sampleTime
    }

    /// The span currently audible (last span whose start is at/below `sample`).
    private func activeSpan(at sample: AVAudioFramePosition) -> TrackSpan? {
        var result: TrackSpan?
        for span in spans where span.startFrame <= sample {
            result = span
        }
        return result ?? spans.first
    }

    private func activeSpan() -> TrackSpan? {
        if let sample = currentSampleTime(), let span = activeSpan(at: sample) { return span }
        return spans.first
    }

    // MARK: - Teardown / power

    private func hardReset() {
        decodeTask?.cancel(); decodeTask = nil
        stopPositionUpdates()
        node.stop()
        node.reset()
        spans.removeAll()
        cumulativeFrames = 0
        outstandingBuffers = 0
        noMoreTracks = false
        awaitingNext = false
        reportedIndex = nil
        hasStartedPlayback = false
        // Engine stays connected at the canonical format; node.reset() clears
        // the scheduled buffer queue.
    }

    private func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Playing audio")
    }

    private func endActivity() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private func emit(_ event: PlaybackEvent) {
        continuation.yield(event)
    }
}
