import Foundation
import Observation

/// Top-level composition root. Owns the long-lived services and the observable
/// view models, and wires them together. Injected into the environment by
/// `SonicwaveApp`. See docs/01-architecture.md.
@MainActor
@Observable
final class AppModel {
    /// Now-playing source of truth (track, queue, position, transport state).
    let player: PlayerModel

    /// Library browsing state (albums/artists/songs/genres/favorites).
    let library: LibraryModel

    /// Server connection + authentication state.
    let connection: ConnectionModel

    /// Bumped by File → New Playlist (⌘N); the sidebar observes it and opens
    /// its New Playlist prompt (a counter so repeat requests always fire).
    private(set) var newPlaylistRequests = 0

    func requestNewPlaylist() {
        newPlaylistRequests += 1
    }

    // Services (not observed directly by views).
    let credentials: CredentialStore
    let client: SubsonicClient
    let playback: PlaybackService
    let nowPlaying: NowPlayingCenter

    init() {
        let credentials = KeychainCredentialStore()
        let client = SubsonicClient(credentials: credentials)
        let playback = PlaybackService(client: client)
        let nowPlaying = NowPlayingCenter()

        self.credentials = credentials
        self.client = client
        self.playback = playback
        self.nowPlaying = nowPlaying
        self.connection = ConnectionModel(client: client, credentials: credentials)
        self.library = LibraryModel(client: client)
        self.player = PlayerModel(playback: playback, nowPlaying: nowPlaying,
                                  scrobbler: { id, submission in
            // Best-effort: a failed scrobble should never surface in the UI.
            _ = try? await client.sendStatus(.scrobble(id: id, submission: submission))
        })

        // Give the shared artwork cache access to the authenticated client, and
        // scope it to the current server so artwork never mixes across servers.
        ArtworkCache.shared.clientBox = ClientBox(client)
        ArtworkCache.shared.setServer(baseURL: credentials.load()?.baseURL)
    }
}
