# 10 — Roadmap, Milestones & Sequencing

Phased build order with exit criteria and top risks. Each milestone is a
shippable-internally increment. The hardest item — streaming gapless via
`AVAudioEngine` — is isolated as a spike (M4) and de-risked by landing simpler
playback first (M3).

> **Live status:** M0 ✅ · M1 ✅ · M2 🚧 (UI/data in-memory; SwiftData cache
> pending) · M3 🚧 (code-complete & tested; runtime audio unverified) ·
> M4 🚧 (gapless + queue + column browser code-complete & tested; gapless seam
> needs device verification). See `PROGRESS.md` for the detailed build log.

## M0 — Foundation ✅
- Create the Xcode app project (macOS 15 deployment, Swift 6 language mode,
  Xcode 26 SDK), folder groups per `01`, unit-test + UI-test targets.
- App Sandbox + `network.client` entitlement; Hardened Runtime; Info.plist
  (min macOS 15, music category, versioning, icon placeholder) — `07`.
- Settings scene skeleton + `AuthStore` (Keychain) — `02`/`07`.
- App scenes wired: `WindowGroup`, `Settings`, `MenuBarExtra` (empty), shared
  `@Observable` models in the environment — `01`/`04`.
- **Exit:** app launches, builds against macOS 15 SDK, opens an empty shell +
  Settings; credentials persist to Keychain.

## M1 — Connectivity & auth ✅
- `SubsonicClient` (actor) + request builder + envelope decoding + error map.
- token+salt auth; API-key auth where supported; `getOpenSubsonicExtensions`
  capability detection — `02`.
- Settings: server URL/username/password (or API key) + **Test Connection**
  (`ping`).
- **Exit:** Test Connection succeeds against a Navidrome server; auth failures
  surface a clear re-auth path.

## M2 — Library browse 🚧
- `LibraryStore` (SwiftData) + paginated fetch for Albums/Artists/Songs/Genres
  — `05`/`02`.
- Sidebar (Library group), dense sortable `Table`, basic now-playing header
  (non-functional transport), artwork thumbnails via `ArtworkCache` — `04`/`05`.
- **Exit:** browse a large library smoothly with pagination; sort columns;
  scroll stays fluid; memory bounded.

## M3 — Single-track playback + system integration 🚧
- `PlaybackService` + `AVAudioEngine` graph playing **one track** (Option A
  progressive decode — committed decision) — `03`.
- `PlayerModel` intent (play/pause/seek), throttled position, now-playing header
  functional.
- `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` + media keys; App Nap
  prevention — `06`.
- **Exit:** play/pause/seek a track; Now Playing widget + media keys work;
  artwork + elapsed time correct.

## M4 — Gapless + queue + column browser 🚧 (highest risk)
- **Spike:** streaming **gapless** with dual player nodes + pre-buffering on the
  committed Option A progressive-decode pipeline; also harden Option A's known
  rough edges (magic cookie, seek accuracy) — `03`. Meet the M4 spike checklist.
- Up Next / queue (reorder, remove, play-from-here) — `04`.
- Column browser (Genre → Artist → Album) — `04`.
- **Exit:** gapless verified on a gapless album; sample-rate change handled;
  queue editing updates pre-buffer target; column browser filters the table.

## M5 — Playlists & favorites
- Playlists CRUD + **reorder** (`createPlaylist`/`updatePlaylist`/
  `deletePlaylist`); drag rows to playlists — `02`/`04`.
- Favorites: `getStarred2`, `star`/`unstar`, Favorites sidebar item, ★ column.
- **Exit:** full playlist lifecycle round-trips to the server; starring works
  everywhere.

## M6 — MenuBarExtra, search, output device
- `MenuBarExtra` `.window` Now Playing panel sharing `PlayerModel` — `04`.
- Global search (`search3`) with debounce/cancellation — `02`/`04`.
- Output-device enumeration/selection + route-change handling — `03`.
- **Exit:** menu-bar panel controls playback with main window closed; search is
  responsive; device switching is robust.

## M7 — Polish: accessibility, restoration, transcoding, appearance
- Accessibility pass (VoiceOver, Dynamic Type, contrast, keyboard nav) — `04`.
- State restoration (windows/selection/sort/scroll) — `06`.
- Transcoding settings (format/bitrate) wired to `stream` — `02`.
- Liquid Glass verification on Tahoe + Sequoia fallback; full menu/shortcuts —
  `04`.
- **Exit:** manual verification checklist in `08` passes.

## M8 — Distribution
- App icon, App Privacy details, reviewer notes/demo credentials — `07`.
- MAS signing/notarization pipeline; (optional) Developer ID build.
- Full unit + UI test pass on macOS 15 / Xcode 26 CI — `08`.
- **Exit:** signed MAS build uploads to App Store Connect; tests green.

## Risk register

| Risk | Milestone | Mitigation |
| --- | --- | --- |
| Streaming gapless decode complexity (Core Audio / format changes) | M3/M4 | Committed to Option A progressive decode; `AudioStreamSource` protocol keeps Option B droppable-in; M4 checklist gates; magic-cookie/seek hardening tracked |
| API-key auth availability varies by server | M1 | Capability detection; token+salt fallback |
| Output-device/route-change engine rebuilds cause glitches | M6 | Observe config-change + Core Audio listeners; rebuild + resume; manual test matrix |
| Subsonic JSON quirks (single-vs-array, string numbers) | M1 | Tolerant decoders + recorded fixtures (`08`) |
| Large-library performance/memory | M2/M5 | Pagination + virtualization + bounded caches (`05`) |
| Liquid Glass / Tahoe-only API drift | M7 | Standard controls only; `#available` guards (`04`) |
| App Review needs a working server | M8 | Demo credentials + graceful no-server onboarding |

## Out of scope (post-v1)
Offline caching/downloads, scrobbling, smart playlists, multi-server,
Cover Flow, local-file playback, tag editing — see `00`.
