import Foundation
import AVFoundation

/// Owns the `AVAudioEngine` graph and drives the Option A progressive decode
/// pipeline (loader → decoder → scheduled buffers). Exposes async intent and an
/// `events` stream consumed by `PlayerModel`. See docs/03-playback-engine.md.
///
/// M3 plays a single track; the second player node + gapless pre-buffering are
/// added in M4.
actor PlaybackService {
    let events: AsyncStream<PlaybackEvent>
    private let continuation: AsyncStream<PlaybackEvent>.Continuation

    private let client: SubsonicClient
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()

    private var outputFormat: AVAudioFormat?
    private var loadGeneration = 0
    private var currentSongId: String?
    private var currentSuffix: String?
    private var durationHint: TimeInterval = 0
    private var seekBaseTime: TimeInterval = 0

    private var outstandingBuffers = 0
    private var finishedDecoding = false
    private var isPaused = false
    private var volume: Float = 1.0

    private var loadTask: Task<Void, Never>?
    private var consumeTask: Task<Void, Never>?
    private var positionTask: Task<Void, Never>?
    private var activity: (any NSObjectProtocol)?

    init(client: SubsonicClient) {
        self.client = client
        let (stream, continuation) = AsyncStream.makeStream(of: PlaybackEvent.self)
        self.events = stream
        self.continuation = continuation
        engine.attach(node)
    }

    // MARK: - Intent

    /// Begin streaming and playing a song from the start.
    func load(songId: String, suffix: String?, duration: TimeInterval) {
        loadGeneration += 1
        let gen = loadGeneration
        teardown(resettingSong: false)
        currentSongId = songId
        currentSuffix = suffix
        durationHint = duration
        seekBaseTime = 0
        isPaused = false
        emit(.stateChanged(.buffering))
        beginLoad(songId: songId, suffix: suffix, gen: gen, timeOffset: nil)
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
        guard outputFormat != nil else { return }
        if !engine.isRunning { try? engine.start() }
        node.play()
        isPaused = false
        beginActivity()
        startPositionUpdates()
        emit(.stateChanged(.playing))
    }

    /// Seek by re-opening the stream at `time` (Option A has no random access).
    func seek(to time: TimeInterval) {
        guard let songId = currentSongId else { return }
        loadGeneration += 1
        let gen = loadGeneration
        teardown(resettingSong: false)
        seekBaseTime = time
        isPaused = false
        emit(.stateChanged(.buffering))
        emit(.position(time: time, duration: durationHint))
        beginLoad(songId: songId, suffix: currentSuffix, gen: gen, timeOffset: Int(time))
    }

    func stop() {
        loadGeneration += 1
        teardown(resettingSong: true)
        emit(.stateChanged(.stopped))
    }

    func setVolume(_ value: Double) {
        volume = Float(max(0, min(1, value)))
        engine.mainMixerNode.outputVolume = volume
    }

    // MARK: - Load pipeline

    private func beginLoad(songId: String, suffix: String?, gen: Int, timeOffset: Int?) {
        finishedDecoding = false
        outstandingBuffers = 0
        loadTask = Task { [weak self] in
            await self?.runLoad(songId: songId, suffix: suffix, gen: gen, timeOffset: timeOffset)
        }
    }

    private func runLoad(songId: String, suffix: String?, gen: Int, timeOffset: Int?) async {
        let prefs = TranscodePrefs.current()
        let url: URL
        do {
            url = try await client.streamURL(songId: songId, format: prefs.format,
                                             maxBitRate: prefs.maxBitRate, timeOffset: timeOffset)
        } catch {
            emit(.failed((error as? SubsonicError)?.userMessage ?? error.localizedDescription))
            emit(.stateChanged(.stopped))
            return
        }

        let source = ProgressiveAudioSource()
        source.open(fileTypeHint: audioFileTypeHint(forSuffix: suffix))
        let decodedBuffers = source.buffers

        // Consume decoded PCM and schedule it as it arrives.
        consumeTask = Task { [weak self] in
            for await box in decodedBuffers {
                await self?.schedule(box.buffer, gen: gen)
            }
            await self?.decodingFinished(gen: gen)
        }

        // Feed bytes into the decoder until the transfer ends.
        let loader = DataStreamLoader()
        do {
            for try await chunk in loader.stream(from: url) {
                if gen != loadGeneration || Task.isCancelled { break }
                source.parse(chunk)
            }
        } catch {
            if gen == loadGeneration {
                emit(.failed((error as? SubsonicError)?.userMessage ?? error.localizedDescription))
            }
        }
        source.finish()
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, gen: Int) {
        guard gen == loadGeneration else { return }

        // Connect/start the engine lazily once the decoded format is known.
        if outputFormat == nil {
            outputFormat = buffer.format
            engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            engine.mainMixerNode.outputVolume = volume
            do { try engine.start() } catch {
                emit(.failed("Audio engine failed to start: \(error.localizedDescription)"))
                return
            }
        }

        outstandingBuffers += 1
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { await self?.bufferCompleted(gen: gen) }
        }

        if !node.isPlaying && !isPaused {
            node.play()
            beginActivity()
            startPositionUpdates()
            emit(.stateChanged(.playing))
        }
    }

    private func bufferCompleted(gen: Int) {
        guard gen == loadGeneration else { return }
        outstandingBuffers -= 1
        if finishedDecoding && outstandingBuffers <= 0 {
            stopPositionUpdates()
            emit(.position(time: durationHint, duration: durationHint))
            emit(.ended)
        }
    }

    private func decodingFinished(gen: Int) {
        guard gen == loadGeneration else { return }
        finishedDecoding = true
        if outstandingBuffers <= 0 && node.isPlaying == false && currentSongId != nil {
            // Nothing decoded (e.g. unsupported format / empty stream).
            emit(.failed("Could not decode this track."))
            emit(.stateChanged(.stopped))
        }
    }

    // MARK: - Position

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
        let t = currentTime()
        let clamped = durationHint > 0 ? min(t, durationHint) : t
        emit(.position(time: clamped, duration: durationHint))
    }

    private func currentTime() -> TimeInterval {
        guard let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime),
              let rate = outputFormat?.sampleRate, rate > 0 else {
            return seekBaseTime
        }
        return seekBaseTime + Double(playerTime.sampleTime) / rate
    }

    // MARK: - Teardown / power

    private func teardown(resettingSong: Bool) {
        loadTask?.cancel(); loadTask = nil
        consumeTask?.cancel(); consumeTask = nil
        stopPositionUpdates()
        node.stop()
        node.reset()
        outputFormat = nil
        outstandingBuffers = 0
        finishedDecoding = false
        if resettingSong {
            currentSongId = nil
            currentSuffix = nil
            endActivity()
        }
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
