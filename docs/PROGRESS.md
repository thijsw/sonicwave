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
  is stable, so one "Always Allow" sticks. Release signs Manual + Developer ID
  with the hardened runtime ON (see the M8 pipeline entry).

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
M7 ✅ (shortcuts, restoration incl. scroll offset, accessibility semantics
AX-verified, Light/Dark verified — the `08` checklist passes; only the
Liquid Glass look awaits a macOS 26 machine, plus by-hand VoiceOver/contrast
spot checks) ·
M8 🚧 (Developer ID pipeline complete incl. notarization + stapling —
Gatekeeper-accepted distributable build; CI runs the unit suite on every
push; remaining: MAS certificates/app record, final icon, App Privacy)

## How to build / test
```sh
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

---

## Fix: multi-song drags dropped into Up Next / playlists lost their order (2026-07-18)
SwiftUI hands multi-item drop payloads over in no guaranteed order, and all
three drop sites (Up Next `.onInsert`, empty-queue `.dropDestination`,
sidebar-playlist `.dropDestination`) consumed them as-received. Fix: sort
decoded `DraggedTrack`s by their `index` field (the source row index the
drag already carried) before inserting — restoring the on-screen order the
user grabbed. Human-reported after dragging an album's tracks to the queue.

## M10 discovery batch: artist info, Start Radio, album shuffle (2026-07-18)
Internet radio deliberately skipped (ICY-stream spike still open — `10`).
- **API:** `getArtistInfo2`, `getSimilarSongs2`, `getTopSongs` endpoints +
  bodies (`02` inventory updated). `getTopSongs` keys off artist *name*
  (API quirk). Bio HTML flattened client-side
  (`ArtistInfo2Body.Info.plainBiography` — drops the "Read more on Last.fm"
  anchor, strips tags, decodes entities; covered by a decode test).
- **Artist page:** header with circular portrait + Artist Radio button,
  expandable 3-line bio, Similar Artists shelf (search-shelf idiom,
  `navigator.openArtist`); artist-list rows get a Start Artist Radio
  context item. Data loads concurrently with the album grid; servers
  without a metadata agent simply hide bio/shelf (best-effort idiom).
- **Start Radio:** track-table context menu (single selection) +
  artist entry points. Chain: similar-by-song → similar-by-artist →
  server top songs → shuffled own-artist tracks (≤10 albums), so radio
  always plays on agent-less servers (the demo server exposed this).
  Seed song plays first; shuffle mode is switched off so station order
  holds.
- **Busy guard:** `AppModel.isPreparingMix` — mix assembly takes a beat
  (similar-songs then per-album fetches), so all radio/album-shuffle entry
  points disable while one is in flight (Artist Radio button swaps its
  icon for a spinner) and the methods bail re-entrantly.
- **Shuffle Albums:** whole albums back-to-back in random order — Controls
  menu + Albums-grid header button. Honors the genre/decade filter (server
  `type=random` unfiltered; filters are list types with no random order,
  so a 200-album filtered page is sampled client-side).
- **Verified:** 105 tests green, zero warnings, SwiftLint clean. All three
  endpoints live-checked against demo.navidrome.org (status ok, expected
  shapes; demo has no Last.fm agent → empty payloads exercised the
  fallback design). ✅ In-app flows (artist page, radio entry points,
  album shuffle) human-verified against a real server 2026-07-18.

## Deployment target lowered to macOS 14 Sonoma (2026-07-18)
`MACOSX_DEPLOYMENT_TARGET` 15.0 → 14.0 across all targets; README, docs
(`00`/`07`/`10`), and the website updated to "macOS 14 Sonoma or later".
Verified empirically before changing: the **app target** compiles at 14.0
with zero errors/warnings — every API in use (incl. `@Observable`,
`MenuBarExtra .window`, the AppKit table) exists on Sonoma. macOS 13 is not
feasible without a rewrite: `@Observable`/Observation requires macOS 14 and
the whole state layer is built on it. Gains the Sonoma-holdout user base
plus 2018–2019 MacBook Air hardware that macOS 15 dropped.
- **Test target needed 3 small fixes:** `AVAudioFile.close()` is 15-only —
  replaced with a `do`-scope so deinit flushes the header (FlacStreaming,
  DecodeContinuity); `MPMediaItemArtwork`'s Sendable conformance is gated
  to 15 → `@preconcurrency import MediaPlayer` (NowPlayingCenterTests);
  the 14.0 SDK surface marks `AVAudioConverter`'s input block `@Sendable` →
  `nonisolated(unsafe)` on a test-local flag (block runs synchronously).
  Full suite green at 14.0; SwiftLint clean.
- **Sonoma runtime verification: consciously skipped** (2026-07-18). Dev
  machine runs macOS 15; a VM/dual-boot pass was judged not worth the
  hassle. Support for 14 is compile-verified only — accepted risk that
  SwiftUI behavior may differ subtly (menu-bar panel, split view). If a
  Sonoma user reports breakage, that's the first place to look; revisit
  with a VM then.
- Future 15-only APIs now need `#available(macOS 15, *)` guards (same
  pattern already planned for Tahoe APIs).

