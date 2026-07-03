import Foundation

/// Value types mirroring the OpenSubsonic JSON, kept close to the wire and
/// `Sendable` so they cross actor boundaries safely.
/// See docs/02-opensubsonic-api.md.

/// OpenSubsonic multi-genre entry. Newer servers (e.g. Navidrome 0.62) return a
/// `genres` array instead of the legacy single `genre` string.
struct GenreRef: Codable, Sendable, Hashable {
    var name: String
}

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
    var genres: [GenreRef]?

    var isStarred: Bool { starred != nil }
    /// Genre for display, preferring the legacy field, then the OpenSubsonic array.
    var displayGenre: String? { genre ?? genres?.first?.name }

    /// File suffixes of lossless encodings, where the format says more than the
    /// (high, variable) bit rate.
    private static let losslessSuffixes: Set<String> = [
        "flac", "alac", "wav", "aif", "aiff", "ape", "dsf", "dff", "wv", "shn",
    ]

    /// Short encoding label for quality-minded listeners: the format name for
    /// lossless files ("FLAC", "AIFF"), the bit rate for lossy ones
    /// ("320 kbps"), the bare suffix as a fallback.
    var qualityLabel: String? {
        if let suffix = suffix?.lowercased(), Self.losslessSuffixes.contains(suffix) {
            return suffix == "aif" ? "AIFF" : suffix.uppercased()
        }
        if let bitRate, bitRate > 0 { return "\(bitRate) kbps" }
        return suffix?.uppercased()
    }

    /// Sort key for the Quality column: lossless above any lossy bit rate.
    var qualityRank: Int {
        if let suffix = suffix?.lowercased(), Self.losslessSuffixes.contains(suffix) {
            return 100_000 + (bitRate ?? 0)
        }
        return bitRate ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case id, title, artist, artistId, album, albumId, coverArt, duration
        case track, discNumber, year, genre, genres, bitRate, suffix, contentType, size, starred
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
    var genres: [GenreRef]?
    var starred: Date?
    var song: [Song]?

    var isStarred: Bool { starred != nil }
    var displayGenre: String? { genre ?? genres?.first?.name }
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
