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

## Milestone status
M0 ✅ · M1 ✅ · M2 🚧 (UI/data in-memory; SwiftData cache pending) ·
M3 🚧 (code-complete, runtime audio unverified) ·
M4 🚧 (gapless + queue + column browser code-complete; gapless needs device verification)

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

## M4 — Gapless + queue + column browser 🚧
Status: **code-complete & builds clean (tests green); gapless transitions need
device verification** (no server/audio device here).
- **Gapless engine** — `PlaybackService` reworked to decode **every track to one
  canonical format** (44.1 kHz/stereo float) and schedule consecutive tracks
  back-to-back on a single `AVAudioPlayerNode` (no stop between tracks), so
  transitions are seamless and **sample-rate changes are handled by resampling**.
  Pre-buffering uses a **pull model**: when a track finishes decoding the service
  emits `.wantNext(afterIndex:)`, `PlayerModel` replies `enqueueNext`/
  `enqueueNoMore`. Track boundaries detected via sample-time **spans** →
  `.trackChanged(index)`; `.ended` only when the last track finishes.
  `ProgressiveAudioSource` now decodes to the supplied canonical format.
- **PlayerModel** — gapless coordination (`gaplessAdvance`, `provideNext`,
  auto vs manual successor incl. repeat-one loop / repeat-all wrap). Manual
  skip/seek hard-restart (a brief gap is expected, by design).
- **Up Next UI** — `UI/NowPlaying/UpNextView.swift` shown as an `.inspector`
  (⌘U / toolbar / View menu): now-playing + upcoming, **drag reorder**, remove,
  **play-from-here**, clear. Backed by tested `PlayerModel` queue editing
  (`moveQueue`, `removeFromQueue`, `clearUpNext`, `playFromQueue`).
- **Column browser** — `UI/Library/ColumnBrowserView.swift`: Genre → Artist →
  Album panes above a filtered `TrackTableView`; selections narrow panes to the
  right + the tracks below. Toggle via View menu (⌥⌘B) / `SongsView`.
- Tests: `QueueEditingTests` (7) added; full suite green.

### Remaining for M4 / to verify
- 🔬 Gapless seam (no gap/overlap) on a real gapless album — device-only.
- 🔬 Sample-rate change across tracks (44.1↔48 k) audibly clean — device-only.
- 🔬 Magic-cookie formats (AAC-in-MP4) — `AVAudioConverter` has no cookie API;
  ADTS/MP3/FLAC are fine; documented limitation in `03-playback-engine.md`.

## M3 — Single-track playback + system integration 🚧
Status: **code-complete & builds clean (25 unit tests pass); runtime audio not
yet verified** (needs a live Navidrome server + audio device — unavailable in
this headless env).
- **Decision:** Option A (progressive decode) is the committed streaming source
  (see `03-playback-engine.md`). Option B kept as fallback.
- `Playback/PlaybackService.swift` — actor owning `AVAudioEngine` + one
  `AVAudioPlayerNode`. Drives loader → decoder → buffer scheduling. Play / pause
  / resume / seek / stop / volume; sample-time position throttled to ~5 Hz via an
  `AsyncStream<PlaybackEvent>`; App Nap / idle-sleep prevented via
  `ProcessInfo.beginActivity` while playing; lazy engine connect at the decoded
  format; teardown releases per-track resources.
- `Playback/DataStreamLoader.swift` — `URLSession` data-delegate → chunked
  `AsyncThrowingStream<Data>` (audio starts before full download).
- `Playback/ProgressiveAudioSource.swift` — Audio File Stream Services parser +
  `AVAudioConverter` producing `AVAudioPCMBuffer`s; format auto-detect + suffix
  hint; `SendablePCMBuffer` ownership transfer.
- `Playback/AudioStreamSource.swift` — protocol seam so Option B is droppable-in.
- `Services/NowPlayingCenter.swift` — `MPNowPlayingInfoCenter` metadata/artwork/
  elapsed + `MPRemoteCommandCenter` (play/pause/toggle/next/prev/seek) → **media
  keys**. Single writer to the system center.
- `Models/PlayerModel.swift` — rewritten to forward intent to `PlaybackService`
  and drive `state`/`position` from its events, while keeping queue/transport
  bookkeeping synchronous (so unit tests need no engine). Wires remote-command
  callbacks; pushes Now Playing metadata + async artwork.
- `App/AppModel.swift` — constructs and injects `PlaybackService` +
  `NowPlayingCenter`.
- Seek re-opens the stream with `timeOffset` (Option A has no random access);
  scrubbers in `NowPlayingBar`/`MenuBarPanel` seek once on release, not per drag.
- Tests added: `PlaybackConfigTests` (transcode prefs, `timeOffset` URL, file
  type hint) + existing `PlayerQueueTests` still green after the refactor.

### Remaining for M3 / to verify
- 🔬 Runtime: play/pause/seek a real track; confirm Now Playing widget + media
  keys; artwork + elapsed time. Needs live server.
- 🔬 Magic-cookie handling (AAC/ALAC) and seek accuracy are flagged for the M4
  spike (see `03-playback-engine.md`).

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
- ✅ Column browser (Genre → Artist → Album) — delivered in M4.

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
- ✅ `xcodebuild build` succeeds (Debug, arm64, macOS 15 target), no warnings.
- ✅ `xcodebuild test` — full suite green (32 test cases; **TEST SUCCEEDED**, 0 failures).
- ⏳ Live run against a Navidrome server not yet exercised in this environment
  (no server configured); Settings → Test Connection is the entry point, then
  play a track to exercise the M3 audio path.
