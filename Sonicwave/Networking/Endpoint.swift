import Foundation

/// Describes a single Subsonic REST call: the method name and its
/// endpoint-specific query items (auth + common params are added by the
/// client). See docs/02-opensubsonic-api.md.
struct Endpoint: Sendable {
    let method: String
    let queryItems: [URLQueryItem]
    /// Mutations whose parameter lists grow with content (playlist song ids)
    /// blow past typical URL limits around ~1,500 tracks. When the server
    /// advertises the OpenSubsonic `formPost` extension, flagged endpoints are
    /// sent as a form-encoded POST body instead (see `SubsonicClient`).
    let usesFormPost: Bool

    init(_ method: String, _ queryItems: [URLQueryItem] = [], usesFormPost: Bool = false) {
        self.method = method
        self.queryItems = queryItems
        self.usesFormPost = usesFormPost
    }

    // MARK: Connection
    static let ping = Endpoint("ping")

    /// OpenSubsonic capability discovery; used to decide GET vs form POST.
    static let openSubsonicExtensions = Endpoint("getOpenSubsonicExtensions")

    /// Ask the server to rescan its music folders (Settings → Connection,
    /// File → Update Server Library).
    static let startScan = Endpoint("startScan")

    // MARK: Library
    static func albumList2(type: String, size: Int, offset: Int) -> Endpoint {
        Endpoint("getAlbumList2", [
            .init(name: "type", value: type),
            .init(name: "size", value: String(size)),
            .init(name: "offset", value: String(offset))
        ])
    }

    static let artists = Endpoint("getArtists")

    /// Subsonic has no "all songs" endpoint; the Songs view uses a random
    /// sample for now (see docs/05-data-and-caching.md, known limitation).
    static func randomSongs(size: Int) -> Endpoint {
        Endpoint("getRandomSongs", [.init(name: "size", value: String(size))])
    }

    static func artist(id: String) -> Endpoint {
        Endpoint("getArtist", [.init(name: "id", value: id)])
    }

    static func album(id: String) -> Endpoint {
        Endpoint("getAlbum", [.init(name: "id", value: id)])
    }

    static let genres = Endpoint("getGenres")

    static func songsByGenre(_ genre: String, count: Int, offset: Int) -> Endpoint {
        Endpoint("getSongsByGenre", [
            .init(name: "genre", value: genre),
            .init(name: "count", value: String(count)),
            .init(name: "offset", value: String(offset))
        ])
    }

    // MARK: Play queue
    /// Persist playback state server-side: the queue, the current song, and
    /// the playhead (ms). Survives relaunch and enables cross-device resume.
    /// The id list grows with the queue → formPost when available.
    static func savePlayQueue(ids: [String], current: String?, positionMs: Int) -> Endpoint {
        var items: [URLQueryItem] = ids.map { .init(name: "id", value: $0) }
        if let current {
            items.append(.init(name: "current", value: current))
            items.append(.init(name: "position", value: String(positionMs)))
        }
        return Endpoint("savePlayQueue", items, usesFormPost: true)
    }

    static let playQueue = Endpoint("getPlayQueue")

    // MARK: Scrobbling
    /// `submission: false` reports "now playing"; `true` records the play
    /// (Navidrome play counts / external scrobblers).
    static func scrobble(id: String, submission: Bool) -> Endpoint {
        Endpoint("scrobble", [
            .init(name: "id", value: id),
            .init(name: "submission", value: submission ? "true" : "false")
        ])
    }

    // MARK: Favorites
    static let starred2 = Endpoint("getStarred2")

    static func star(id: String, isAlbum: Bool = false, isArtist: Bool = false) -> Endpoint {
        let key = isArtist ? "artistId" : (isAlbum ? "albumId" : "id")
        return Endpoint("star", [.init(name: key, value: id)])
    }

    static func unstar(id: String, isAlbum: Bool = false, isArtist: Bool = false) -> Endpoint {
        let key = isArtist ? "artistId" : (isAlbum ? "albumId" : "id")
        return Endpoint("unstar", [.init(name: key, value: id)])
    }

    // MARK: Search
    static func search3(query: String, songCount: Int, songOffset: Int,
                        albumCount: Int, artistCount: Int) -> Endpoint {
        Endpoint("search3", [
            .init(name: "query", value: query),
            .init(name: "songCount", value: String(songCount)),
            .init(name: "songOffset", value: String(songOffset)),
            .init(name: "albumCount", value: String(albumCount)),
            .init(name: "artistCount", value: String(artistCount))
        ])
    }

    // MARK: Playlists
    static let playlists = Endpoint("getPlaylists")

    static func playlist(id: String) -> Endpoint {
        Endpoint("getPlaylist", [.init(name: "id", value: id)])
    }

    /// Create a playlist, or — when `playlistId` is supplied — replace an
    /// existing playlist's contents with `songIds` in the given order. The
    /// replace form is the canonical way to **reorder** a playlist, since
    /// `updatePlaylist` can only append (see `updatePlaylist`).
    static func createPlaylist(name: String? = nil, playlistId: String? = nil,
                               songIds: [String] = []) -> Endpoint {
        var items: [URLQueryItem] = []
        if let playlistId { items.append(.init(name: "playlistId", value: playlistId)) }
        if let name { items.append(.init(name: "name", value: name)) }
        items += songIds.map { URLQueryItem(name: "songId", value: $0) }
        return Endpoint("createPlaylist", items, usesFormPost: true)
    }

    static func deletePlaylist(id: String) -> Endpoint {
        Endpoint("deletePlaylist", [.init(name: "id", value: id)])
    }

    /// Update a playlist. Supports rename, comment, public flag, adding songs,
    /// and removing songs by their index within the playlist.
    static func updatePlaylist(id: String, name: String? = nil, comment: String? = nil,
                               isPublic: Bool? = nil, songIdsToAdd: [String] = [],
                               songIndexesToRemove: [Int] = []) -> Endpoint {
        var items: [URLQueryItem] = [.init(name: "playlistId", value: id)]
        if let name { items.append(.init(name: "name", value: name)) }
        if let comment { items.append(.init(name: "comment", value: comment)) }
        if let isPublic { items.append(.init(name: "public", value: isPublic ? "true" : "false")) }
        items += songIdsToAdd.map { URLQueryItem(name: "songIdToAdd", value: $0) }
        items += songIndexesToRemove.map { URLQueryItem(name: "songIndexToRemove", value: String($0)) }
        return Endpoint("updatePlaylist", items, usesFormPost: true)
    }
}
