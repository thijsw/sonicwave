import Foundation

/// Value types mirroring the OpenSubsonic JSON, kept close to the wire and
/// `Sendable` so they cross actor boundaries safely.
/// See docs/02-opensubsonic-api.md.

struct Song: Identifiable, Codable, Sendable, Hashable {
    let id: String
    var title: String
    var artist: String?
    var artistId: String?
    var album: String?
    var albumId: String?
    var coverArt: String?
    var duration: Int?
    var track: Int?
    var discNumber: Int?
    var year: Int?
    var genre: String?
    var bitRate: Int?
    var suffix: String?
    var contentType: String?
    var size: Int?
    var starred: Date?

    var isStarred: Bool { starred != nil }

    enum CodingKeys: String, CodingKey {
        case id, title, artist, artistId, album, albumId, coverArt, duration
        case track, discNumber, year, genre, bitRate, suffix, contentType, size, starred
    }
}

struct Album: Identifiable, Codable, Sendable, Hashable {
    let id: String
    var name: String
    var artist: String?
    var artistId: String?
    var coverArt: String?
    var songCount: Int?
    var duration: Int?
    var year: Int?
    var genre: String?
    var starred: Date?
    var song: [Song]?

    var isStarred: Bool { starred != nil }
}

struct Artist: Identifiable, Codable, Sendable, Hashable {
    let id: String
    var name: String
    var coverArt: String?
    var albumCount: Int?
    var starred: Date?
    var album: [Album]?

    var isStarred: Bool { starred != nil }
}

struct Genre: Codable, Sendable, Hashable, Identifiable {
    var value: String
    var songCount: Int?
    var albumCount: Int?

    var id: String { value }
}

struct Playlist: Identifiable, Codable, Sendable, Hashable {
    let id: String
    var name: String
    var owner: String?
    var `public`: Bool?
    var songCount: Int?
    var duration: Int?
    var comment: String?
    var changed: Date?
    var coverArt: String?
    var entry: [Song]?
}
