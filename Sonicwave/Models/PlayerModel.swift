import Foundation
import Observation

/// Central source of truth for everything "now playing": current track, the
/// Up Next queue, transport state and position. Observed by the main window,
/// the menu-bar panel, and the system Now Playing center.
///
/// Queue/transport bookkeeping is synchronous and engine-independent (so it's
/// unit-testable without audio). When a `PlaybackService` is injected, intent is
/// forwarded to it; gapless advances are driven by its `.trackChanged` /
/// `.wantNext` events. See docs/01-architecture.md and docs/03-playback-engine.md.
@MainActor
@Observable
final class PlayerModel {
    private(set) var currentTrack: Song?
    private(set) var queue: [Song] = []
    private(set) var currentIndex: Int?

    private(set) var state: PlaybackState = .stopped
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    private(set) var lastError: String?

    var repeatMode: RepeatMode = .off
    var shuffle: Bool = false {
        didSet {
            guard oldValue != shuffle else { return }
            rebuildUpcoming()
        }
    }

    /// Canonical (unshuffled) order, used to restore order when shuffle is off.
    @ObservationIgnored private var unshuffledOrder: [Song] = []
    /// Tracks handed to the engine: the queue position at hand-off (which the
    /// engine echoes back in its events, frozen) → the entry's *current*
    /// position. Queue edits shift positions after hand-off, so events must be
    /// translated through this map or a boundary would advance to whatever
    /// song now sits at the stale position.
    @ObservationIgnored private var spanPositions: [Int: Int] = [:]
    var volume: Double = 1.0 {
        didSet { forward { await $0.setVolume(self.volume) } }
    }

    var isPlaying: Bool { state == .playing }

    /// Upcoming tracks after the current one (the visible "Up Next").
    var upNext: ArraySlice<Song> {
        guard let index = currentIndex, index + 1 <= queue.count else { return [] }
        return queue[(index + 1)...]
    }

    @ObservationIgnored private let playback: PlaybackService?
    // Internal (not private): PlayerModel+RemoteCommands.swift wires this.
    @ObservationIgnored let nowPlaying: NowPlayingCenter?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    // Internal (not private): the scrobbling logic lives in
    // PlayerModel+Scrobbling.swift and stored properties can't move with it.
    /// Reports plays to the server (`scrobble`): (songId, submission).
    /// Injected by AppModel; nil in tests.
    @ObservationIgnored let scrobbler: (@Sendable (String, Bool) async -> Void)?
    /// The current track's play has been recorded (once per track start).
    @ObservationIgnored var submittedScrobble = false

    init(playback: PlaybackService? = nil, nowPlaying: NowPlayingCenter? = nil,
         scrobbler: (@Sendable (String, Bool) async -> Void)? = nil) {
        self.playback = playback
        self.nowPlaying = nowPlaying
        self.scrobbler = scrobbler
        if let playback { startEventLoop(playback) }
        wireRemoteCommands()
    }

    // MARK: - Start / enqueue

    /// Replace the queue and start playing at the given index.
    func play(tracks: [Song], startAt index: Int = 0) {
        guard !tracks.isEmpty, tracks.indices.contains(index) else { return }
        queue = tracks
        unshuffledOrder = tracks
        setCurrent(index)
        if shuffle { rebuildUpcoming() }
        state = .playing
        startCurrent()
    }

    func playNext(_ tracks: [Song]) {
        unshuffledOrder.append(contentsOf: tracks)
        guard let index = currentIndex else { queue.append(contentsOf: tracks); return }
        queue.insert(contentsOf: tracks, at: index + 1)
    }

    func enqueue(_ tracks: [Song]) {
        unshuffledOrder.append(contentsOf: tracks)
        queue.append(contentsOf: tracks)
    }

    // MARK: - Queue editing (Up Next)

