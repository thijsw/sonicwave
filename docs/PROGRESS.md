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
- **Debug builds sign with the Developer ID identity** (Huell B.V.,
  `4HNWJ993V9`; manual style, hardened runtime off for Debug). Ad-hoc signing
  gave every build a new designated requirement, so the keychain re-prompted
  for the server credential on each rebuild; the certificate-based requirement
  is stable, so one "Always Allow" sticks. Release is untouched.

## Milestone status
M0 ✅ · M1 ✅ (auth/endpoints live-verified vs Navidrome 0.62) ·
M2 ✅ (UI/data live-verified; SwiftData cache dropped — network-required by
design; artwork cached on disk) ·
M3 ✅ (playback live-verified end-to-end; seek + Now Playing/media keys work) ·
M4 ✅ (gapless human-confirmed seamless 2026-07-03; only a cross-sample-rate
transition remains untested — needs mixed-rate tracks in the library) ·
M5 ✅ (playlist CRUD + reorder-by-replace verified vs Navidrome 0.62
2026-07-03; favorites persist) ·
M6 ✅ (MenuBarExtra panel + search verified; output-device switching,
vanish-fallback and re-pin human-verified vs a USB DAC 2026-07-05) ·
M7 🚧 (media keys hardened; restoration — last section, table sort,
column-browser selections — live-verified 2026-07-07; ⌘N/volume/⌘L shortcuts
live-verified; accessibility labels on icon-only controls; appearance polish
done. Remaining: deeper VoiceOver sweep, scroll-position restoration) ·
M8 ⏳ (not started)

