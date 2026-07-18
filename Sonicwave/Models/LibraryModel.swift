import Foundation
import Observation
import os

/// Observable library-browsing state. Loads albums/artists/songs/genres from
/// the server with pagination. The SwiftData cache layer is layered in during
/// M2 (docs/05-data-and-caching.md); this model currently fetches directly via
/// the client and holds results in memory.
@MainActor
@Observable
final class LibraryModel {
    enum Load<T: Sendable>: Sendable {
        case idle
        case loading
        case loaded(T)
        case failed(String)
    }

    private(set) var albums: [Album] = []
    private(set) var albumsState: Load<Void> = .idle
    private var albumOffset = 0
    private var albumsExhausted = false
    var albumSortType = "alphabeticalByName"
    private(set) var albumFilter: AlbumFilter = .none

    /// Albums-grid filter. Genre and year are `getAlbumList2` list types, so
    /// an active filter replaces the sort order server-side (issue #9).
    enum AlbumFilter: Hashable {
        case none
        case genre(String)
        case years(from: Int, through: Int)
    }

    private(set) var artists: [Artist] = []
    private(set) var artistsState: Load<Void> = .idle

    private(set) var genres: [Genre] = []

    private(set) var songs: [Song] = []
    private(set) var songsState: Load<Void> = .idle

    private(set) var starredSongs: [Song] = []
    private(set) var starredAlbums: [Album] = []

    // Home shelves (getAlbumList2 list types).
    private(set) var homeNewest: [Album] = []
    private(set) var homeRecent: [Album] = []
    private(set) var homeFrequent: [Album] = []
    private(set) var homeRandom: [Album] = []
    private(set) var homeLoaded = false
    private var homeLoading = false

    // Internal setter (not private): playlist CRUD lives in
    // LibraryModel+Playlists.swift.
    var playlists: [Playlist] = []

    static let pageSize = 100

    // Internal (not private): LibraryModel+Playlists.swift sends through it.
    let client: SubsonicClient

    init(client: SubsonicClient) {
        self.client = client
    }

    func reset() {
        albums = []
        albumOffset = 0
        albumsExhausted = false
        albumFilter = .none
        albumsState = .idle
        artists = []
        artistsState = .idle
        genres = []
        starredSongs = []
        starredAlbums = []
        starredLoaded = false
        homeNewest = []
        homeRecent = []
        homeFrequent = []
        homeRandom = []
        homeLoaded = false
    }

    // MARK: - Albums (paginated)

    func loadAlbumsIfNeeded() async {
        // Retry when empty unless a request is already in flight, so a transient
        // failure (e.g. a network timeout) doesn't blank the grid until relaunch.
        guard albums.isEmpty else { return }
        if case .loading = albumsState { return }
        await loadMoreAlbums()
    }

    func loadMoreAlbums() async {
        guard !albumsExhausted else { return }
        if case .loading = albumsState { return }
        albumsState = .loading
        do {
            let body = try await client.send(albumPageEndpoint(), as: AlbumList2Body.self)
            let page = body.albumList2.album ?? []
            albums.append(contentsOf: page)
            albumOffset += page.count
            albumsExhausted = page.count < Self.pageSize
            albumsState = .loaded(())
        } catch {
            albumsState = .failed(error.userMessage)
            Self.log.error("album load failed: \(error.userMessage)")
        }
    }

    /// The next page for the current sort/filter combination. Filters are
    /// list *types* in the API, so an active filter takes over from the sort.
    private func albumPageEndpoint() -> Endpoint {
        switch albumFilter {
        case .none:
            return .albumList2(type: albumSortType, size: Self.pageSize, offset: albumOffset)
        case let .genre(name):
            return .albumList2(type: "byGenre", size: Self.pageSize, offset: albumOffset,
                               genre: name)
        case let .years(from, through):
            return .albumList2(type: "byYear", size: Self.pageSize, offset: albumOffset,
                               fromYear: from, toYear: through)
        }
    }

    private static let log = Logger(subsystem: "nl.huell.sonicwave", category: "library")

    func changeAlbumSort(to type: String) async {
        albumSortType = type
        await reloadAlbums()
    }

    func changeAlbumFilter(to filter: AlbumFilter) async {
        guard filter != albumFilter else { return }
        albumFilter = filter
        await reloadAlbums()
    }

