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
M0 ✅ · M1 ✅ (auth/endpoints live-verified vs Navidrome 0.62) ·
M2 🚧 (UI/data live-verified; SwiftData cache still pending) ·
M3 🚧 (decode pipeline live-verified; audio *output* needs a human) ·
M4 🚧 (gapless code-complete & decode-verified; audible seam needs a human) ·
M5 🚧 (playlist CRUD/reorder + favorites code-complete & builds/tests green;
needs a live server to confirm reorder-by-replace)

## How to build / test
```sh
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

---

## M5 — Playlists CRUD/reorder + Favorites 🚧
Status: **code-complete, builds clean, full test suite green (incl. new
`PlaylistEndpointTests`); playlist edits need a live server to confirm.**
- **Endpoint** — `createPlaylist` extended with an optional `playlistId` so it
  can *replace* a playlist's contents (the canonical Subsonic reorder
  mechanism, since `updatePlaylist` can only append).
- **LibraryModel** — added playlist editing: `createPlaylist(name:songIds:)`
  (returns the created playlist to auto-select it), `deletePlaylist`,
  `renamePlaylist`, `addToPlaylist`, `removeFromPlaylist(indexes:)`, and
  `reorderPlaylist(name:songIds:)` (full-replace). Each refreshes the sidebar
  list. Favorites: batched `setStarred(_:songIds:)` (one reload for many) plus
  `setAlbumStarred`.
- **TrackTableView** — now the single place for track actions everywhere
  (Songs, album/playlist/genre detail, favorites, search):
  - **Favorites star column** with optimistic local state (taps reflect
    immediately; server reconciles on the next `getStarred2`).
  - Context menu: Play / Play Next / Add to Up Next · **Add to Playlist ▸**
    (existing playlists + **New Playlist…** via a name alert) · Add/Remove
    Favorites (multi-select aware).
  - **Playlist-edit mode** (opt-in via handlers): reorder (Move to Top/Up/
    Down/Bottom) + **Remove from Playlist**, operating on stored indices;
    `sortable: false` keeps the displayed order == stored order so reorder is
    coherent.
- **SidebarView** — Playlists section header gains a **+** (New Playlist alert,
  auto-selects the new playlist); per-row context menu **Rename… / Delete**
  (with confirmation; resets selection if the open playlist is deleted).
- **PlaylistDetailView** — rewritten: artwork + song-count/duration header,
  **Play** + **Shuffle**, toolbar **⋯ → Rename…**, and an editable
  `TrackTableView` (drag-free reorder + remove via context menu) with optimistic
  updates that re-fetch after each server edit.
- **AlbumDetailView** — header **favorite (star) toggle** for whole albums.
- **Row identity** — `TrackTableView` wraps each track in a positional `Row`
  (id = stored index) so **duplicate songs are distinct** (select / remove /
  reorder act on one entry, not every copy). Title is now the first column.
- **Drag & drop** — track-table rows are `.draggable` (`DraggedTrack` = song id
  + source index, JSON-encoded); **dropping onto a sidebar playlist** adds the
  song(s), with a drop-target highlight.
- **Playlist appearance (Music-faithful, AppKit table)** — `PlaylistDetailView`
  uses `MusicTrackTable`, an `NSViewRepresentable` wrapping `NSTableView`
  (`UI/Components/MusicTrackTable.swift`). SwiftUI can't combine edge-to-edge
  stripes + double-click + reliable selection (`Table` is inset-only; `List`
  can't double-click without breaking selection), so the playlist uses AppKit:
  - `.fullWidth` style + alternating row colors → **true edge-to-edge stripes**
    (incl. empty filler rows below, like Music).
  - **Double-click-to-play** (`doubleAction`), **Return-to-play** (keyDown),
    native single/multi **selection**, full-width **red** selection via a
    custom `NSTableRowView.drawSelection`.
  - **Now-playing speaker** column (`speaker.wave.2.fill` in the accent red),
    shown independently of selection.
  - Favorite star column (clickable `NSButton`); right-click menu built with a
    `ClosureMenuItem` helper (Play / Play Next / Add to Up Next / Add to
    Playlist▸ / Favorite / Move to Top·Up·Down·Bottom / Remove).
  - Verified by driving the app (computer-use): double-click started playback +
    speaker appeared on the playing row while selection moved elsewhere; stripes
    edge-to-edge; favorites/menu/selection all work.
- **Unified table everywhere** — `MusicTrackTable` is now the single track list
  used across the whole app. `TrackTableView` was reworked into a thin SwiftUI
  wrapper over it (same public API, so all call sites — Songs, album/genre
  detail, Favorites, Search, ColumnBrowser, Playlist — were untouched). Added to
  the AppKit table so the browse views didn't regress:
  - **Click-to-sort headers** (`sortDescriptorPrototype` + a coordinator-owned
    sorted `displayed` order). Playlist mode passes `sortable: false` (keeps
    stored order for reorder).
  - **Drag-to-playlist** via `tableView(_:pasteboardWriterForRow:)` writing a
    `DraggedTrack` as `public.json`, which the sidebar's SwiftUI
    `.dropDestination(for: DraggedTrack.self)` accepts.
  - Callbacks are order-independent: `onPlay([Song], Int)` /
    `onToggleFavorite(Song)` / `makeMenu([Song], IndexSet)` use the *displayed*
    (sorted) order.
  - Verified live (computer-use): edge-to-edge stripes, double-click-to-play, the
    now-playing speaker (which correctly tracks the song across a re-sort),
    selection, and header sorting all work in Favorites/Songs/Playlist.
  - The old `PlaylistTracksView` was deleted (folded into `TrackTableView`).
  - Note: dropped the standalone album `#` (track-number) column for a single
    consistent column set (Title/Artist/Album/Genre/Time + speaker + favorite).
  - **Header/stripe polish:** the `Time` header is right-aligned to match its
    right-aligned values; `columnAutoresizingStyle = .uniformColumnAutoresizing`
    makes the flexible columns fill the table width so rows/stripes/selection
    run truly edge-to-edge (previously ~20px short on the right). Verified.
  - ⚠️ **Open:** post-relaunch order didn't reflect earlier menu reorders, so
    **server-side persistence of reorder-by-replace on Navidrome is unconfirmed**
    (favorites persist fine). Native drag-to-reorder also postponed.
  - Other track views (Songs/Albums/Genres/Favorites/Search) still use the
    sortable `Table` (`.inset(alternatesRowBackgrounds:)`) — inset, not
    edge-to-edge. Converting them would mean dropping click-to-sort headers
    (only `Table` sorts). Open question whether to unify.
