# Build Progress Log

A running record of what's been implemented, verified, and deferred. Newest
milestone first. See `10-roadmap.md` for the full milestone plan.

## Conventions
- ✅ done & verified · 🚧 in progress · ⏳ deferred (tracked) · 🔬 spike pending

## Environment
- Xcode 26.3, Swift 6.2.4, macOS 15 SDK. Swift 6 language mode (strict
  concurrency) enabled on all targets.
- Bundle identifier: `nl.huell.sonicwave`. App Sandbox + `network.client`
  entitlement; Hardened Runtime on.
- Project uses Xcode 16+ **synchronized file groups**, so new `.swift` files
  under `Sonicwave/` and `SonicwaveTests/` are picked up automatically without
  editing the project file.

## How to build / test
```sh
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

---

## M0 — Foundation ✅
Status: **complete, builds clean.**
- `Sonicwave.xcodeproj` (app + unit-test targets), synchronized file groups.
- App Sandbox + `network.client` entitlement (`Sonicwave/Sonicwave.entitlements`),
  Hardened Runtime, generated Info.plist (min macOS 15, music category,
  `nl.huell.sonicwave`).
- Scenes wired in `App/SonicwaveApp.swift`: `WindowGroup`, `Settings`,
  `MenuBarExtra(.window)`; shared `@Observable` models injected via environment.
- `App/AppModel.swift` composition root owning services + models.
- Asset catalog with `AppIcon` (placeholder) + `AccentColor`.

## M1 — Connectivity & auth ✅
Status: **complete, builds clean, 18 unit tests passing.**
- `Services/SubsonicClient.swift` — actor; request builder
  (`/rest/<method>.view`, common params `v/c/f=json`), envelope decode, typed
  `SubsonicError` mapping, capability fields surfaced via `ServerInfo`.
- Auth: token+salt (`md5(secret+salt)` via CryptoKit, random salt per request)
  and OpenSubsonic `apiKey`. Secret never appears in the URL; token never
  persisted.
- `Services/CredentialStore.swift` — Keychain-backed store (+ in-memory store
  for tests/previews).
- `Models/ConnectionModel.swift` — connection state machine, Test Connection
  (`ping`), Save & Connect (persists to Keychain), refresh at launch,
  transcoding prefs (UserDefaults).
- `UI/Settings/SettingsView.swift` — Connection + Playback tabs (server,
  auth method, Test/Save/Disconnect, transcoding format/bitrate).
- Tests: `AuthTests`, `DecodingTests`, `RequestBuildingTests`,
  `PlayerQueueTests` — md5 vectors, salt randomness, URL/auth construction for
  both methods, transcoding params, envelope/model/date decoding, failed-status
  → error, queue/transport logic.

## M2 — Library browse 🚧
Status: **UI + data flow working in-memory; SwiftData cache not yet wired.**
- `Networking/SubsonicModels.swift` value types (Song/Album/Artist/Genre/Playlist);
  `Networking/Endpoint.swift` endpoint map; `Networking/SubsonicResponse.swift`
  envelope + per-endpoint bodies.
- `Models/LibraryModel.swift` — albums (paginated via `getAlbumList2`), artists
  (`getArtists`), genres, songs (random sample — see limitation), favorites
  (`getStarred2`), playlists, search (`search3`), album/artist/genre detail,
  star/unstar.
- UI: `RootView` (NavigationSplitView + bottom now-playing bar + not-connected
  overlay + global search), `SidebarView` (Library + Playlists sections),
  `AlbumsView` (grid + infinite scroll), `AlbumDetailView`, `ArtistsView`
  (+ detail), `SongsView`, `GenresView` (+ detail), `FavoritesView`,
  `PlaylistDetailView`, `SearchResultsView`, `TrackTableView` (sortable, context
  menu, play/enqueue), `ArtworkView` + `Services/ArtworkCache.swift` (NSCache,
  server-resized, in-flight dedup).
- `UI/NowPlaying/NowPlayingBar.swift`, `UI/MenuBar/MenuBarPanel.swift`,
  `App/SonicwaveCommands.swift` (Controls menu + shortcuts).

### Remaining for M2
- 🚧 SwiftData persistence layer (`Persistence/`) — currently library data is
  held in memory per `LibraryModel`; the on-disk cache + offset persistence from
  `05-data-and-caching.md` is not yet implemented.
- 🚧 Column browser (Genre → Artist → Album) — planned for M4 per roadmap.

## Known limitations / deferrals
- ⏳ **Songs view uses `getRandomSongs`** (Subsonic has no "all songs"
  endpoint). Tracked for a fuller aggregation later (see
  `05-data-and-caching.md`).
- 🔬 **Playback is stubbed** — `PlayerModel` manages queue/transport state but
  no audio engine yet. Real `AVAudioEngine` streaming + gapless is M3/M4
  (`03-playback-engine.md`), the project's key spike.
- ⏳ SwiftData cache, Now Playing center / media keys, output-device selection,
  full playlist editing/reorder, accessibility pass, state restoration, MAS
  packaging — all per roadmap M2–M8.

## Verification status
- ✅ `xcodebuild build` succeeds (Debug, arm64, macOS 15 target).
- ✅ `xcodebuild test` — 18/18 passing.
- ⏳ Live run against a Navidrome server not yet exercised in this environment
  (no server configured); Settings → Test Connection is the entry point.