    /// Jump to and play a specific queue index (hard start).
    func playFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        setCurrent(index)
        state = .playing
        startCurrent()
    }

    /// Move queue items (SwiftUI `onMove`), keeping the current track tracked.
    /// Index bookkeeping is positional, never by song id — the same song can
    /// sit in the queue twice, and an id lookup would snap to the first copy.
    func moveQueue(from offsets: IndexSet, to destination: Int) {
        var positions = Array(queue.indices)
        positions.move(fromOffsets: offsets, toOffset: destination)
        remapPositions { positions.firstIndex(of: $0) }
        queue.move(fromOffsets: offsets, toOffset: destination)
    }

    /// Insert tracks at a specific queue position (drag-into-Up-Next),
    /// keeping the current track tracked.
    func insertInQueue(_ tracks: [Song], at index: Int) {
        guard !tracks.isEmpty else { return }
        unshuffledOrder.append(contentsOf: tracks)
        let clamped = min(max(index, 0), queue.count)
        queue.insert(contentsOf: tracks, at: clamped)
        remapPositions { $0 >= clamped ? $0 + tracks.count : $0 }
    }

    /// Apply a position transform (from a queue mutation) to every tracked
    /// position: the current entry and the entries handed to the engine.
    private func remapPositions(_ transform: (Int) -> Int?) {
        if let current = currentIndex { currentIndex = transform(current) }
        spanPositions = spanPositions.compactMapValues(transform)
    }

    func removeFromQueue(at index: Int) {
        guard queue.indices.contains(index) else { return }
        let removingCurrent = index == currentIndex
        queue.remove(at: index)
        if removingCurrent {
            if queue.isEmpty {
                clearPlayback()
            } else {
                setCurrent(min(index, queue.count - 1))
                startCurrent()
            }
        } else {
            remapPositions { $0 == index ? nil : ($0 > index ? $0 - 1 : $0) }
        }
    }

    /// Remove everything after the current track.
    func clearUpNext() {
        guard let index = currentIndex, index + 1 < queue.count else { return }
        queue.removeSubrange((index + 1)...)
        forward { await $0.enqueueNoMore() }
    }

}

// MARK: - Transport & internal transitions

extension PlayerModel {
    func togglePlayPause() {
        switch state {
        case .playing:
            state = .paused
            forward { await $0.pause() }
        case .paused:
            state = .playing
            forward { await $0.resume() }
        case .stopped:
            guard currentTrack != nil else { return }
            state = .playing
            startCurrent()
        case .buffering:
            break
        }
        syncNowPlayingState()
    }

    func next() {
        guard let index = currentIndex else { return }
        if let target = linearNext(after: index) {
            advanceManual(to: target)
        } else {
            state = .stopped
            forward { await $0.stop() }
        }
    }

    func previous() {
        guard let index = currentIndex else { return }
        if position > 3 {
            seek(to: 0)
            return
        }
        let prev = index - 1
        if queue.indices.contains(prev) {
            advanceManual(to: prev)
        } else {
            seek(to: 0)
        }
    }

    func seek(to time: TimeInterval) {
        position = max(0, min(time, duration))
        let target = position
        forward { await $0.seek(to: target) }
    }

    /// Cycle repeat: off → all → one → off.
    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    // MARK: - Internal transitions

    private func setCurrent(_ index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        currentTrack = queue[index]
        duration = TimeInterval(queue[index].duration ?? 0)
        position = 0
        scrobbleTrackStarted()
    }

    /// Manual skip: hard-restart playback at `index` (a brief gap is expected).
    private func advanceManual(to index: Int) {
        guard queue.indices.contains(index) else { return }
        setCurrent(index)
        state = .playing
        startCurrent()
    }

    private func startCurrent(from time: TimeInterval = 0) {
        // A hard start resets the engine's timeline; only the current entry
        // is handed over.
        spanPositions = currentIndex.map { [$0: $0] } ?? [:]
        guard let track = currentTrack, let index = currentIndex else { return }
        updateNowPlayingTrack()
        let id = track.id
        let suffix = track.suffix
        let dur = TimeInterval(track.duration ?? 0)
        forward { await $0.play(songId: id, suffix: suffix, duration: dur, index: index, from: time) }
    }

    private func clearPlayback() {
        currentTrack = nil
        currentIndex = nil
        spanPositions = [:]
        state = .stopped
        position = 0
        duration = 0
        forward { await $0.stop() }
        nowPlaying?.update(track: nil, state: .stopped, position: 0, duration: 0)
    }

    /// Successor for automatic (gapless) advance — honors repeat-one (loop).
    private func autoNext(after index: Int) -> Int? {
        if repeatMode == .one { return index }
        return linearNext(after: index)
    }

    /// Successor for manual skip — ignores repeat-one, honors repeat-all wrap.
    private func linearNext(after index: Int) -> Int? {
        let next = index + 1
        if queue.indices.contains(next) { return next }
        if repeatMode == .all, !queue.isEmpty { return 0 }
        return nil
    }

