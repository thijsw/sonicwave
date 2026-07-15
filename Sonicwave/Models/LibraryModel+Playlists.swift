import Foundation

/// Server playlists: listing, fetching, and full CRUD. Reorder is the
/// full-replace form of `createPlaylist` (`updatePlaylist` can only append).
/// Split from LibraryModel for the type-body-length lint.
extension LibraryModel {
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

}
