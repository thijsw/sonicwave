import Testing
import Foundation
@testable import Sonicwave

/// Playlist CRUD/reorder request construction (M5). See docs/02-opensubsonic-api.md.
struct PlaylistEndpointTests {
    private func values(_ items: [URLQueryItem], _ name: String) -> [String] {
        items.filter { $0.name == name }.compactMap(\.value)
    }

    @Test func createWithSongs() {
        let endpoint = Endpoint.createPlaylist(name: "Road Trip", songIds: ["1", "2"])
        #expect(endpoint.method == "createPlaylist")
        #expect(endpoint.queryItems.contains(URLQueryItem(name: "name", value: "Road Trip")))
        #expect(values(endpoint.queryItems, "songId") == ["1", "2"])
        #expect(values(endpoint.queryItems, "playlistId").isEmpty)
    }

    @Test func createEmpty() {
        let endpoint = Endpoint.createPlaylist(name: "Empty")
        #expect(values(endpoint.queryItems, "songId").isEmpty)
        #expect(endpoint.queryItems.contains(URLQueryItem(name: "name", value: "Empty")))
    }

    @Test func replaceForReorderKeepsOrder() {
        let endpoint = Endpoint.createPlaylist(name: "Mix", playlistId: "pl-9", songIds: ["c", "a", "b"])
        #expect(endpoint.method == "createPlaylist")
        #expect(endpoint.queryItems.first == URLQueryItem(name: "playlistId", value: "pl-9"))
        #expect(values(endpoint.queryItems, "songId") == ["c", "a", "b"])
    }

    @Test func renameViaUpdate() {
        let endpoint = Endpoint.updatePlaylist(id: "p1", name: "New Name")
        #expect(endpoint.method == "updatePlaylist")
        #expect(endpoint.queryItems.contains(URLQueryItem(name: "playlistId", value: "p1")))
        #expect(endpoint.queryItems.contains(URLQueryItem(name: "name", value: "New Name")))
    }

    @Test func addAndRemoveViaUpdate() {
        let endpoint = Endpoint.updatePlaylist(id: "p1", songIdsToAdd: ["x", "y"], songIndexesToRemove: [2, 0])
        #expect(values(endpoint.queryItems, "songIdToAdd") == ["x", "y"])
        #expect(values(endpoint.queryItems, "songIndexToRemove") == ["2", "0"])
    }

    @Test func delete() {
        let endpoint = Endpoint.deletePlaylist(id: "p1")
        #expect(endpoint.method == "deletePlaylist")
        #expect(endpoint.queryItems == [URLQueryItem(name: "id", value: "p1")])
    }

    @Test func starAndUnstar() {
        #expect(Endpoint.star(id: "s1").queryItems == [URLQueryItem(name: "id", value: "s1")])
        #expect(Endpoint.star(id: "a1", isAlbum: true).queryItems == [URLQueryItem(name: "albumId", value: "a1")])
        #expect(Endpoint.unstar(id: "s1").method == "unstar")
    }
}

/// Album filter endpoints (issue #9): genre and year are list types.
struct AlbumFilterEndpointTests {
    private func items(_ endpoint: Endpoint) -> [String: String?] {
        Dictionary(uniqueKeysWithValues: endpoint.queryItems.map { ($0.name, $0.value) })
    }

    @Test func byGenreCarriesGenreParam() {
        let endpoint = Endpoint.albumList2(type: "byGenre", size: 100, offset: 40, genre: "Jazz")
        #expect(items(endpoint)["type"] == "byGenre")
        #expect(items(endpoint)["genre"] == "Jazz")
        #expect(items(endpoint)["offset"] == "40")
    }

    @Test func byYearCarriesRange() {
        let endpoint = Endpoint.albumList2(type: "byYear", size: 100, offset: 0,
                                           fromYear: 1990, toYear: 1999)
        #expect(items(endpoint)["fromYear"] == "1990")
        #expect(items(endpoint)["toYear"] == "1999")
    }

    @Test func plainSortOmitsFilterParams() {
        let endpoint = Endpoint.albumList2(type: "newest", size: 100, offset: 0)
        #expect(items(endpoint)["genre"] == nil)
        #expect(items(endpoint)["fromYear"] == nil)
    }
}