    /// Reorder the not-yet-reached tracks for the current shuffle state, leaving
    /// the current track and any already pre-buffered next in place (so the
    /// engine's scheduled audio still matches what we display). Turning shuffle
    /// off restores the original relative order of the upcoming tracks.
    private func rebuildUpcoming() {
        guard let current = currentIndex else { return }
        let pivot = max(current, spanPositions.values.max() ?? current)
        guard pivot + 1 < queue.count else { return }
        let upcoming = Array(queue[(pivot + 1)...])
        let reordered = shuffle
            ? upcoming.shuffled()
            : upcoming.sorted { (unshuffledOrder.firstIndex(of: $0) ?? 0) < (unshuffledOrder.firstIndex(of: $1) ?? 0) }
        queue.replaceSubrange((pivot + 1)..., with: reordered)
    }

}

// MARK: - Event loop & Now Playing

extension PlayerModel {
    private func startEventLoop(_ playback: PlaybackService) {
        eventTask = Task { [weak self] in
            for await event in playback.events {
                self?.handle(event)
            }
        }
    }

    /// Internal (not private) so tests can drive engine events directly.
    func handle(_ event: PlaybackEvent) {
        switch event {
        case let .stateChanged(newState):
            state = newState
            syncNowPlayingState()
        case let .position(time, dur):
            position = time
            if dur > 0 { duration = dur }
            nowPlaying?.updateProgress(position: position, duration: duration, state: state)
            scrobbleIfPlayedEnough()
        case let .trackChanged(index):
            gaplessAdvance(to: index)
        case let .wantNext(afterIndex):
            provideNext(after: afterIndex)
        case .ended:
            state = .stopped
            syncNowPlayingState()
        case let .failed(message):
            lastError = message
            state = .stopped
        }
    }

    /// Dismiss the surfaced playback error (the alert's binding).
    func clearError() { lastError = nil }

    /// The engine crossed a gapless boundary into a pre-buffered track. `echo`
    /// is the queue position at hand-off; translate it to the entry's current
    /// position (queue edits may have shifted it since).
    private func gaplessAdvance(to echo: Int) {
        // Echoes not in the map were never handed over in this timeline
        // (stale event across a hard restart) — ignore rather than advance to
        // whatever now sits at that position.
        guard let index = spanPositions.removeValue(forKey: echo),
              queue.indices.contains(index), index != currentIndex else { return }
        let previous = currentIndex
        currentIndex = index
        currentTrack = queue[index]
        duration = TimeInterval(queue[index].duration ?? 0)
        position = 0
        scrobbleTrackStarted()
        // The span that just finished is done — drop its stale mapping.
        if let previous {
            spanPositions = spanPositions.filter { $0.value != previous }
        }
        updateNowPlayingTrack()
    }

    /// The engine asks for the successor to pre-buffer. `echo` is the position
    /// (at hand-off) of the track that finished decoding; its successor is
    /// computed from that entry's *current* position.
    private func provideNext(after echo: Int) {
        let anchor = spanPositions[echo] ?? currentIndex ?? echo
        guard let target = autoNext(after: anchor), queue.indices.contains(target) else {
            Task { await playback?.enqueueNoMore() }
            return
        }
        spanPositions[target] = target
        guard let playback else { return }
        let song = queue[target]
        let id = song.id
        let suffix = song.suffix
        let dur = TimeInterval(song.duration ?? 0)
        Task { await playback.enqueueNext(songId: id, suffix: suffix, duration: dur, index: target) }
    }

    // MARK: - Now Playing

    private func updateNowPlayingTrack() {
        nowPlaying?.update(track: currentTrack, state: state, position: position, duration: duration)
        guard let coverArt = currentTrack?.coverArt else { return }
        Task { [weak self] in
            let image = await ArtworkCache.shared.image(coverArt: coverArt, size: 600)
            self?.nowPlaying?.updateArtwork(image)
        }
    }

    private func syncNowPlayingState() {
        nowPlaying?.update(track: currentTrack, state: state, position: position, duration: duration)
    }

    // MARK: - Helpers

    /// Forward intent to the playback service if present (no-op in tests).
    private func forward(_ action: @escaping @Sendable (PlaybackService) async -> Void) {
        guard let playback else { return }
        Task { await action(playback) }
    }
}