## Post-v1 roadmap from ecosystem gap analysis (2026-07-18)
Surveyed ~35 Subsonic/OpenSubsonic clients (Feishin, Supersonic, Symfonium,
play:Sub, Amperfy, EKO, NaviBeat, …) and mapped Sonicwave against them.
Already ahead of the field: `savePlayQueue` cross-device sync (almost
unclaimed ecosystem-wide), hardware rate matching, streaming gapless.
Added M9–M11 to `10-roadmap.md`: M9 ratings (`setRating`) + synced lyrics
(`getLyricsBySongId`) + sleep timer (all S) · M10 discovery —
`getArtistInfo2` bios, instant mix (`getSimilarSongs2`), album shuffle,
internet radio gated behind an ICY-stream spike (M) · M11 audiophile batch —
optional EQ, signal-path integrity indicator, hog mode, playbackReport (L).
Crossfade explicitly deferred (single-node gapless scheduling has no overlap
path). Offline caching flagged as the first `00` non-goal to revisit
post-MAS. Docs only — no code changes.

## v0.4.0 released (2026-07-17)
Build 7, notarized/stapled/Gatekeeper-accepted, hand-written notes. Ships
the FLAC streaming fix (headline), transcode fallback, album filters,
Shuffle Library, disc headers, artwork throttling. Website changelog
updated; release-triggered Pages deploy stamps 0.4.0.

## FLAC streaming was broken — parser corruption from in-callback buffers (2026-07-16)
Found while live-verifying the issue batch below: playing any FLAC album
decoded ~0.5s per track, then raced through the queue to the end. Weeks of
MP3-only listening had masked it — **FLAC never worked** via the
progressive pipeline.
- **Symptom:** `AudioFileStreamParseBytes` returns `'wht?'`
  (kAudioFileStreamError_UnsupportedFileType) mid-stream after ~6 FLAC
  frames; no `failureMessage` (format WAS discovered), so each track ends
  after ~24K frames → instant gapless boundary → next track → race.
- **Diagnosis:** dumped the real stream via a throwaway in-target test
  (server bytes = pristine FLAC), then bisected standalone: identical bytes
  parse cleanly with no-op callbacks; constructing **AVAudioCompressedBuffer
  inside the AudioFileStream packets callback corrupts the FLAC parser**
  (AVAudioConverter creation in the property callback is innocent; MP3
  tolerates all of it, which is why this never surfaced).
- **Fix:** the packets callback now only copies raw bytes + packet
  descriptions (`PendingPackets`); buffer construction and conversion run
  after ParseBytes returns (`drainPendingPackets` from `parse()`/`finish()`).
  Verified: the dumped 25MB track decodes 10.6M/10.6M frames, and The
  Blueprint (13 FLACs) plays normally in the app. Hermetic regression test
  (`FlacStreamingTests`) synthesizes a FLAC via AVAudioFile and streams it
  in 4KB chunks — reproduces the corruption on the old code.
