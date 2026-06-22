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
/// the menu-bar panel, and (later) the system Now Playing center.
///
/// The actual audio engine arrives in M3 (docs/03-playback-engine.md); for now
/// this model owns the queue/transport state and exposes intent methods that
/// the playback service will be wired into.
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

    var repeatMode: RepeatMode = .off
    var shuffle: Bool = false
    var volume: Double = 1.0

    var isPlaying: Bool { state == .playing }

    // MARK: - Queue management

    /// Replace the queue and start at the given index.
    func play(tracks: [Song], startAt index: Int = 0) {
        guard !tracks.isEmpty, tracks.indices.contains(index) else { return }
        queue = tracks
        currentIndex = index
        currentTrack = tracks[index]
        duration = TimeInterval(tracks[index].duration ?? 0)
        position = 0
        state = .playing
        // TODO(M3): hand off to PlaybackService.
    }

    func playNext(_ tracks: [Song]) {
        guard let index = currentIndex else { queue.append(contentsOf: tracks); return }
        queue.insert(contentsOf: tracks, at: index + 1)
    }

    func enqueue(_ tracks: [Song]) {
        queue.append(contentsOf: tracks)
    }

    // MARK: - Transport (stubbed until M3)

    func togglePlayPause() {
        switch state {
        case .playing: state = .paused
        case .paused, .stopped: state = currentTrack == nil ? .stopped : .playing
        case .buffering: break
        }
    }

    func next() {
        guard let index = currentIndex else { return }
        let nextIndex = index + 1
        if queue.indices.contains(nextIndex) {
            advance(to: nextIndex)
        } else if repeatMode == .all, !queue.isEmpty {
            advance(to: 0)
        } else {
            state = .stopped
        }
    }

    func previous() {
        guard let index = currentIndex else { return }
        if position > 3 {
            position = 0
            return
        }
        let prevIndex = index - 1
        if queue.indices.contains(prevIndex) {
            advance(to: prevIndex)
        } else {
            position = 0
        }
    }

    func seek(to time: TimeInterval) {
        position = max(0, min(time, duration))
        // TODO(M3): forward to PlaybackService.
    }

    private func advance(to index: Int) {
        guard queue.indices.contains(index) else { return }
        currentIndex = index
        currentTrack = queue[index]
        duration = TimeInterval(queue[index].duration ?? 0)
        position = 0
        state = .playing
    }
}