    private func reloadAlbums() async {
        albums = []
        albumOffset = 0
        albumsExhausted = false
        albumsState = .idle
        await loadMoreAlbums()
    }

    // MARK: - Artists

    func loadArtistsIfNeeded() async {
        guard artists.isEmpty else { return }
        if case .loading = artistsState { return }
        artistsState = .loading
        do {
            let body = try await client.send(.artists, as: ArtistsBody.self)
            artists = (body.artists.index ?? []).flatMap { $0.artist ?? [] }
            artistsState = .loaded(())
        } catch {
            artistsState = .failed(error.userMessage)
        }
    }

    // MARK: - Songs (random sample — see endpoint note)

    func loadSongsIfNeeded() async {
        guard songs.isEmpty else { return }
        if case .loading = songsState { return }
        songsState = .loading
        do {
            let body = try await client.send(.randomSongs(size: 500), as: RandomSongsBody.self)
            songs = body.randomSongs.song ?? []
            songsState = .loaded(())
        } catch {
            songsState = .failed(error.userMessage)
        }
    }

    /// A fresh random batch for whole-library shuffle (Shuffle All). Distinct
    /// from the Songs sample above so the visible list isn't disturbed.
    /// Best-effort: an empty result simply leaves playback untouched.
    func randomBatch(size: Int = 500) async -> [Song] {
        let body = try? await client.send(.randomSongs(size: size), as: RandomSongsBody.self)
        return body?.randomSongs.song ?? []
    }

    // MARK: - Genres

    private var genresLoading = false

    func loadGenresIfNeeded() async {
        // Albums and the column browser can both request genres at once.
        guard genres.isEmpty, !genresLoading else { return }
        genresLoading = true
        defer { genresLoading = false }
        do {
            let body = try await client.send(.genres, as: GenresBody.self)
            genres = (body.genres.genre ?? [])
                .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        } catch {
            genres = []
        }
    }

    // MARK: - Favorites

    private var starredLoaded = false
    private var starredLoading = false

    func loadStarredIfNeeded() async {
        // `starredLoaded` (not emptiness): a user with zero favorites would
        // otherwise refetch on every appearance; the in-flight flag stops
        // Favorites + an album detail from firing duplicate fetches.
        guard !starredLoaded, !starredLoading else { return }
        starredLoading = true
        await reloadStarred()
        starredLoading = false
    }

    func reloadStarred() async {
        do {
            let body = try await client.send(.starred2, as: Starred2Body.self)
            starredAlbums = body.starred2.album ?? []
            starredSongs = body.starred2.song ?? []
            starredLoaded = true
        } catch {
            // leave existing values; surfaced via UI empty state
        }
    }

    // MARK: - Search

    struct SearchResults: Sendable {
        var artists: [Artist] = []
        var albums: [Album] = []
        var songs: [Song] = []
        var isEmpty: Bool { artists.isEmpty && albums.isEmpty && songs.isEmpty }
    }

    func search(_ query: String) async -> SearchResults {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SearchResults() }
        do {
            let body = try await client.send(
                .search3(query: trimmed, songCount: 50, songOffset: 0, albumCount: 20, artistCount: 20),
                as: Search3Body.self
            )
            return SearchResults(
                artists: body.searchResult3.artist ?? [],
                albums: body.searchResult3.album ?? [],
                songs: body.searchResult3.song ?? []
            )
        } catch {
            return SearchResults()
        }
    }

    // MARK: - Favorite toggling

    @discardableResult
    func setStarred(_ starred: Bool, songId: String) async -> Bool {
        await setStarred(starred, songIds: [songId])
    }

    /// Star/unstar several songs, reloading favorites once at the end.
    /// Returns false when any write failed, so optimistic UI can roll back.
    @discardableResult
    func setStarred(_ starred: Bool, songIds: [String]) async -> Bool {
        guard !songIds.isEmpty else { return false }
        var allSucceeded = true
        for id in songIds {
            do {
                _ = try await client.sendStatus(starred ? .star(id: id) : .unstar(id: id))
            } catch {
                allSucceeded = false
            }
        }
        await reloadStarred()
        return allSucceeded
    }

    func setAlbumStarred(_ starred: Bool, albumId: String) async {
        _ = try? await client.sendStatus(
            starred ? .star(id: albumId, isAlbum: true) : .unstar(id: albumId, isAlbum: true))
        await reloadStarred()
    }

    // MARK: - Album detail

    func songs(forAlbum id: String) async -> [Song] {
        do {
            let body = try await client.send(.album(id: id), as: AlbumBody.self)
            return body.album.song ?? []
        } catch {
            return []
        }
    }

    /// The full album record for an id — used by "Go to Album" from a track,
    /// where only the song's `albumId` is at hand.
    func album(id: String) async -> Album? {
        try? await client.send(.album(id: id), as: AlbumBody.self).album
    }

    func albums(forArtist id: String) async -> [Album] {
        do {
            let body = try await client.send(.artist(id: id), as: ArtistBody.self)
            return body.artist.album ?? []
        } catch {
            return []
        }
    }

    func songs(forGenre genre: String) async -> [Song] {
        do {
            let body = try await client.send(.songsByGenre(genre, count: Self.pageSize, offset: 0),
                                             as: SongsByGenreBody.self)
            return body.songsByGenre.song ?? []
        } catch {
            return []
        }
    }

}

