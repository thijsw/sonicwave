import Foundation

/// The Subsonic error object inside a failed response.
struct SubsonicAPIError: Decodable, Sendable {
    let code: Int
    let message: String?
}

/// Server identity / capability fields present on every response.
struct ServerInfo: Sendable, Equatable {
    var status: String
    var version: String?
    var type: String?
    var serverVersion: String?
    var openSubsonic: Bool?
}

/// Decodes the `subsonic-response` envelope: the common status/capability
/// fields, plus an optional endpoint-specific `Body` decoded from the same
/// level. On a failed status the body is skipped and `error` is populated.
/// See docs/02-opensubsonic-api.md.
struct InnerResponse<Body: Decodable & Sendable>: Decodable, Sendable {
    let info: ServerInfo
    let error: SubsonicAPIError?
    let body: Body?

    private enum StatusKeys: String, CodingKey {
        case status, version, type, serverVersion, openSubsonic, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StatusKeys.self)
        let status = try container.decodeIfPresent(String.self, forKey: .status) ?? "ok"
        info = ServerInfo(
            status: status,
            version: try container.decodeIfPresent(String.self, forKey: .version),
            type: try container.decodeIfPresent(String.self, forKey: .type),
            serverVersion: try container.decodeIfPresent(String.self, forKey: .serverVersion),
            openSubsonic: try container.decodeIfPresent(Bool.self, forKey: .openSubsonic)
        )
        error = try container.decodeIfPresent(SubsonicAPIError.self, forKey: .error)
        body = status == "ok" ? try Body(from: decoder) : nil
    }
}

/// Outer wrapper: `{ "subsonic-response": { ... } }`.
struct SubsonicResponseWrapper<Body: Decodable & Sendable>: Decodable, Sendable {
    let response: InnerResponse<Body>
    enum CodingKeys: String, CodingKey { case response = "subsonic-response" }
}

/// Payload for endpoints that return no data beyond status (e.g. ping, star).
struct EmptyBody: Decodable, Sendable {
    init() {}
    init(from decoder: Decoder) throws {}
}

// MARK: - Endpoint-specific payload bodies

struct AlbumList2Body: Decodable, Sendable {
    struct Container: Decodable, Sendable { var album: [Album]? }
    var albumList2: Container
}

struct ArtistsBody: Decodable, Sendable {
    struct Index: Decodable, Sendable { var name: String; var artist: [Artist]? }
    struct Container: Decodable, Sendable { var index: [Index]? }
    var artists: Container
}

struct ArtistBody: Decodable, Sendable {
    var artist: Artist
}

struct AlbumBody: Decodable, Sendable {
    var album: Album
}

struct GenresBody: Decodable, Sendable {
    struct Container: Decodable, Sendable { var genre: [Genre]? }
    var genres: Container
}

struct SongsByGenreBody: Decodable, Sendable {
    struct Container: Decodable, Sendable { var song: [Song]? }
    var songsByGenre: Container
}

struct RandomSongsBody: Decodable, Sendable {
    struct Container: Decodable, Sendable { var song: [Song]? }
    var randomSongs: Container
}

struct Starred2Body: Decodable, Sendable {
    struct Container: Decodable, Sendable {
        var artist: [Artist]?
        var album: [Album]?
        var song: [Song]?
    }
    var starred2: Container
}

struct Search3Body: Decodable, Sendable {
    struct Container: Decodable, Sendable {
        var artist: [Artist]?
        var album: [Album]?
        var song: [Song]?
    }
    var searchResult3: Container
}

struct PlaylistsBody: Decodable, Sendable {
    struct Container: Decodable, Sendable { var playlist: [Playlist]? }
    var playlists: Container
}

struct PlaylistBody: Decodable, Sendable {
    var playlist: Playlist
}

struct OpenSubsonicExtensionsBody: Decodable, Sendable {
    struct Extension: Decodable, Sendable { var name: String; var versions: [Int]? }
    var openSubsonicExtensions: [Extension]?
}
