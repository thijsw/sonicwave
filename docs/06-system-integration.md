# 06 — System Integration

What makes Sonicwave feel native: it appears in Control Center / the Now Playing
widget, responds to the media keys, restores its windows, and behaves like a
proper Mac app. All of this is driven from the single `PlayerModel` (see `01`)
via a `NowPlayingCenter` service so system state can never disagree with the UI.

## Now Playing — `MPNowPlayingInfoCenter` ✅

- Keep `MPNowPlayingInfoCenter.default().nowPlayingInfo` current with:
  - `MPMediaItemPropertyTitle`, `…Artist`, `…AlbumTitle`,
  - `MPMediaItemPropertyPlaybackDuration`,
  - `MPNowPlayingInfoPropertyElapsedPlaybackTime` (updated on the throttled
    cadence from `03`, not every frame),
  - `MPNowPlayingInfoPropertyPlaybackRate` (0 paused / 1 playing),
  - `MPMediaItemPropertyArtwork` — an `MPMediaItemArtwork` whose handler returns
    a resized image from `ArtworkCache` (see `05`).
- Set `MPNowPlayingInfoCenter.default().playbackState` to reflect
  playing/paused/stopped.
- Update on: track change, play/pause, seek, and periodic elapsed-time ticks.

## Remote commands & media keys — `MPRemoteCommandCenter` ✅

- Enable and handle: `playCommand`, `pauseCommand`, `togglePlayPauseCommand`,
  `nextTrackCommand`, `previousTrackCommand`, `changePlaybackPositionCommand`
  (scrub from Control Center), and seek/skip as desired.
- Each handler calls into `PlayerModel` intent and returns the appropriate
  `MPRemoteCommandHandlerStatus`.
- This is the **sanctioned** way to receive the keyboard/Touch Bar media keys
  (F7/F8/F9) — do **not** use low-level event taps. Registering remote commands
  is what lets Sonicwave win the media keys when it's the active audio app.
- Disable commands that don't apply (e.g. no rating) so the system UI hides
  them.

## App Nap & sleep prevention ✅

- During active playback, hold a
  `ProcessInfo.processInfo.beginActivity(options: [.userInitiated,
  .idleSystemSleepDisabled], reason: "Playing audio")` token; release it on
  pause/stop. Prevents throttling and idle-sleep mid-track. (Detailed in `03`;
  owned by `PlaybackService`.)

## Drag-and-drop ✅ / ⏳

- **Internal** (✅): drag track rows to sidebar playlists and into Up Next
  (see `04`).
- **External files onto window/dock** (⏳ for full support): v1 is
  streaming-only/server-backed. Accept the drop and attempt to resolve dropped
  audio to server items (by metadata) for enqueue; otherwise show an
  unsupported affordance. Full local-file playback is a post-v1 item.

## Window model & state restoration ✅

- Adopt SwiftUI scene restoration so windows reopen where the user left them.
- Persist and restore per-window UI state: selected sidebar item, column-browser
  selections, table sort + visible columns, scroll position, Up Next
  visibility. Use `@SceneStorage`/`@AppStorage` for lightweight pieces and the
  store for heavier selections.
- Support full-screen and Stage Manager (mostly free with standard scenes;
  verify layout at small/large sizes).

## File-system access ✅

- v1 needs almost no local file access (streaming). If external-file drag
  import is enabled later, use `NSOpenPanel` and **security-scoped bookmarks**
  for any persistent access rather than hardcoded paths, consistent with the
  sandbox (see `07`).

## Ownership

`NowPlayingCenter` is the only writer to `MPNowPlayingInfoCenter` /
`MPRemoteCommandCenter`; it observes `PlayerModel` and pushes updates, and
routes remote commands back into `PlayerModel`. This keeps a single, testable
seam between app state and the system.
