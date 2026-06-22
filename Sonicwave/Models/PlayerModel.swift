import Foundation
import Observation

enum PlaybackState: Equatable, Sendable {
    case stopped
    case buffering
    case playing
    case paused
}

enum RepeatMode: String, Sendable, CaseIterable {
    case off, all, one
}

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
    private(set) var history: [Song] = []
    private(set) var currentIndex: Int?

    private(set) var state: PlaybackState = .stopped
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    private(set) var lastError: String?

    var repeatMode: RepeatMode = .off
    var shuffle: Bool = false
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
    @ObservationIgnored private let nowPlaying: NowPlayingCenter?
    @ObservationIgnored private var eventTask: Task<Void, Never>?

    init(playback: PlaybackService? = nil, nowPlaying: NowPlayingCenter? = nil) {
        self.playback = playback
        self.nowPlaying = nowPlaying
        if let playback { startEventLoop(playback) }
        wireRemoteCommands()
    }

    // MARK: - Start / enqueue

    /// Replace the queue and start playing at the given index.
    func play(tracks: [Song], startAt index: Int = 0) {
        guard !tracks.isEmpty, tracks.indices.contains(index) else { return }
        queue = tracks
        setCurrent(index)
        state = .playing
        startCurrent()
    }

    func playNext(_ tracks: [Song]) {
        guard let index = currentIndex else { queue.append(contentsOf: tracks); return }
        queue.insert(contentsOf: tracks, at: index + 1)
    }

    func enqueue(_ tracks: [Song]) {
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
    func moveQueue(from offsets: IndexSet, to destination: Int) {
        queue.move(fromOffsets: offsets, toOffset: destination)
        reindexCurrent()
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
            reindexCurrent()
        }
    }

    /// Remove everything after the current track.
    func clearUpNext() {
        guard let index = currentIndex, index + 1 < queue.count else { return }
        queue.removeSubrange((index + 1)...)
        forward { await $0.enqueueNoMore() }
    }

    // MARK: - Transport

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

    // MARK: - Internal transitions

    private func setCurrent(_ index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        currentTrack = queue[index]
        duration = TimeInterval(queue[index].duration ?? 0)
        position = 0
    }

    /// Manual skip: hard-restart playback at `index` (a brief gap is expected).
    private func advanceManual(to index: Int) {
        guard queue.indices.contains(index) else { return }
        setCurrent(index)
        state = .playing
        startCurrent()
    }

    private func startCurrent(from time: TimeInterval = 0) {
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
        state = .stopped
        position = 0
        duration = 0
        forward { await $0.stop() }
        nowPlaying?.update(track: nil, state: .stopped, position: 0, duration: 0)
    }

    private func reindexCurrent() {
        guard let id = currentTrack?.id else { return }
        currentIndex = queue.firstIndex { $0.id == id }
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

    // MARK: - Event loop

    private func startEventLoop(_ playback: PlaybackService) {
        eventTask = Task { [weak self] in
            for await event in playback.events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: PlaybackEvent) {
        switch event {
        case let .stateChanged(newState):
            state = newState
            syncNowPlayingState()
        case let .position(time, dur):
            position = time
            if dur > 0 { duration = dur }
            nowPlaying?.updateProgress(position: position, duration: duration, state: state)
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

    /// The engine crossed a gapless boundary into a pre-buffered track.
    private func gaplessAdvance(to index: Int) {
        guard queue.indices.contains(index), index != currentIndex else { return }
        if let current = currentTrack { history.append(current) }
        currentIndex = index
        currentTrack = queue[index]
        duration = TimeInterval(queue[index].duration ?? 0)
        position = 0
        updateNowPlayingTrack()
    }

    /// The engine asks for the successor to pre-buffer.
    private func provideNext(after index: Int) {
        guard let playback else { return }
        if let target = autoNext(after: index), queue.indices.contains(target) {
            let song = queue[target]
            let id = song.id
            let suffix = song.suffix
            let dur = TimeInterval(song.duration ?? 0)
            Task { await playback.enqueueNext(songId: id, suffix: suffix, duration: dur, index: target) }
        } else {
            Task { await playback.enqueueNoMore() }
        }
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

    private func wireRemoteCommands() {
        guard let nowPlaying else { return }
        nowPlaying.onPlay = { [weak self] in
            guard let self, self.state != .playing else { return }
            self.togglePlayPause()
        }
        nowPlaying.onPause = { [weak self] in
            guard let self, self.state == .playing else { return }
            self.togglePlayPause()
        }
        nowPlaying.onTogglePlayPause = { [weak self] in self?.togglePlayPause() }
        nowPlaying.onNext = { [weak self] in self?.next() }
        nowPlaying.onPrevious = { [weak self] in self?.previous() }
        nowPlaying.onSeek = { [weak self] time in self?.seek(to: time) }
    }

    // MARK: - Helpers

    /// Forward intent to the playback service if present (no-op in tests).
    private func forward(_ action: @escaping @Sendable (PlaybackService) async -> Void) {
        guard let playback else { return }
        Task { await action(playback) }
    }
}