// MARK: - Discovery (artist info, radio mixes, album shuffle)

extension LibraryModel {
    /// Bio + similar artists for the artist page. Best-effort: nil simply
    /// hides the extras (servers without a metadata agent return little).
    func artistInfo(id: String) async -> ArtistInfo2Body.Info? {
        try? await client.send(.artistInfo2(id: id, count: 12), as: ArtistInfo2Body.self).artistInfo2
    }

    /// Similar-song mix seeding Start Radio. `id` may be a song or artist id.
    func similarSongs(id: String, count: Int = 50) async -> [Song] {
        let body = try? await client.send(.similarSongs2(id: id, count: count),
                                          as: SimilarSongs2Body.self)
        return body?.similarSongs2.song ?? []
    }

    /// Radio fallback for servers with no similarity data for an artist.
    func topSongs(artist name: String, count: Int = 50) async -> [Song] {
        let body = try? await client.send(.topSongs(artist: name, count: count),
                                          as: TopSongsBody.self)
        return body?.topSongs.song ?? []
    }

    /// Random whole albums for Shuffle Albums, honoring the active grid
    /// filter. Without one the server randomizes; genre/year are list types
    /// with no random order, so sample a large filtered page client-side.
    func randomAlbums(count: Int = 12) async -> [Album] {
        let endpoint: Endpoint
        switch albumFilter {
        case .none:
            endpoint = .albumList2(type: "random", size: count, offset: 0)
        case let .genre(name):
            endpoint = .albumList2(type: "byGenre", size: 200, offset: 0, genre: name)
        case let .years(from, through):
            endpoint = .albumList2(type: "byYear", size: 200, offset: 0,
                                   fromYear: from, toYear: through)
        }
        let body = try? await client.send(endpoint, as: AlbumList2Body.self)
        let albums = body?.albumList2.album ?? []
        if case .none = albumFilter { return albums }
        return Array(albums.shuffled().prefix(count))
    }
}

// MARK: - Home shelves

extension LibraryModel {
    func loadHomeIfNeeded() async {
        guard !homeLoaded, !homeLoading else { return }
        await reloadHome()
    }

    /// The four shelves load concurrently; a shelf the server can't provide
    /// simply stays empty (the view hides it).
    func reloadHome() async {
        guard !homeLoading else { return }
        homeLoading = true
        defer { homeLoading = false }
        async let newest = albumList(type: "newest")
        async let recent = albumList(type: "recent")
        async let frequent = albumList(type: "frequent")
        async let random = albumList(type: "random")
        (homeNewest, homeRecent, homeFrequent, homeRandom)
            = await (newest, recent, frequent, random)
        // All-empty almost always means the fetches failed (offline at
        // launch) — stay "unloaded" so the next appearance retries instead
        // of showing an empty Home until relaunch.
        homeLoaded = !(homeNewest.isEmpty && homeRecent.isEmpty
                       && homeFrequent.isEmpty && homeRandom.isEmpty)
    }

    /// Re-roll just the Random shelf (the Home view's refresh button).
    func rerollRandomAlbums() async {
        homeRandom = await albumList(type: "random")
    }

    private func albumList(type: String) async -> [Album] {
        let body = try? await client.send(.albumList2(type: type, size: 20, offset: 0),
                                          as: AlbumList2Body.self)
        return body?.albumList2.album ?? []
    }
}