- Red herrings worth remembering: server-side player transcoding (wasn't),
  ATS hints (wasn't), Retry-After chunk sizes (wasn't). The winning move
  was dumping real bytes and bisecting the callback work standalone.

## Issue batch: #4 #7 #8 #9 #10 (2026-07-15/16)
- **#7 Shuffle All** (`64c9727`): Controls → Shuffle Library + Songs header
  button; fresh 500-song `getRandomSongs` batch.
- **#4 artwork throttling** (`d72fb54`): `AsyncLimiter` (FIFO semaphore
  actor) caps fetches at 6; 429s get one retry after Retry-After (2s
  default, 30s clamp); disk hits bypass.
- **#10 transcode retry** (`29dafc6`): undecodable current track retries
  once as forced mp3 (suffix "mp3" too — the stream is mp3 whatever the
  file was); followers inherit the timeline's forceTranscode so a fully
  unsupported album doesn't race; recovery/seek preserve gain + transcode.
- **#9 album filters** (`6ccc37f`): genre/decade via byGenre/byYear list
  types; sort disabled while filtered; playlists CRUD split to
  LibraryModel+Playlists for the type-length lint.
- **#8 disc headers** (`cdfac38`): TrackTableRow maps unselectable sticky
  group rows over the AppKit table; all external contracts stay in
  track-index space; headers only in disc order; subtitles from discTitles.
- Live-verified: filters (Rap → 1 album, sort disabled), Shuffle Library
  (cross-library mix), single-disc album renders headerless with correct
  play-index mapping. Multi-disc live check pending a multi-disc album in
  the library (row math unit-tested). Suite: 89 → **102 tests**.
- Verification gotcha: computer-driven UI clicks/screenshots cost 5-18s
  each — position math must use timestamps, and a stale app instance from
  a previous day can shadow the fresh build (`ps` first, then `open`).

## v0.3.0 released (2026-07-15)
Build 6, notarized/stapled/Gatekeeper-accepted, zip on the GitHub Release
with hand-written notes. Ships the issue burn-down below (queue
persistence, ReplayGain, formPost playlists, local plain-HTTP). Website
changelog updated; the release-triggered Pages deploy stamps 0.3.0.

## Issue burn-down: #1 #2 #5 #6 (2026-07-15)
First four tracker issues closed (from the competitive research round):
- **#2 — plain-HTTP home servers** (`88eaff3`): partial `Info.plist`
  (repo root; inside `Sonicwave/` the synced group copies it as a bundle
  resource → warning) merged into the generated one with
  `NSAllowsLocalNetworking`. Non-local `http://` stays ATS-blocked but now
  maps to an actionable message (`SubsonicError.transport(from:)`).
- **#1 — large playlist mutations** (`d1f85cc`): `usesFormPost`-flagged
  endpoints go as form-encoded POST when the server advertises `formPost`
  (capability via resurrected `getOpenSubsonicExtensions`, cached per base
  URL). `+` escaped in bodies — form decoding reads it as a space.
- **#5 — play-queue persistence** (`671e565`): `savePlayQueue`/
  `getPlayQueue`; saves forced on pause/track change, 30s-throttled on
  position ticks, final best-effort on quit; restores paused via
  `PlayerModel.restoreQueue` (never clobbers an active queue; resume
  position consumed by the next stopped→play).
