import Testing
import Foundation
@testable import Sonicwave

/// Up Next queue editing + gapless successor logic in PlayerModel
/// (engine-independent). See docs/03-playback-engine.md, docs/08-testing.md.
@MainActor
struct QueueEditingTests {
    private func songs(_ ids: [String]) -> [Song] {
        ids.map { Song(id: $0, title: "Title \($0)", duration: 100) }
    }

    @Test func upNextIsTracksAfterCurrent() {
        let player = PlayerModel()
        player.play(tracks: songs(["1", "2", "3", "4"]), startAt: 1)
        #expect(player.upNext.map(\.id) == ["3", "4"])
    }

    @Test func removeFromQueueKeepsCurrentTracked() {
        let player = PlayerModel()
        player.play(tracks: songs(["1", "2", "3"]), startAt: 2)
        player.removeFromQueue(at: 0) // remove a track before current
        #expect(player.currentTrack?.id == "3")
        #expect(player.currentIndex == 1)
    }

    @Test func removeCurrentAdvancesToNext() {
        let player = PlayerModel()
        player.play(tracks: songs(["1", "2", "3"]), startAt: 1)
        player.removeFromQueue(at: 1) // remove current ("2")
        #expect(player.currentTrack?.id == "3")
    }

    @Test func removeLastCurrentStops() {
        let player = PlayerModel()
        player.play(tracks: songs(["1"]), startAt: 0)
        player.removeFromQueue(at: 0)
        #expect(player.currentTrack == nil)
        #expect(player.state == .stopped)
    }

    @Test func moveQueueReindexesCurrent() {
        let player = PlayerModel()
        player.play(tracks: songs(["1", "2", "3"]), startAt: 0)
        player.moveQueue(from: IndexSet(integer: 0), to: 3) // move "1" to the end
        #expect(player.queue.map(\.id) == ["2", "3", "1"])
        #expect(player.currentTrack?.id == "1")
        #expect(player.currentIndex == 2)
    }

    @Test func insertInQueueAtPositionKeepsCurrentTracked() {
        let player = PlayerModel()
        player.play(tracks: songs(["1", "2", "3"]), startAt: 1)
        player.insertInQueue(songs(["9", "8"]), at: 1) // insert before current
        #expect(player.queue.map(\.id) == ["1", "9", "8", "2", "3"])
        #expect(player.currentTrack?.id == "2")
        #expect(player.currentIndex == 3)
    }

    @Test func insertInQueueClampsIndex() {
        let player = PlayerModel()
        player.play(tracks: songs(["1"]), startAt: 0)
        player.insertInQueue(songs(["9"]), at: 42)
        #expect(player.queue.map(\.id) == ["1", "9"])
    }

    @Test func clearUpNextTrimsAfterCurrent() {
        let player = PlayerModel()
        player.play(tracks: songs(["1", "2", "3", "4"]), startAt: 1)
        player.clearUpNext()
        #expect(player.queue.map(\.id) == ["1", "2"])
        #expect(player.upNext.isEmpty)
    }

    @Test func playFromQueueJumpsToIndex() {
        let player = PlayerModel()
        player.play(tracks: songs(["1", "2", "3"]), startAt: 0)
        player.playFromQueue(at: 2)
        #expect(player.currentTrack?.id == "3")
        #expect(player.isPlaying)
    }
}
