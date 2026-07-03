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

    // MARK: - Duplicate songs in the queue
    // Index bookkeeping must be positional: an id lookup snaps to the first
    // copy of a duplicated song.

    @Test func removeBeforeCurrentDuplicateKeepsCurrentEntry() {
        let player = PlayerModel()
        player.play(tracks: songs(["A", "B", "A"]), startAt: 2) // playing the 2nd "A"
        player.removeFromQueue(at: 1) // remove "B"
        #expect(player.queue.map(\.id) == ["A", "A"])
        #expect(player.currentIndex == 1) // still the 2nd "A", not the 1st
    }

    @Test func moveQueueWithDuplicatesKeepsCurrentEntry() {
        let player = PlayerModel()
        player.play(tracks: songs(["A", "B", "A"]), startAt: 2) // playing the 2nd "A"
        player.moveQueue(from: IndexSet(integer: 1), to: 0) // move "B" to front
        #expect(player.queue.map(\.id) == ["B", "A", "A"])
        #expect(player.currentIndex == 2) // followed the entry, not the id
    }

    @Test func insertBeforeCurrentDuplicateShiftsCurrent() {
        let player = PlayerModel()
        player.play(tracks: songs(["A", "A"]), startAt: 1) // playing the 2nd "A"
        player.insertInQueue(songs(["9"]), at: 1)
        #expect(player.queue.map(\.id) == ["A", "9", "A"])
        #expect(player.currentIndex == 2)
    }

    @Test func playFromQueueSelectsTheDuplicateEntry() {
        let player = PlayerModel()
        player.play(tracks: songs(["A", "B", "A"]), startAt: 0)
        player.playFromQueue(at: 2) // the 2nd "A"
        #expect(player.currentIndex == 2)
        #expect(player.upNext.isEmpty)
    }

    @Test func nextAdvancesIntoSameSong() {
        let player = PlayerModel()
        player.play(tracks: songs(["A", "A", "B"]), startAt: 0)
        player.next()
        #expect(player.currentIndex == 1) // same song, next entry
        #expect(player.currentTrack?.id == "A")
    }

    // MARK: - Gapless events vs. queue edits
    // The engine echoes the queue position a track had at hand-off; edits made
    // after hand-off shift positions, so events must be translated.

    @Test func gaplessBoundaryFollowsPrebufferedEntryAfterInsert() {
        let player = PlayerModel()
        player.play(tracks: songs(["A", "B", "C"]), startAt: 0)
        player.handle(.wantNext(afterIndex: 0))       // engine pre-buffers "B" (pos 1)
        player.insertInQueue(songs(["X"]), at: 1)     // queue: A X B C — "B" now pos 2
        player.handle(.trackChanged(index: 1))        // engine echoes frozen pos 1
        #expect(player.currentTrack?.id == "B")       // advanced into "B", not "X"
        #expect(player.currentIndex == 2)
    }

    @Test func gaplessBoundaryFollowsPrebufferedEntryAfterRemove() {
        let player = PlayerModel()
        player.play(tracks: songs(["A", "B", "C", "D"]), startAt: 1)
        player.handle(.wantNext(afterIndex: 1))       // pre-buffers "C" (pos 2)
        player.removeFromQueue(at: 0)                 // queue: B C D — "C" now pos 1
        player.handle(.trackChanged(index: 2))        // frozen echo
        #expect(player.currentTrack?.id == "C")
        #expect(player.currentIndex == 1)
    }

    @Test func provideNextAnchorsOnMovedEntry() {
        let player = PlayerModel()
        player.play(tracks: songs(["A", "B", "C"]), startAt: 0)
        player.moveQueue(from: IndexSet(integer: 0), to: 3) // queue: B C A, playing "A" (pos 2)
        player.handle(.wantNext(afterIndex: 0))       // engine echoes "A"'s frozen pos 0
        // Successor must be computed from "A"'s current position (2) → none
        // (end of queue), not from stale position 0 (which would yield "C").
        player.handle(.trackChanged(index: 1))        // no advance should occur into "C"
        #expect(player.currentTrack?.id == "A")
    }
}
