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

    private(set) var artists: [Artist] = []
    private(set) var artistsState: Load<Void> = .idle

    private(set) var genres: [Genre] = []

    private(set) var songs: [Song] = []
    private(set) var songsState: Load<Void> = .idle

    private(set) var starredSongs: [Song] = []
    private(set) var starredAlbums: [Album] = []
    private(set) var starredArtists: [Artist] = []

    private(set) var playlists: [Playlist] = []

    static let pageSize = 100

    private let client: SubsonicClient

    init(client: SubsonicClient) {
        self.client = client
    }

    func reset() {
        albums = []
        albumOffset = 0
        albumsExhausted = false
        albumsState = .idle
        artists = []
        artistsState = .idle
        genres = []
        starredSongs = []
        starredAlbums = []
        starredArtists = []
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
            let body = try await client.send(
                .albumList2(type: albumSortType, size: Self.pageSize, offset: albumOffset),
                as: AlbumList2Body.self
            )
            let page = body.albumList2.album ?? []
            albums.append(contentsOf: page)
            albumOffset += page.count
            albumsExhausted = page.count < Self.pageSize
            albumsState = .loaded(())
        } catch let error as SubsonicError {
            albumsState = .failed(error.userMessage)
            Self.log.error("album load failed: \(error.userMessage)")
        } catch {
            albumsState = .failed(error.localizedDescription)
            Self.log.error("album load failed: \(error.localizedDescription)")
        }
    }

    private static let log = Logger(subsystem: "nl.huell.sonicwave", category: "library")

    func changeAlbumSort(to type: String) async {
        albumSortType = type
        albums = []
        albumOffset = 0
        albumsExhausted = false
        albumsState = .idle
        await loadMoreAlbums()
    }

    // MARK: - Artists

    func loadArtistsIfNeeded() async {
        guard artists.isEmpty else { return }
        artistsState = .loading
        do {
            let body = try await client.send(.artists, as: ArtistsBody.self)
            artists = (body.artists.index ?? []).flatMap { $0.artist ?? [] }
            artistsState = .loaded(())
        } catch let error as SubsonicError {
            artistsState = .failed(error.userMessage)
        } catch {
            artistsState = .failed(error.localizedDescription)
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
        } catch let error as SubsonicError {
            songsState = .failed(error.userMessage)
        } catch {
            songsState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Genres

    func loadGenresIfNeeded() async {
        guard genres.isEmpty else { return }
        do {
            let body = try await client.send(.genres, as: GenresBody.self)
            genres = (body.genres.genre ?? [])
                .sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        } catch {
            genres = []
        }
    }

    // MARK: - Favorites

    func loadStarredIfNeeded() async {
        guard starredSongs.isEmpty, starredAlbums.isEmpty, starredArtists.isEmpty else { return }
        await reloadStarred()
    }

    func reloadStarred() async {
        do {
            let body = try await client.send(.starred2, as: Starred2Body.self)
            starredArtists = body.starred2.artist ?? []
            starredAlbums = body.starred2.album ?? []
            starredSongs = body.starred2.song ?? []
        } catch {
            // leave existing values; surfaced via UI empty state
        }
    }

    // MARK: - Playlists

    func loadPlaylistsIfNeeded() async {
        guard playlists.isEmpty else { return }
        await reloadPlaylists()
    }

    func reloadPlaylists() async {
        do {
            let body = try await client.send(.playlists, as: PlaylistsBody.self)
            playlists = (body.playlists.playlist ?? [])
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            // keep existing
        }
    }

    func playlist(id: String) async -> Playlist? {
        do {
            let body = try await client.send(.playlist(id: id), as: PlaylistBody.self)
            return body.playlist
        } catch {
            return nil
        }
    }

    // MARK: - Playlist editing (M5)

    /// Create a playlist, optionally seeded with songs. Returns the created
    /// playlist (when the server echoes it) so callers can select it.
    @discardableResult
    func createPlaylist(name: String, songIds: [String] = []) async -> Playlist? {
        let created = try? await client.send(.createPlaylist(name: name, songIds: songIds),
                                             as: PlaylistBody.self)
        await reloadPlaylists()
        return created?.playlist
    }

    func deletePlaylist(id: String) async {
        _ = try? await client.sendStatus(.deletePlaylist(id: id))
        await reloadPlaylists()
    }

    func renamePlaylist(id: String, to name: String) async {
        _ = try? await client.sendStatus(.updatePlaylist(id: id, name: name))
        await reloadPlaylists()
    }

    func addToPlaylist(id: String, songIds: [String]) async {
        guard !songIds.isEmpty else { return }
        _ = try? await client.sendStatus(.updatePlaylist(id: id, songIdsToAdd: songIds))
        await reloadPlaylists()
    }

    func removeFromPlaylist(id: String, indexes: [Int]) async {
        guard !indexes.isEmpty else { return }
        _ = try? await client.sendStatus(.updatePlaylist(id: id, songIndexesToRemove: indexes))
        await reloadPlaylists()
    }

    /// Reorder by replacing the playlist's contents with `songIds` in the new
    /// order — `updatePlaylist` can only append, so the full-replace form of
    /// `createPlaylist` is the canonical reorder mechanism.
    func reorderPlaylist(id: String, name: String, songIds: [String]) async {
        _ = try? await client.sendStatus(.createPlaylist(name: name, playlistId: id, songIds: songIds))
        await reloadPlaylists()
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

    func setStarred(_ starred: Bool, songId: String) async {
        await setStarred(starred, songIds: [songId])
    }

    /// Star/unstar several songs, reloading favorites once at the end.
    func setStarred(_ starred: Bool, songIds: [String]) async {
        guard !songIds.isEmpty else { return }
        for id in songIds {
            _ = try? await client.sendStatus(starred ? .star(id: id) : .unstar(id: id))
        }
        await reloadStarred()
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
