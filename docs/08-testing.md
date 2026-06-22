# 08 — Testing Strategy

Use **Swift Testing** (`@Test`, `#expect`/`#require`) for unit and logic tests;
**XCTest/XCUITest** for UI automation (the supported path for UI tests). Design
for testability via protocols so services can be mocked without a live server or
audio hardware.

## What to unit-test (Swift Testing)

### Networking / API (`02`)
- **Request building:** correct `/rest/<method>` path, common params
  (`v/c/f=json`), and per-endpoint params; URL encoding of queries.
- **Auth:** token+salt — `t == md5(password + salt)` for known vectors; salt is
  random per request; API-key path emits the right params; password never
  appears in the URL.
- **Response decoding:** decode `Codable` models from **recorded JSON
  fixtures** (Navidrome responses for `getAlbumList2`, `getArtist`, `getAlbum`,
  `getPlaylists`, `search3`, `getStarred2`, `getOpenSubsonicExtensions`,
  error envelopes). Cover the single-vs-array and string-number quirks.
- **Error mapping:** Subsonic error codes (40/41/50/70/…) map to the right
  `SubsonicError` cases.
- **Pagination:** offset bookkeeping and exhaustion detection.
- **Transcoding params:** original vs transcode produce the expected `stream`
  URL (`format`/`maxBitRate` present/absent).

### Playback logic (`03`)
- **Queue/Up Next:** play-from-index, next/previous, reorder, remove,
  repeat/shuffle behavior — tested against a **mocked engine** (a fake
  conforming to the playback/stream-source protocols), no real audio.
- **Gapless scheduling decisions:** N+1 priming triggers at the right point;
  node role swap; teardown/release ordering (assert via the mock's recorded
  calls).
- **Position throttling:** updates emitted at the configured rate, derived from
  sample time (inject a clock).
- **Seek:** maps to source seek + position/Now Playing update.

### State & integration seams
- **`PlayerModel`** transitions (`PlaybackState` enum) on intent.
- **`NowPlayingCenter`** (`06`): given a `PlayerModel` change, the right
  `nowPlayingInfo` keys/playbackState are produced (test the mapping function,
  not the live `MPNowPlayingInfoCenter`).
- **Artwork cache** (`05`): key-by-id+size, eviction, no full-res reuse for
  thumbnails.

## Mocking approach ✅

- Protocols at every service boundary: `SubsonicAPI`, `AudioStreamSource`,
  `PlaybackEngine`, `ArtworkProviding`, `CredentialStore`.
- A `MockSubsonicAPI` returns fixture-backed responses + injectable errors.
- A `MockPlaybackEngine` records scheduling/seek/teardown calls for assertions.
- `URLProtocol`-based stub for any test that must exercise the real
  `SubsonicClient` over `URLSession` end-to-end without a server.

## UI tests (XCUITest)

- Smoke flows: configure server (mocked via launch-argument stub), browse a
  library, play a track, scrub, next/previous, create/reorder a playlist,
  search.
- Accessibility: key elements have identifiers/labels; basic VoiceOver-trait
  presence.

## Manual verification checklist (hardware-dependent)

These can't be fully automated — verify by hand each release:
- [ ] Now Playing widget shows correct title/artist/album/artwork + elapsed.
- [ ] Media keys (F7/F8/F9) and Control Center transport control the app.
- [ ] **Gapless**: a known gapless album transitions with no seam/overlap.
- [ ] Output-device switch mid-track recovers cleanly.
- [ ] Headphone unplug / AirPods connect handled (route change).
- [ ] App doesn't sleep/App-Nap mid-track.
- [ ] State restoration: relaunch reopens windows/selection/sort/scroll.
- [ ] Light/Dark, increased contrast, reduce transparency, VoiceOver,
      keyboard-only navigation.
- [ ] Liquid Glass appearance on macOS 26; clean native look on Sequoia.
- [ ] Memory stable over a long listening session (no buffer/artwork leak).

## CI 🔶

- Run unit tests on every change (`xcodebuild test` /
  `swift test` where applicable) on a macOS 15 + Xcode 26 runner.
- Build the signed MAS artifact in a release job (see `07`).