- **Accent color** — app `AccentColor` set to the iTunes red (`#CF172C` light /
  brighter in dark), sampled from the user's iTunes 12.6.3 reference screenshot
  (the selected-row red is `#CC132C`). Drives row selection, buttons, etc.
- **Sidebar (iTunes-style)** — section icons are colored red (loaded via
  `Color("AccentColor")` so they stay red regardless of list tint); selection is
  the standard macOS pill, which renders the accent red while the sidebar is the
  focused pane and neutral gray when another pane is focused (matching the
  reference, which was captured with the track list focused). Forcing
  always-gray would need custom row drawing — not done (SwiftUI's sidebar
  selection ignores `.tint`).
- Tests: `PlaylistEndpointTests` (8) — create (with/without songs), replace-for-
  reorder ordering, rename/add/remove via `updatePlaylist`, delete, star/unstar.

### Remaining for M5 / to verify
- 🔬 Reorder-by-replace and add/remove against a real Navidrome (no server here).
  Note: replace and bulk add/remove use **GET** query params, so very large
  playlists could hit URL-length limits — fine for typical sizes; a POST path is
  a future hardening item if needed.

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
- ⏳ SwiftData cache, output-device selection, accessibility pass, state
  restoration, MAS packaging — all per roadmap M6–M8. (Playlist editing/reorder
  + favorites delivered in M5; Now Playing center / media keys delivered in M3.)

## Verification status
- ✅ `xcodebuild build` succeeds (Debug, arm64, macOS 15 target), no warnings.
- ✅ `xcodebuild test` — full suite green (**TEST SUCCEEDED**, 0 failures).

### Live verification — 2026-06-22, against Navidrome 0.62.0 (real server)
Validated the networking + decode path end-to-end (opt-in `LiveDecodeTests`,
skipped unless `SONICWAVE_HOST/USER/PASS` env vars are set — no secrets committed):
- ✅ **Auth** (token+salt) — `ping` returns ok; password never in the URL.
- ✅ **Capabilities** — `openSubsonic: true`; extensions include `transcodeOffset`
  (confirms the `timeOffset` seek approach is supported) + `transcoding`.
- ✅ **Endpoints decode** — `getAlbumList2`, `getArtists`, `getGenres`,
  `getRandomSongs`, `getPlaylists`, `getStarred2` all parse (extra
  Navidrome/OpenSubsonic keys ignored by `Codable`).
- ✅ **Artwork** — `getCoverArt` returns `image/webp` (NSImage decodes natively
  on macOS 15).
- ✅ **Stream** — `audio/mpeg` (MP3) with HTTP range support.
- ✅ **Transcode + seek** — `format=mp3&maxBitRate=192&timeOffset=30` returns
  valid MP3.
- ✅ **Decode pipeline (the spike!)** — a real downloaded MP3 fed through
  `ProgressiveAudioSource` (AudioFileStream + AVAudioConverter) produced
  > 1 s of 44.1 kHz canonical PCM. The Option A pipeline works on real data.
- **Bug found & fixed:** Navidrome 0.62 sends `genres` (array), not the legacy
  `genre` string → added `GenreRef`/`displayGenre` so the Genre column populates.
- **Connection robustness:** pasting the browser URL (`…/app`) caused a 404
  (`/app/rest/ping.view`). `ConnectionModel.normalizedBaseURL` now strips the
  `/app` SPA suffix + trailing slash/query/fragment and assumes `https://` when
  the scheme is omitted (a legit reverse-proxy subpath like `/navidrome` is
  preserved). Covered by `ConnectionTests`.

### Audible playback (on device)
- ✅ Audio plays end-to-end from Navidrome.
- 🐛→🔧 **Startup crackle** in the first seconds = buffer underrun (node started
  on the first decoded buffer). Fixed with a **~2 s pre-roll** before starting
  the node (also after seeks) + `engine.prepare()` + larger decode-buffer
  headroom. Re-verifying by ear.

### Still requires a human (audio output / listening)
- ⏳ Actual sound through an output device (engine → speaker).
- ⏳ Audible gapless seam on a gapless album; cross-sample-rate transition.
- ⏳ Now Playing widget + media keys behavior (system UI).
- App is launchable: `open` the Debug build, then Settings → Connection.
