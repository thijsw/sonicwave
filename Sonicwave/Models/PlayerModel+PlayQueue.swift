import Foundation

/// What `savePlayQueue` persists: the queue as song ids, the current song,
/// and the playhead in milliseconds.
struct PlayQueueSnapshot: Sendable, Equatable {
    var songIds: [String]
    var currentId: String?
    var positionMs: Int
}

/// Server-side play-queue persistence: the queue, current track and playhead
/// survive relaunch (restored paused, never auto-playing) and are visible to
/// other clients for cross-device resume. Saves are best-effort — like
/// scrobbles, a failure never surfaces. Restore is wired in AppModel.
extension PlayerModel {
    /// Periodic saves (driven by the ~5 Hz position stream) are throttled to
    /// one per interval; structural moments (pause, track change) force.
    private static let saveInterval: TimeInterval = 30

    /// The state worth persisting right now, or nil when there is nothing
    /// to save (empty queue).
    var playQueueSnapshot: PlayQueueSnapshot? {
        guard !queue.isEmpty else { return nil }
        return PlayQueueSnapshot(songIds: queue.map(\.id),
                                 currentId: currentTrack?.id,
                                 positionMs: Int(position * 1000))
    }

    /// Push the current snapshot to the server. `force` bypasses the
    /// wall-clock throttle (pause and track changes force; position ticks
    /// don't). No-op without an injected store or with an empty queue.
    func saveQueueIfNeeded(force: Bool = false) {
        guard let queueStore, let snapshot = playQueueSnapshot else { return }
        guard force || Date.now.timeIntervalSince(lastQueueSave) >= Self.saveInterval else { return }
        lastQueueSave = .now
        // FIFO-chained on the previous save: concurrent POSTs can complete
        // out of order, letting an older snapshot win server-side.
        let previous = queueSaveTask
        queueSaveTask = Task {
            await previous?.value
            await queueStore(snapshot)
        }
    }
}
