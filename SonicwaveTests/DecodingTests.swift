import Testing
import Foundation
@testable import Sonicwave

/// Response envelope + model decoding against representative JSON, including
/// the failed-status path. See docs/02-opensubsonic-api.md, docs/08-testing.md.
struct DecodingTests {
    private let decoder = SubsonicClient.makeDecoder()

    @Test func decodesAlbumList2() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","type":"navidrome",
        "serverVersion":"0.52.0","openSubsonic":true,"albumList2":{"album":[
        {"id":"a1","name":"Kind of Blue","artist":"Miles Davis","artistId":"ar1",
        "coverArt":"al-a1","songCount":5,"duration":2645,"year":1959,"genre":"Jazz",
        "starred":"2023-04-01T10:00:00.000Z"}]}}}
        """
        let data = Data(json.utf8)
        let wrapper = try decoder.decode(SubsonicResponseWrapper<AlbumList2Body>.self, from: data)
        #expect(wrapper.response.info.status == "ok")
        #expect(wrapper.response.info.openSubsonic == true)
        let albums = try #require(wrapper.response.body?.albumList2.album)
        #expect(albums.count == 1)
        #expect(albums[0].name == "Kind of Blue")
        #expect(albums[0].year == 1959)
        #expect(albums[0].isStarred)
    }

    @Test func decodesFailedStatusIntoError() throws {
        let json = """
        {"subsonic-response":{"status":"failed","version":"1.16.1",
        "error":{"code":40,"message":"Wrong username or password."}}}
        """
        let data = Data(json.utf8)
        let wrapper = try decoder.decode(SubsonicResponseWrapper<EmptyBody>.self, from: data)
        #expect(wrapper.response.info.status == "failed")
        #expect(wrapper.response.error?.code == 40)
        #expect(wrapper.response.body == nil)
    }

    @Test func decodesPlaylistWithEntries() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","playlist":{
        "id":"pl1","name":"Roadtrip","owner":"thijs","public":false,"songCount":2,
        "duration":480,"entry":[
        {"id":"s1","title":"Track One","artist":"A","duration":240},
        {"id":"s2","title":"Track Two","artist":"B","duration":240}]}}}
        """
        let data = Data(json.utf8)
        let wrapper = try decoder.decode(SubsonicResponseWrapper<PlaylistBody>.self, from: data)
        let playlist = try #require(wrapper.response.body?.playlist)
        #expect(playlist.name == "Roadtrip")
        #expect(playlist.entry?.count == 2)
        #expect(playlist.entry?[1].title == "Track Two")
    }

    @Test func decodesOpenSubsonicGenresArray() throws {
        // Navidrome 0.62 omits the legacy `genre` string and sends `genres`.
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","randomSongs":{"song":[
        {"id":"s1","title":"Track","artist":"A","duration":200,
        "genres":[{"name":"Jazz"},{"name":"Bebop"}]}]}}}
        """
        let data = Data(json.utf8)
        let wrapper = try decoder.decode(SubsonicResponseWrapper<RandomSongsBody>.self, from: data)
        let song = try #require(wrapper.response.body?.randomSongs.song?.first)
        #expect(song.genre == nil)
        #expect(song.displayGenre == "Jazz")
    }

    @Test func decodesArtistInfo2AndFlattensBioHTML() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","artistInfo2":{
        "biography":"Miles Davis was an American trumpeter &amp; bandleader. \
        <a href=\\"https://www.last.fm/music/Miles+Davis\\" rel=\\"nofollow\\">Read more on Last.fm</a>",
        "largeImageUrl":"https://example/img.jpg",
        "similarArtist":[{"id":"ar2","name":"John Coltrane","coverArt":"ar-ar2","albumCount":3}]}}}
        """
        let wrapper = try decoder.decode(SubsonicResponseWrapper<ArtistInfo2Body>.self,
                                         from: Data(json.utf8))
        let info = try #require(wrapper.response.body?.artistInfo2)
        #expect(info.similarArtist?.first?.name == "John Coltrane")
        let bio = try #require(info.plainBiography)
        #expect(bio == "Miles Davis was an American trumpeter & bandleader.")
    }

    @Test func decodesSimilarSongs2() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","similarSongs2":{"song":[
        {"id":"s1","title":"So What","artist":"Miles Davis","duration":545},
        {"id":"s2","title":"Naima","artist":"John Coltrane","duration":263}]}}}
        """
        let wrapper = try decoder.decode(SubsonicResponseWrapper<SimilarSongs2Body>.self,
                                         from: Data(json.utf8))
        let songs = try #require(wrapper.response.body?.similarSongs2.song)
        #expect(songs.count == 2)
        #expect(songs[1].title == "Naima")
    }

    @Test func decodesTopSongsAndEmptyContainer() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","topSongs":{"song":[
        {"id":"s1","title":"Blue in Green","artist":"Miles Davis","duration":328}]}}}
        """
        let wrapper = try decoder.decode(SubsonicResponseWrapper<TopSongsBody>.self,
                                         from: Data(json.utf8))
        #expect(wrapper.response.body?.topSongs.song?.count == 1)

        // Servers with no data send an empty object — must not throw.
        let empty = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","topSongs":{}}}
        """
        let emptyWrapper = try decoder.decode(SubsonicResponseWrapper<TopSongsBody>.self,
                                              from: Data(empty.utf8))
        #expect(emptyWrapper.response.body?.topSongs.song == nil)
    }

    @Test func decodesDatesWithoutFractionalSeconds() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","album":{
        "id":"a2","name":"X","starred":"2022-01-02T03:04:05Z"}}}
        """
        let data = Data(json.utf8)
        let wrapper = try decoder.decode(SubsonicResponseWrapper<AlbumBody>.self, from: data)
        #expect(wrapper.response.body?.album.isStarred == true)
    }
}
