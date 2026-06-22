# 01 — App Architecture

## Goals

- One unambiguous source of truth for playback state, observed by every view,
  the `MenuBarExtra` panel, and the system Now Playing center.
- A service layer that keeps `AVAudioEngine` and `URLSession` out of views, so
  queue/gapless logic is testable and the audio backend is swappable.
- Swift 6 strict concurrency by construction: `@MainActor` UI/state,
  `actor`-isolated services, `Sendable` value-type models.
- Small memory footprint: lazy data, streamed audio, aggressively released
  buffers and artwork.

## Layered design

```
┌─────────────────────────────────────────────────────────────┐
│  UI  (SwiftUI views, @MainActor)                             │
│  ContentView · Sidebar · TrackTable · ColumnBrowser ·        │
│  NowPlayingHeader · UpNextView · MenuBarExtra panel ·        │
│  SettingsView · SearchView                                    │
└───────────────▲─────────────────────────────────────────────┘
                │ observes (@Observable)
┌───────────────┴─────────────────────────────────────────────┐
│  App State / ViewModels  (@MainActor, @Observable)           │
│  AppModel · PlayerModel · LibraryModel · PlaylistsModel ·    │
│  SearchModel · ConnectionModel                               │
└───────────────▲─────────────────────────────────────────────┘
                │ async calls
┌───────────────┴─────────────────────────────────────────────┐
│  Services  (actors / isolated)                               │
│  SubsonicClient (actor) · PlaybackService (actor) ·          │
│  LibraryStore (SwiftData) · ArtworkCache · AuthStore         │
│  (Keychain) · NowPlayingCenter · OutputDeviceService         │
└───────────────▲─────────────────────────────────────────────┘
                │
┌───────────────┴─────────────────────────────────────────────┐
│  System / IO                                                 │
│  URLSession · AVAudioEngine · MediaPlayer · Keychain ·       │
│  Core Audio · SwiftData store                                │
└─────────────────────────────────────────────────────────────┘
```

**Rule:** views never import `AVFoundation`/`MediaPlayer`/`URLSession`; they
talk to models, and models talk to services.

## Central state: `PlayerModel` ✅

A single `@MainActor @Observable final class PlayerModel` is the source of
truth for everything "now playing":

- `currentTrack: Song?`, `queue: [Song]` (Up Next), `history: [Song]`
- `playbackState: PlaybackState` (`.stopped`, `.buffering`, `.playing`,
  `.paused`)
- `position: TimeInterval`, `duration: TimeInterval` (position throttled — see
  `03`)
- `repeatMode`, `shuffle`, `volume`, `outputDeviceID`

Why central: the `MenuBarExtra` panel, the main window's header, multiple
library windows, the `MPNowPlayingInfoCenter`, and `MPRemoteCommandCenter`
handlers must all reflect and mutate the same state without drift. `PlayerModel`
forwards intent (`play(_:)`, `pause()`, `next()`, `seek(to:)`) to
`PlaybackService` and mirrors the resulting state back for observation.

The model is the *only* thing that writes to `NowPlayingCenter`, so system
metadata can never disagree with the UI.

## Service responsibilities

- **`SubsonicClient` (actor)** — all OpenSubsonic HTTP. Builds authed
  requests, decodes `Codable` models, maps errors. See `02`.
- **`PlaybackService` (actor)** — owns `AVAudioEngine`, the two player nodes,
  the streaming decode pipeline, gapless scheduling, and a position publisher.
  Exposes async intent methods and an `AsyncStream`/callback of state +
  position back to `PlayerModel`. See `03`.
- **`LibraryStore`** — SwiftData-backed metadata cache (albums/artists/songs/
  genres/playlists/starred) with pagination. See `05`.
- **`ArtworkCache`** — fetch-once, resized, memory-bounded image cache. See
  `05`.
- **`AuthStore`** — Keychain read/write of server URL, username, password (for
  token+salt) or API key. See `02`/`07`.
- **`NowPlayingCenter`** — wraps `MPNowPlayingInfoCenter` /
  `MPRemoteCommandCenter`. See `06`.
- **`OutputDeviceService`** — enumerate Core Audio output devices, observe
  route changes, set engine output. See `03`.

## Concurrency model (Swift 6 strict) ✅

- UI + all `@Observable` models: `@MainActor`.
- Networking, decode, file/audio I/O: off the main actor in `actor`s or
  detached tasks. Decoding audio and reading streams must never block the UI.
- Data crossing isolation boundaries is `Sendable` value types (`struct`/
  `enum`); models map service DTOs to UI-facing value types.
- Migration approach: start the app target in Swift 6 language mode from M0
  (greenfield, so no incremental migration burden). Keep service boundaries
  narrow and `Sendable`-clean.

## State management: Observation ✅

Use the Observation framework (`@Observable`) rather than
`ObservableObject`/`@Published`. Inject models via the SwiftUI environment
(`.environment(playerModel)`) so the main window, additional windows, and the
`MenuBarExtra` scene share instances. App-level wiring lives in the `App`
struct's `body` (`WindowGroup`, `Settings`, `MenuBarExtra` scenes).

## Error handling & state modeling

- `enum`s with associated values for finite state (`PlaybackState`,
  `ConnectionState`, `LoadState<T>` = `.idle/.loading/.loaded(T)/.failed(Error)`).
- Typed throwing (`throws(SubsonicError)`) at the client boundary; surface
  user-facing errors via a lightweight alert/toast model.
- Optionals over sentinels; avoid force-unwraps outside genuinely guaranteed
  cases.

## Module / target structure (described, not scaffolded)

Single app target for v1 plus a unit-test target. Folder groups inside the app
target:

```
Sonicwave/
  App/            App entry, scenes, commands (menu bar), environment wiring
  Models/         PlayerModel, LibraryModel, … (@Observable) + value types
  Services/       SubsonicClient, PlaybackService, LibraryStore, ArtworkCache,
                  AuthStore, NowPlayingCenter, OutputDeviceService
  Networking/     Request builder, endpoint enum, DTOs, error mapping
  Playback/       Engine graph, streaming source, gapless scheduler
  Persistence/    SwiftData models + schema
  UI/
    Sidebar/  Library/  Playlists/  NowPlaying/  Search/  Settings/  MenuBar/
  Resources/      Assets, Info.plist, entitlements
SonicwaveTests/   Swift Testing units (+ fixtures)
SonicwaveUITests/ XCUITest target
```

Keep the audio/Core Audio bridging thin and contained (most is pure Swift; only
device enumeration touches Core Audio C APIs).

## Dependency policy ✅

First-party Apple frameworks only. Everything in the prompt maps to system
frameworks (SwiftUI, AVFAudio/AVFoundation, MediaPlayer, Security/Keychain,
URLSession, SwiftData, CryptoKit/`Insecure.MD5` for the auth token). Reach for
an SPM package only if a permissive-licensed library is the sole alternative to
reinventing the wheel; record any such decision here with its license.