## How to build / test
```sh
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

---

## M7 quick wins — shortcuts + restoration (2026-07-07)
Status: **done & live-verified by driving the app (computer-use).**
- **File → New Playlist… (⌘N)** replaces New Window (like Music); routed to
  the sidebar's existing New Playlist prompt via an observable request
  counter on `AppModel`. Disabled when disconnected.
- **Controls gains** Increase/Decrease Volume (⌘↑/⌘↓, ±0.1) and a current-track
  favorite toggle (⌘L) whose title tracks the starred state ("Add to/Remove
  from Favorites"); it loads the starred list first so the toggle is truthful.
- **Table-sort persistence**: `MusicTrackTable` takes a `sortAutosaveKey`
  (one slot per view kind: songs/favorites/browser/album/search); the sort
  key + direction persist to UserDefaults (`trackSort.<key>`) and are restored
  on creation — only for columns that still exist. Playlists are exempt
  (stored order is the reorder surface).
- **Column-browser selections persist** (`browser.genre/artist/album` via
  `@AppStorage`); the reset cascade moved into the binding setters so a
  restore doesn't clear the restored artist/album, and the genre's songs are
  reloaded on appearance.
- Verified live: ⌘N opened the prompt; ⌘↓/⌘↑ moved the toolbar volume
  slider; ⌘L unstarred the playing track (row left Favorites) and re-starred
  it; Rock → Jimi Hendrix + Title-sort survived a full quit/relaunch
  (defaults inspected: `trackSort.browser = "title|asc"`, flips to desc on
  re-click); playlist view stayed in stored order with no sort applied.

## Tooling — SwiftLint (2026-07-06)
Status: **done; lint clean, build warnings unchanged, all 66 tests green.**
- SwiftLint 0.65 installed (Homebrew) with a near-default `.swiftlint.yml`
  (only idiomatic short names `id/i/x/y/lo/hi` excluded from
  `identifier_name`). 125 violations fixed to zero.
- Along the way: `MusicTrackTable`'s cell/row views moved to
  `TrackTableCells.swift`; `PlaybackState`/`RepeatMode` moved to
  `Models/PlaybackTypes.swift`; oversized functions split
  (`viewFor` cell builders, `handlePackets` input helpers, context-menu
  sections); `PlaybackService`'s 7-param decode functions bundled into a
  `DecodeRequest`; `PlaybackService`/`PlayerModel` reorganized into same-file
  extensions per functional area. One justified `file_length` disable stays in
  `PlaybackService.swift` (splitting the actor would expose its private
  state). No behavior changes.

## Hardware sample-rate matching (2026-07-05)
Status: **done & human-verified against a USB DAC (CXA81, 44.1k–705.6k).**
Audirvana/Roon-style bit-perfect-style output, on by default (Settings →
Playback → "Match hardware sample rate"); full design in
`03-playback-engine.md`:
- Each hard start re-derives the timeline format from the track's **native
  sample rate** (`ProgressiveAudioSource.chooseOutput` picks the output format
  at source discovery — no software resample for native-rate tracks), and the
  node is reconnected when the rate differs from the current connection.
- The output device's **nominal hardware rate** is set to the closest
  supported match (`AudioOutputDevices.bestSupportedRate/setNominalSampleRate`),
  so nothing resamples between file and DAC. Gapless followers join the
  running timeline's format (resampled only if they differ).
- Deliberate rate switches fire config-change notifications — swallowed as
  echoes via the recovery guard. With matching off, timelines return to the
  fixed 44.1 kHz base format and the device's rate is never touched.
- Verified live: a 48 kHz pre-set device snapped to 44.1 kHz on play; with the
  toggle off an external 48 kHz set was left untouched. Remaining ideal-world
  gaps: bit depth stays float32 through the mixer (lossless for ≤24-bit
  sources); exclusive/hog-mode access not implemented.
- Same pass: the menu-bar icon now matches the app icon's waveform glyph, and
  `ArtworkView` gained a `placeholderSymbol` (menu-bar panel shows the
  waveform, glyph scales with view size).

## UI overhaul — Cadence design pass (2026-07-02/03)
Status: **done & live-verified (computer-use driving the real app).** The
visual direction moved from the old bottom-bar layout to the Cadence design
project (see `09-design-system.md` for the source). Highlights, with pointers
for anything the older sections below describe differently:
- **Now-playing toolbar** — transport (prev / accent play circle / next)
  leading, a centered "LCD" (artwork, title, artist — album, elapsed/total,
  accent progress hairline; click toggles the panel), volume + panel toggle
  trailing. `NowPlayingBar` (bottom bar) is gone; see `NowPlayingToolbar.swift`.
- **Now Playing panel** — `UpNextView` → `NowPlayingPanel.swift`: headerless
  inspector, full-bleed hero artwork to the window top, slim scrubber,
  transport with shuffle/repeat, aligned Up Next queue (drag-to-reorder,
  hover play/remove). Only presentable while something plays or is queued.
- **Search** — field pinned at the top of the sidebar
  (`.searchable(placement: .sidebar)`, ⌘F focuses); results are artist/album
  shelves over the shared track table.
- **No NavigationStack** — in-place navigation via `Navigator` (opened album
  overlays the section with an inline Back link; Artists is a master-detail
  split). `GenresView` was folded into the column browser.
- **Consistency fixes** — shared `AlbumGridCell` (covers fill adaptive grid
  cells), column-browser panes match the table header style, content no
  longer scrolls under the transparent toolbar (pinned hairline).
- **Menu-bar panel** — restyled to the same design language (slim scrubber +
  times, accent play, shuffle/repeat).
- Gotchas discovered (recorded in `04-ui-ux.md`): custom toolbar items can't
  live above the sidebar; row tap gestures kill List drag-reordering;
  `.toolbarBackground(.visible)` is a no-op under `.hiddenTitleBar`.
- **Stability: gapless events vs. queue edits.** The engine echoes the queue
  position a track had at hand-off; queue edits after hand-off shift
  positions, so `PlayerModel` now translates every `.trackChanged`/`.wantNext`
  through a `spanPositions` map (hand-off echo → current position), adjusted
  positionally by move/remove/insert alongside `currentIndex`. Unknown echoes
  (stale across a hard restart) are ignored rather than advanced into.
  `handle(_:)` is internal so tests drive engine events directly (3 tests).

## M6 — MenuBarExtra, search, output device ✅
Status: **complete — multi-device switching + route changes human-verified
2026-07-05 (USB DAC); see the bullets below.**
- **MenuBarExtra `.window` panel** — `MenuBarPanel` shares the same `PlayerModel`
  as the main window (artwork, scrubber, prev/play-pause/next). Verified live: the
  menu-bar popover reflects and controls the current track independently of the
  main window.
- **Global search** — `search3` via `.searchable`, with a 250 ms debounce and
  per-keystroke cancellation (`.task(id:)` in `SearchResultsView`). Already in
  place from M2; confirmed it meets the M6 bar.
- **Output-device selection** (new):
  - `Playback/AudioOutputDevices.swift` — Core Audio enumeration of
    output-capable devices (`AudioDevice` = id/uid/name), default-device lookup,
    and UID→id resolution (UID is the stable, persisted identifier).
  - `PlaybackService` — `setOutputDevice(uid:)` persists the choice and applies it
    to the engine's output unit (`kAudioOutputUnitProperty_CurrentDevice`),
    applied at engine connect and re-applied on every
    `.AVAudioEngineConfigurationChange` (route change / default-device change /
    format change) so playback follows the new route; falls back to the system
    default when the chosen device is gone.
  - Settings → Playback gains an **Output Device** picker (System Default +
    devices), persisted via `@AppStorage("outputDeviceUID")`.
  - Verified live (computer-use): picker enumerates real devices (System Default +
    MacBook Pro Speakers), selecting an explicit device persists and plays with
    no engine errors / 0 IO overloads.
  - ✅ **Multi-device switching + route changes human-verified (2026-07-05)**
    against a USB DAC (Cambridge Audio CXA81) alongside MacBook/Studio Display
    speakers: mid-track switches amp → speakers → amp all audible; yanking the
    amp's USB mid-track fell back to the system default and kept playing from
    the playhead; replugging re-pinned to the amp automatically. Findings
    fixed along the way (see `PlaybackService`/`AudioOutputDevices`):
    - A **live device swap wedges the render graph silently when hardware
      formats differ** (USB DAC at 44.1 kHz vs speakers) — audio gone until a
      rebuild, unrecoverable by switching back. All route changes (manual
      switch, vanish, return) now rebuild the engine and hard-restart the
      stream at the playhead (`recoverPlayback`, reusing the seek path) — a
      sub-second gap, reliable on any hardware.
    - `AVAudioEngineConfigurationChange` does **not** fire when a *pinned*
      device vanishes: a `kAudioHardwarePropertyDevices` listener
      (`AudioDeviceListObserver`) drives vanish-fallback / return-re-pin.
    - Settings device picker refreshes live on connect/disconnect, shows a
      "(disconnected)" row (persisted device name) while the choice is absent,
      and filters Core Audio's transient private aggregates.
    - Sonicwave never touches the system default — other apps' routing is
      fully independent (macOS's own Bluetooth default auto-switch is not
      ours to control).

## M5 — Playlists CRUD/reorder + Favorites ✅
Status: **complete — reorder-by-replace + add/remove verified against
Navidrome 0.62 (2026-07-03; see "Remaining for M5" below).**
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
- ✅ **Reorder-by-replace + add/remove verified against Navidrome 0.62
  (2026-07-03),** driving the real app: Move to Top persisted across a full
  relaunch (fresh `getPlaylist` fetch); Move Up/Down round-trips; Remove took
  out only the targeted entry with a duplicated song present; Add to
  Playlist ▸ appended; a final relaunch fetched the exact restored order —
  duplicates intact throughout. (The earlier "post-relaunch order didn't
  reflect reorders" observation did not reproduce.)
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

## M4 — Gapless + queue + column browser ✅
Status: **complete — gapless human-confirmed seamless 2026-07-03** (see
"Remaining for M4" below for the verification details).
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
- ✅ **Gapless seam instrumentally verified (2026-07-03):** three consecutive
  Abbey Road medley boundaries (Golden Slumbers → Carry That Weight → The End
  → Her Majesty) crossed on-device with **zero underruns** (the starvation
  detector never fired) and **zero HAL overloads/skipped IO cycles** in the
  unified log; the album played to completion. Found & fixed along the way:
  pre-buffer streams suspended by the read-ahead throttle were hitting
  URLSession's default 60 s request timeout (-1001) — the loader now uses a
  600 s request timeout since long idle is by design. Remaining known log
  noise: one benign `AudioConverter … packet descriptions (0)` complaint per
  track at the end-of-stream flush (decode continuity is test-verified).
  **Human-confirmed seamless by ear (2026-07-03)** — the M4 gapless-seam exit
  criterion is met. Still open from that checklist: a cross-sample-rate
  (44.1↔48 k) transition, untestable until the library has mixed-rate tracks.
- 🔬 Sample-rate change across tracks (44.1↔48 k) audibly clean — device-only.
- 🔬 Magic-cookie formats (AAC-in-MP4) — `AVAudioConverter` has no cookie API;
  ADTS/MP3/FLAC are fine; documented limitation in `03-playback-engine.md`.

## M3 — Single-track playback + system integration ✅
Status: **complete — playback verified end-to-end on device** (audio plays
from Navidrome, seek verified, media keys hardened during M7 work; see
"Audible playback" below for the crackle/seek forensics).
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

### M2 notes
- ❌ SwiftData persistence layer — **dropped.** The app is network-required by
  design (no offline playback), so library metadata stays in-memory per
  `LibraryModel`. Artwork is cached persistently on disk instead
  (`Services/ArtworkCache.swift`); see `05-data-and-caching.md`.
- ✅ Column browser (Genre → Artist → Album) — delivered in M4.

## Known limitations / deferrals
- ⏳ **Songs view uses `getRandomSongs`** (Subsonic has no "all songs"
  endpoint). Tracked for a fuller aggregation later (see
  `05-data-and-caching.md`).
- ✅ ~~Playback is stubbed~~ — superseded: the real `AVAudioEngine` streaming +
  gapless engine landed in M3/M4 (`03-playback-engine.md`).
- ⏳ Accessibility pass, state restoration, MAS packaging — per roadmap M7–M8.
  (SwiftData cache dropped; output-device selection delivered in M6; playlist
  editing/reorder + favorites in M5; Now Playing center / media keys in M3.)

## Verification status
- ✅ `xcodebuild build` succeeds (Debug, arm64, macOS 15 target) with
  **zero compiler warnings** (clean build; the former ~29-warning baseline was
  eliminated 2026-07-07 — always-true casts collapsed via typed throws,
  `MusicTrackTable.Coordinator` made `@MainActor`, converter input flags
  boxed, date decoding moved to Sendable `Date.ISO8601FormatStyle`).
- ✅ `xcodebuild test` — full suite green (**TEST SUCCEEDED**, 66 tests,
  0 failures).

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
- 🔬 **Crackle investigation (evidence-based).** Rather than enlarge buffers:
  - **Decode/convert exonerated.** A self-contained test (`DecodeContinuityTests`)
    encodes a pure sine → AAC/ADTS → decodes it through the *real*
    `ProgressiveAudioSource` and measures sample-to-sample steps: the max interior
    step (~0.0324) equals the sine's natural slope (~0.0313) → **no glitches /
    sample corruption** in the per-batch conversion. (The synthetic ADTS stream
    under-decodes — an AudioFileStream/ADTS harness quirk — so real-file
    completeness + boundary continuity is covered by the extended `LiveDecodeTests`
    instead.)
  - **Found & fixed a real bug:** the converter's tail was never flushed —
    `ProgressiveAudioSource.finish()` now runs a final `.endOfStream` conversion
    (`flushDecoder()`) so the end of each track isn't dropped (clipped endings /
    gapless-seam clicks).
  - **Runtime underrun detector:** `PlaybackService` logs (os.Logger, category
    `playback`) when the player node starves. In a captured Console log it
    **never fired** → the crackle was *not* underrun.
  - 🐛→✅ **ROOT CAUSE FOUND (from the Console log):** repeated
    `AVAudioCompressedBuffer initWithFormat … required condition is false:
    (!(fmt.IsLinearPCM()…))`. `ProgressiveAudioSource` always wrapped packets in
    an `AVAudioCompressedBuffer`, but for **uncompressed (linear-PCM) sources —
    WAV/AIFF —** that buffer is invalid, so those tracks decoded to garbage →
    crackle. Matches the symptom exactly (only *some* songs cracked). **Fix:**
    when the source format is linear PCM, wrap the frames in an `AVAudioPCMBuffer`
    instead (compressed path unchanged). Verified clean build + tests.
  - Earlier mitigation (~2 s pre-roll + `engine.prepare()`) remains.
- 🐛→✅ **ROOT CAUSE of the remaining single click (~1 s into PCM tracks).** After
  the PCM fix, AIFF still produced one reproducible click. Traced with a render
  tap (output data was clean — `maxStep 0.157`, no discontinuity) + unified-log
  correlation: a single `HALC_ProxyIOContext … skipping cycle due to overload`
  fired ~1 s into playback. The audio **device dropped one IO cycle** (the glitch
  is after the engine, so not in the rendered samples). Cause: a track decodes
  *far* faster than real time, so its buffers are scheduled in one big burst —
  and **linear-PCM (AIFF/WAV) yields ~2× as many buffers** (~2800 for a 3:49
  track) as compressed, flooding `scheduleBuffer` and starving the IO thread
  (hence PCM-only). **Fix:** `ProgressiveAudioSource` now **consolidates** the
  many small per-batch decoder outputs into ~1-second buffers before yielding,
  cutting `scheduleBuffer` calls ~12×. Verified: the overload no longer appears
  in the log when playing the AIFF.
- **Bounded read-ahead (paced scheduling).** Following the standard streaming
  model (cf. AudioStreaming / SwiftAudioPlayer / the AVAudioEngine streaming
  writeup), decoding/scheduling no longer runs unbounded ahead of playback.
  `PlaybackService.throttleReadAhead` keeps the buffered look-ahead between ~8 s
  and ~15 s (both well above the 2 s pre-roll): once 15 s ahead it **suspends the
  URLSession transfer and pauses decoding**, resuming when playback drains to
  8 s. Bounds memory (a whole track is no longer held decoded in RAM) and smooths
  scheduling. `DataStreamLoader` gained `pause()`/`resume()`
  (`URLSessionDataTask.suspend/resume` → TCP back-pressure). Verified: the AIFF
  stays at 0 overloads and decode is paced (no early burst to completion).
- 🐛→✅ **Seek restarted the track from 0.** The Subsonic `timeOffset` parameter
  only seeks *transcoded* streams (the OpenSubsonic `transcodeOffset` extension);
  on an original-file stream (the default, transcoding off) the server ignores it
  and plays from the start. **Fix:** when not transcoding, `runDecode` streams from
  0 and `ProgressiveAudioSource` **discards decoded output up to the seek point**
  (`skipFrames`, sample-precise, works for every format); when transcoding it
  still uses the efficient server-side `timeOffset`. Verified by driving the app:
  scrubbing to ~2:00 resumes playback from 2:00 (0 overloads). Note: the
  non-transcoded path re-reads from the start up to the seek point (fine on a fast
  connection; a future byte-range/`AudioFileStreamSeek` optimization could avoid
  the re-read for self-syncing formats).

### Still requires a human (audio output / listening)
- ✅ Actual sound through an output device — verified (see "Audible playback").
- ✅ Audible gapless seam — human-confirmed 2026-07-03 (Abbey Road medley).
- ⏳ Cross-sample-rate transition (44.1↔48 k) — untestable until the library
  has mixed-rate tracks.
- ✅ Now Playing widget + media keys — hardened & verified during the M7 pass.
- App is launchable: `open` the Debug build, then Settings → Connection.