- **#6 — ReplayGain** (`232ea3c`): gain baked into span buffers via
  `vDSP_vsmul` (one shared gapless node → node volume can't do per-track);
  peak-clamped dB→linear math on `ReplayGainMode` (unit-tested); Settings →
  Playback picker; seek preserves the span's gain. Gotcha: `Song` has
  explicit `CodingKeys` — new decoded fields must be added there or they
  silently decode as nil.
- Suite: 67 → **89 tests**.
- **Live-verified vs Navidrome 0.63.2** (same day): queue restore across
  quit/relaunch is exact — track, paused position (1:02, then 3:01) and Up
  Next order all reappear, no auto-play; resume plays on from the restored
  position at 1× (timestamp-correlated — beware: computer-driven UI clicks/
  screenshots cost 5–18s each, which first masqueraded as a "+12s position
  jump"). savePlayQueue→getPlayQueue round-trips through the formPost path
  (Navidrome advertises it). Settings picker persists across relaunches.
  A `replaygain <gain> for <songId>` info log (nl.huell.sonicwave/playback)
  makes gain application observable; the library's files carry no RG tags,
  so non-unity gain (and audibility) still needs a tagged album — the
  unity no-op path ran clean. NB: zsh shadows `/usr/bin/log` with a
  builtin — use the full path.

## v0.2.0 released; repo public, website live (2026-07-15)
- **Released v0.2.0 (build 5)** via `scripts/publish.sh` — notarized,
  Gatekeeper-accepted ("Notarized Developer ID"), tagged, zip attached to
  the GitHub Release with generated notes. First release carrying the
  post-M7 feature batch (Home, scrobbling, AirPlay Tier 1, demo onboarding,
  scan, Quick Look art, decode-failure alerts, resizable panel).
- **Repository made public** (2026-07-15) after a full git-history audit:
  no credentials/hosts ever committed (live tests are env-var-gated); the
  Apple Team ID and author email are the only identifying values and are
  public by design. Claude-design share links stripped from `09`.
- **Landing page** (`site/`, dark hi-fi look, animated LCD hero) deployed to
  GitHub Pages: <https://thijsw.github.io/sonicwave/>. `pages.yml` deploys
  on `site/` pushes **and on every published release**, stamping the latest
  release tag into the page's `app-version` spans — the download front door
  stays current with zero manual steps.
- Gotcha found on the first release-triggered deploy: the `github-pages`
  environment only allowed `main`, and release events run on the **tag
  ref** — the run failed in 3s with no job logs. Fixed permanently with a
  `v*` **tag** deployment-branch policy on the environment; rerun deployed
  and the live page shows 0.2.0.
- Docs synced with the shipped app (scrobbling no longer a non-goal — the
  server relays; CI marked done; AirPlay/Quick Look/scan coverage added)
  and a root `CLAUDE.md` added as the session entry point.

## Polish batch: scan, Quick Look art, show-album (2026-07-08)
Player quality-of-life features, all live-verified:
- **Server library scan**: `startScan` endpoint; Settings → Connection
  "Scan Library" (shows "Scanning — N items" feedback) + File → Update
  Server Library. Verified against Navidrome.
- **Seek precision log-verified sample-exact** while validating seek entry
  points (temporary tick logging: position ran 30.0 → 31.4 dead-on after a
  seek to 0:30). An apparent "+10s offset" during UI testing turned out to
  be measurement latency, not a bug. (A "Go to Time…" prompt was built on
  this and removed the same day as not useful enough.)
- **Quick Look artwork**: clicking the panel's hero art opens the
  full-resolution cover (`ArtworkCache.originalImageFileURL` stages a
  properly-named file, extension sniffed from magic bytes so QL renders it).
- **Show Album in Library**: the panel's album line is clickable, plus
  Controls → Show Album in Library (⇧⌘L). Resolves `albumId` via
  `getAlbum`. Learned: SwiftUI `.contextMenu` on toolbar items never fires —
  NSToolbar intercepts right-clicks for its own customize menu — so the LCD
  hosts no context menu.
- RootView's Controls-menu handlers live in a `CurrentTrackCommands`
  modifier (inlining them broke the type-checker's time budget).
- Known cosmetic nit: the fixed-height Settings window scrolls its
  Connection form now that the scan section is added.

## Home shelves, scrobbling, demo server (2026-07-08)
- **Home** sidebar section (`HomeView`): a distinct landing page —
  time-of-day greeting, "Jump Back In" hero card (blurred-artwork backdrop,
  inline Play verified to win over the card's open-album tap), then
  varied-size shelves (Keep Listening / Recently Added at 150pt / Most
  Played / Random with re-roll) from `getAlbumList2` types. Shared
  `Shelf`/`AlbumShelf` gained title, tile-size and header-accessory
  parameters. Verified live against Navidrome (first flat four-shelf cut
  was rejected as indistinct and redesigned).
- **Scrobbling** (`PlayerModel+Scrobbling`, injected closure → `scrobble`):
  "now playing" at track start, submission at half-track-or-4-minutes
  (≥ 30s tracks). Settings → Playback toggle, default on. **Verified
  end-to-end**: played a 2Pac track past its midpoint → after relaunch the
  album led the server-fed Recently Played shelf (it was absent before —
  plays predating this feature were never counted).
- **Demo server**: Settings → Connection shows a one-click "Use Demo
  Server" (public Navidrome demo, `demo`/`demo`) — only while no server is
  configured, so it can't clobber a real setup. Doubles as the App Review
  reviewer path (`07` checklist item closed). Demo server reachability
  probe-verified; the button reuses the tested saveAndConnect path.

## CI, decode-failure UX, panel resize (2026-07-08)
- **CI test job** (`.github/workflows/tests.yml`): build + full unit suite on
  every push/PR, macOS 15 runner, newest installed Xcode selected at run
  time, `CODE_SIGNING_ALLOWED=NO` (LiveDecodeTests self-skip without env).
  Closes the last self-serve M8 item.
- **AAC/ALAC-in-MP4 graceful error**: `ProgressiveAudioSource` now refuses
  cookie-dependent containers at format discovery (`AVAudioConverter` has no
  magic-cookie API — decoding emitted loud static) and reports a
  `failureMessage`; a stream ending with no decodable format gets a generic
  one. `PlaybackService` stops the transfer and emits `.failed`. Found along
  the way: `PlayerModel.lastError` was **write-only** — playback failures
  were never shown. RootView now presents a "Can't Play Track" alert with
  the actionable message (enable server transcoding). Unit-tested against a
  real AVAudioFile-encoded `.m4a` (`aacInMP4SurfacesGracefulError`).
- **Now Playing panel resize**: grab strip on the panel's leading edge
  (`PanelResizeHandle`), 300–480pt clamp, persisted
  (`nowPlayingPanelWidth`). Lives inside the detail column so it cannot
  re-trigger the split-view/toolbar instability the panel design avoids;
  open/close animation is keyed on visibility only, so dragging is live.

## AirPlay Tier 1 (2026-07-08)
Status: **code complete, build/lint clean, UI verified; live end-to-end
deferred** (needs a real AirPlay 2 receiver — none available at the time).
- Scope (Tier 1): treat AirPlay endpoints as regular Core Audio output
  devices — no private sender API, no in-app discovery. `AudioDevice` gained
  `isAirPlay` (via `kAudioDevicePropertyTransportType ==
  kAudioDeviceTransportTypeAirPlay`); the Settings picker groups AirPlay
  routes after regular devices with an `airplay.audio` label;
  `matchDeviceRateIfEnabled` skips AirPlay transports (fixed network clock —
  nominal-rate pokes are useless-to-glitchy; macOS resamples instead).
- **Empirical constraint (probed, not assumed):** an AirPlay receiver only
  exists as a Core Audio device *while the system is connected to it* —
  Control Center owns discovery/connection. A shairport-sync fake receiver
  ("Sonicwave Test Speaker") advertised fine on Bonjour (`_raop._tcp`) but
  never appeared in the device list, and *also never appeared in Control
  Center*: the Homebrew build is **AirPlay 1 only**, and macOS's system
  output list shows **AirPlay 2 receivers only** (AirPlay 1 shows in
  Music.app's private picker alone). An AirPlay 2 shairport-sync needs a
  from-source build + root nqptp daemon — not attempted.
- Verified so far: build + SwiftLint clean; Settings → Playback picker
  correct pre-connection (regular devices, remembered-disconnected entry, no
  phantom AirPlay section).
- **⏳ Pending live test** (any AirPlay 2 receiver, e.g. another Mac with
  AirPlay Receiver enabled, HomePod, Apple TV): connect via Control Center →
  device appears with AirPlay transport → shows under the picker's AirPlay
  group → pin in-app → audio arrives → log shows no rate-match attempt.

## Toolbar/panel stability fixes (2026-07-08)
Status: **done & frame-verified** (screen recordings analyzed per frame;
note: computer-use synthetic input does NOT deliver while `screencapture -V`
records — drive the app via `osascript` keystrokes when filming).
- **Sidebar shove on panel toggle (the real one):** presenting the Now
  Playing panel via `.inspector` inserts its column into the window's split
  view at full width *before* the detail column yields space — the whole
  content pane slides left, pushing the sidebar off the window edge and
  snapping it back (~9 frames at 60 fps, caught on camera). Fixed by hosting
  the panel as a width-animated trailing pane **inside the detail column,
  below the toolbar** (`HStack` + `.transition(.move(edge: .trailing))`);
  the outer split view never re-lays-out and the toolbar never needs to
  reflow (NSToolbar item re-layout snaps, never animates — every attempt at
  a header that tracks the panel, animated padding / merged full-width item
  / split-view holding priorities, either snapped or landed in the overflow
  menu). Motion-analysis verified: the pane slides over ~10 frames; the
  sidebar and the toolbar strip show **zero** moved frames across both
  toggle directions. Trade-offs: no inspector drag-to-resize (fixed 344pt),
  and the hero artwork tops out at the toolbar's bottom edge rather than
  the window top.
- Along the way: panel toggles (LCD, toolbar button, ⌘U, dismiss binding)
  wrapped in `withAnimation`; `columnVisibility` pinned to `.constant(.all)`
  (the sidebar is permanently visible by design); the toolbar volume slider
  is hosted in an `NSHostingView` that refuses `mouseDownCanMoveWindow` —
  dragging it no longer moves the window (custom SwiftUI drag gestures don't
  opt out of toolbar window-dragging the way native controls do).

## M8 — release signing pipeline (2026-07-07)
Status: **Developer ID pipeline working end-to-end; MAS path configured and
blocked on portal artifacts.**
- Release build settings: Manual signing, **Developer ID Application (Huell
  B.V., 4HNWJ993V9)**, **Hardened Runtime ON** (was `Automatic` with no team).
  Debug unchanged (Developer ID, hardened runtime off — Keychain DR
  stability).
- `scripts/release.sh [developer-id|app-store]`:
  archive → export (`scripts/ExportOptions-*.plist`) → `codesign
  --verify --strict` + authority/`runtime`-flag assertion → notarize + staple
  + `spctl` assess (auto-skipped with instructions until a `sonicwave`
  notarytool keychain profile is stored) → versioned zip. `build/` is
  git-ignored.
- **Verified:** pipeline run produced `build/Sonicwave-0.1.0.zip`; signature
  valid (`Authority=Developer ID Application: Huell B.V.`,
  `flags=0x10000(runtime)`); entitlements on the artifact are exactly
  app-sandbox + network.client; `spctl` reports "Unnotarized Developer ID"
  (expected pre-notarization); the exported app **runs, connects via
  Keychain creds, and plays audio** under the hardened runtime — no runtime
  exceptions needed.
- ✅ **Notarization round-trip verified (2026-07-07):** with the `sonicwave`
  keychain profile stored, the pipeline notarized (status **Accepted**),
  stapled, and passed Gatekeeper (`accepted, source=Notarized Developer ID`).
  `build/Sonicwave-0.1.0.zip` is a fully distributable direct-download build.
- Remaining for M8: Apple Distribution + Mac Installer certs and an ASC app
  record for the MAS build, final app icon, App Privacy details, reviewer
  notes/demo server, CI test job.

## M7 close-out — accessibility + scroll restoration (2026-07-07)
Status: **M7 complete** (Tahoe/Liquid Glass verification pending a macOS 26
machine). The `08-testing.md` manual checklist is annotated with per-item
status.
- **`SlimSlider` accessibility**: the custom gesture-driven slider now
  exposes a spoken value (percent for volume; "elapsed of total" for the
  panel/menu-bar scrubbers via `accessibilityValueText`) and
  increment/decrement adjustable actions — which also make it operable via
  Full Keyboard Access and VoiceOver (VO-↑/↓). Verified by walking the AX
  tree: `label=Volume valueDesc=100 percent actions=[AXIncrement,
  AXDecrement]`.
- **Track-table favorite buttons** expose state-aware labels ("Add to /
  Remove from Favorites") + `AXPress` — all rows verified via the AX API.
- **Scroll-position restoration** (`trackScroll.<key>`): the stable library
  views (Songs/Favorites/browser) persist their scroll offset (debounced
  saves via a selector-based clip-view observer; saving starts only after
  the one-shot restore so churn can't clobber the stored value; restore is
  clamped to loaded content). Content-specific views (album detail, search)
  and playlists deliberately don't persist scroll. Live-verified: offset 932
  survived a relaunch (a +5-tick scroll then saved 1052).
- **Light mode verified** without touching system settings (per-app
  `NSRequiresAquaSystemAppearance` override, removed afterwards): clean
  light rendering, readable text, correct accent. No hardcoded colors exist
  in the codebase.
- `MusicTrackTable` was reorganized to keep lint clean: view lifecycle in a
  same-file extension, sort+scroll persistence in
  `TrackTablePersistence.swift`.
- Remaining strictly-by-hand items: a full VoiceOver listening pass,
  increased-contrast / reduce-transparency spot checks, AirPods route
  change (same recovery path as the verified USB-DAC vanish), and the
  macOS 26 Liquid Glass look.

## Memory-leak audit (2026-07-07)
Status: **app code verified leak-free** (static review + `leaks` runs against
the live app under load).
- **Static review:** all long-lived closures use `[weak self]`
  (NowPlayingCenter remote commands, engine callbacks, event loops);
  `DataStreamLoader` invalidates its URLSession (which retains its delegate)
  on both completion and stream termination; `AudioDeviceListObserver`
  removes its Core Audio listener in `deinit`; `NSMenuItem.target` is weak so
  `ClosureMenuItem`'s self-target doesn't cycle; the one `takeRetainedValue`
  balances Core Audio's +1; artwork `NSCache` is count-bounded (400) with
  self-removing in-flight tasks.
- **Runtime (leaks tool):** after 12 track skips (full decode pipeline
  teardown/rebuild each), seeks, panel toggles, view switching, and repeated
  context menus: **zero leaks attributable to Sonicwave code**. Footprint is
  stable and *declines* during playback (47 MB idle → ~118 MB peak → 83 MB
  while still playing) — the bounded read-ahead behaves as designed.
- **Known framework-internal leak (accepted):** AudioToolbox's
  `ListenerMap::InsertEvent` leaks ~50–100-byte AU parameter-listener
  bindings each time the player node is (re)connected to the mixer — first
  play, rate-change hard starts (rate matching), route recoveries. ~1.2 KB
  per reconnect, all inside `AVAudioEngine`/`AudioToolboxCore` via the
  documented `engine.connect` API; not fixable app-side (we already reconnect
  only when the timeline rate actually changes). Heisenbug note: full
  `MallocStackLogging=1` masks it; reproduce with `=lite` or none.

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
- ✅ `xcodebuild test` — full suite green (**TEST SUCCEEDED**, 67 tests,
  0 failures), and CI repeats the run on every push
  (`.github/workflows/tests.yml`).

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
