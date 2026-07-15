import Testing
import Foundation
@testable import Sonicwave

/// Play-queue persistence (savePlayQueue/getPlayQueue): endpoint building,
/// tolerant decoding, snapshotting, and paused restore. See issue #5.
@MainActor
struct PlayQueueTests {
    private func songs(_ ids: [String]) -> [Song] {
        ids.map { Song(id: $0, title: "Title \($0)", duration: 100) }
    }

    // MARK: Endpoint & decoding

    @Test func savePlayQueueBuildsIdsCurrentAndPosition() {
        let endpoint = Endpoint.savePlayQueue(ids: ["a", "b"], current: "b", positionMs: 12500)
        #expect(endpoint.method == "savePlayQueue")
        #expect(endpoint.usesFormPost)
        let values = endpoint.queryItems.map { "\($0.name)=\($0.value ?? "")" }
        #expect(values == ["id=a", "id=b", "current=b", "position=12500"])
    }

    @Test func savePlayQueueOmitsPositionWithoutCurrent() {
        let endpoint = Endpoint.savePlayQueue(ids: ["a"], current: nil, positionMs: 999)
        #expect(!endpoint.queryItems.contains { $0.name == "position" })
    }

    @Test func playQueueBodyDecodesStringAndNumericCurrent() throws {
        let decoder = SubsonicClient.makeDecoder()
        let stringCurrent = try decoder.decode(PlayQueueBody.self, from: Data(
            #"{"playQueue":{"entry":[{"id":"s1","title":"T"}],"current":"s1","position":9000}}"#.utf8))
        #expect(stringCurrent.playQueue?.current == "s1")
        #expect(stringCurrent.playQueue?.position == 9000)

        let numericCurrent = try decoder.decode(PlayQueueBody.self, from: Data(
            #"{"playQueue":{"entry":[{"id":"42","title":"T"}],"current":42}}"#.utf8))
        #expect(numericCurrent.playQueue?.current == "42")
    }

    // MARK: Snapshot

    @Test func snapshotCapturesQueueCurrentAndPosition() {
        let player = PlayerModel()
        player.play(tracks: songs(["a", "b", "c"]), startAt: 1)
        player.position = 12.5
        let snapshot = player.playQueueSnapshot
        #expect(snapshot?.songIds == ["a", "b", "c"])
        #expect(snapshot?.currentId == "b")
        #expect(snapshot?.positionMs == 12500)
    }

    @Test func snapshotIsNilWithEmptyQueue() {
        #expect(PlayerModel().playQueueSnapshot == nil)
    }

    // MARK: Restore

    @Test func restoreAdoptsQueuePausedAtPosition() {
        let player = PlayerModel()
        player.restoreQueue(songs(["a", "b", "c"]), currentIndex: 1, position: 42)
        #expect(player.state == .stopped)              // never auto-plays
        #expect(player.currentTrack?.id == "b")
        #expect(player.queue.count == 3)
        #expect(player.position == 42)
        #expect(player.upNext.map(\.id) == ["c"])
    }

    @Test func restoreClampsPositionToDuration() {
        let player = PlayerModel()
        player.restoreQueue(songs(["a"]), currentIndex: 0, position: 5000)
        #expect(player.position == 100)                // track duration
    }

    @Test func restoreNeverClobbersAnActiveQueue() {
        let player = PlayerModel()
        player.play(tracks: songs(["x"]))
        player.restoreQueue(songs(["a", "b"]), currentIndex: 0, position: 0)
        #expect(player.currentTrack?.id == "x")
        #expect(player.queue.map(\.id) == ["x"])
    }

    @Test func restoreRejectsOutOfRangeIndex() {
        let player = PlayerModel()
        player.restoreQueue(songs(["a"]), currentIndex: 5, position: 0)
        #expect(player.queue.isEmpty)
    }

    // MARK: Save triggers

    @Test func pauseForcesASaveAndPositionTicksAreThrottled() async {
        let saved = SavedSnapshots()
        let player = PlayerModel(queueStore: { await saved.append($0) })
        player.play(tracks: songs(["a", "b"]))         // track start forces a save
        player.togglePlayPause()                       // pause forces another
        player.handle(.position(time: 5, duration: 100))   // throttled — no save
        var count = 0
        for _ in 0..<200 where count < 2 {             // let the save Tasks land
            await Task.yield()
            count = await saved.count
        }
        #expect(count == 2)
    }
}

private actor SavedSnapshots {
    private(set) var snapshots: [PlayQueueSnapshot] = []
    var count: Int { snapshots.count }
    func append(_ snapshot: PlayQueueSnapshot) { snapshots.append(snapshot) }
}
