import Testing
import Foundation
@testable import Sonicwave

/// Disc group headers on multi-disc albums (issue #8): row building keeps
/// track indices stable while interleaving unselectable headers.
@MainActor
struct DiscHeaderTests {
    private func song(_ id: String, disc: Int?, track: Int) -> Song {
        Song(id: id, title: id, duration: 100, track: track, discNumber: disc)
    }

    @Test func multiDiscGetsHeadersWithStableTrackIndices() {
        let tracks = [song("a", disc: 1, track: 1), song("b", disc: 1, track: 2),
                      song("c", disc: 2, track: 1)]
        let rows = TrackTableRow.build(tracks: tracks, headers: [:])
        #expect(rows == [.header("Disc 1"), .track(0), .track(1),
                         .header("Disc 2"), .track(2)])
    }

    @Test func discSubtitleJoinsTheHeader() {
        let tracks = [song("a", disc: 1, track: 1), song("b", disc: 2, track: 1)]
        let rows = TrackTableRow.build(
            tracks: tracks, headers: [2: "Live at Wembley"])
        #expect(rows.contains(.header("Disc 1")))
        #expect(rows.contains(.header("Disc 2 · Live at Wembley")))
    }

    @Test func singleDiscStaysHeaderless() {
        let tracks = [song("a", disc: 1, track: 1), song("b", disc: 1, track: 2)]
        let rows = TrackTableRow.build(tracks: tracks, headers: [:])
        #expect(rows == [.track(0), .track(1)])
    }

    @Test func missingDiscNumbersCountAsDiscOne() {
        let tracks = [song("a", disc: nil, track: 1), song("b", disc: nil, track: 2)]
        let rows = TrackTableRow.build(tracks: tracks, headers: [:])
        #expect(rows == [.track(0), .track(1)])
    }

    @Test func optOutProducesPlainRows() {
        let tracks = [song("a", disc: 1, track: 1), song("b", disc: 2, track: 1)]
        let rows = TrackTableRow.build(tracks: tracks, headers: nil)
        #expect(rows == [.track(0), .track(1)])
    }

    @Test func albumDecodesDiscTitles() throws {
        let json = Data("""
        {"id":"al1","name":"Big Album","discTitles":
            [{"disc":1,"title":"The Slow Side"},{"disc":2,"title":"The Fast Side"},{"disc":3}]}
        """.utf8)
        let album = try SubsonicClient.makeDecoder().decode(Album.self, from: json)
        #expect(album.discSubtitles == [1: "The Slow Side", 2: "The Fast Side"])
    }
}
