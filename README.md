<div align="center">

# Sonicwave

**A native macOS music player for your own OpenSubsonic server.**

The interaction design iTunes got right — a dense sortable track list, a
column browser, Up Next, fast search — rebuilt as a modern, restrained
SwiftUI app that feels like it shipped with macOS. Streaming-only,
audiophile-grade playback, no Electron in sight.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![Frameworks](https://img.shields.io/badge/dependencies-Apple%20frameworks%20only-green)
![Server](https://img.shields.io/badge/server-OpenSubsonic%20%2F%20Navidrome-8A2BE2)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

</div>

---

Sonicwave connects to a self-hosted [OpenSubsonic](https://opensubsonic.netlify.app/)
library ([Navidrome](https://www.navidrome.org/) is the reference server) and
streams it through a hand-built `AVAudioEngine` pipeline. It's for people who
run their own music server and want a real Mac app — keyboard-friendly,
low-footprint, HIG-faithful — instead of a browser tab.

## Highlights

### 🎧 Playback that takes audio seriously
- **True gapless playback.** Every track decodes into one continuous timeline
  on a single player node — album transitions are seamless by construction,
  not by crossfade. Verified by ear on the Abbey Road medley.
- **Hardware sample-rate matching** (Audirvana/Roon-style, on by default):
  the output device's clock is switched to each track's native rate, so
  nothing is resampled between the file and your DAC.
- **Progressive streaming decode.** Audio File Stream Services +
  `AVAudioConverter` turn the HTTP stream into PCM as bytes arrive — playback
  starts fast, and read-ahead is throttled to ~15 s so memory stays flat
  (MP3, FLAC, AAC/ADTS, WAV, AIFF, …).
- **Robust output routing.** Pick any output device; mid-track switches,
  a vanished USB DAC, or a replug all recover automatically at the playhead.
  Sonicwave never touches your system-default device.
- **Sample-precise seeking**, server-side transcoding (format + max bitrate)
  if you want it, and idle-sleep/App Nap prevention while playing.

### 📚 A library you can actually drive
- **Dense, sortable track table** (real AppKit under the hood): edge-to-edge
  stripes, double-click or ⏎ to play, ⌥-double-click to queue next,
  multi-select, drag to playlists, click-to-sort headers.
- **Column browser** — filter Genre → Artist → Album, just like the classic
  iTunes pattern (⌥⌘B).
- **Quality badges** per track ("FLAC", "320 kbps"); sorting ranks lossless
  above any lossy bitrate.
- **Global search** with instant artist/album shelves and song results (⌘F).
- **Server playlists, fully round-trip:** create, rename, delete, reorder
  (Move to Top/Up/Down/Bottom), add/remove — all persisted to the server.
- **Favorites everywhere:** a ★ column with optimistic toggling, album-level
  stars, a Favorites section.

### 🖥 A proper Mac citizen
- **Now Playing toolbar** with an iTunes-style "LCD": artwork, track info,
  elapsed/total, and a hairline progress bar; click it to open the
  **Now Playing panel** (hero artwork, scrubber, transport, reorderable
  Up Next queue).
- **Menu-bar player** (`MenuBarExtra`): full transport and scrubbing from the
  menu bar, even with the main window closed.
- **System integration done right:** Control Center / Now Playing widget,
  media keys (F7/F8/F9), `MPRemoteCommandCenter` scrubbing, live artwork.
- **Native everything:** Light/Dark, keyboard shortcuts for transport and
  views, state restoration, App Sandbox with a single entitlement
  (outgoing network), credentials in the Keychain.

## Requirements

- **macOS 15 Sequoia** or later
- An **OpenSubsonic-compatible server** (Navidrome, Gonic, LMS, Astiga, …)
  reachable over HTTP(S)
- Xcode 26 / Swift 6.2 to build from source

## Download

Grab `Sonicwave-x.y.z.zip` from the
[latest release](https://github.com/thijsw/sonicwave/releases/latest), unzip,
and drop `Sonicwave.app` into `/Applications`. Builds are Developer
ID-signed, hardened-runtime, and **notarized by Apple** — they launch
without Gatekeeper warnings.

## Building

```sh
git clone https://github.com/thijsw/sonicwave.git
cd sonicwave
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' build
```

Or open `Sonicwave.xcodeproj` in Xcode and hit Run.

**First launch:** open **Settings → Connection** (⌘,), enter your server
address, username, and password (or an OpenSubsonic API key), and hit
**Test Connection** → **Save & Connect**. Sonicwave normalizes pasted browser
URLs (it strips Navidrome's `/app` suffix for you), and your credentials go
straight to the Keychain — the classic token+salt scheme means your password
never travels in a URL.

## Under the hood

Swift 6 strict concurrency, Observation, and **zero third-party
dependencies** — every capability maps to a first-party framework:

| Layer | What it is |
| --- | --- |
| UI | SwiftUI (`NavigationSplitView`, `MenuBarExtra`, inspector panel) with a thin AppKit `NSTableView` core for the track list |
| State | `@Observable` models on the main actor; one `PlayerModel` is the single source of truth for everything "now playing" |
| Playback | `PlaybackService` actor owning `AVAudioEngine`; progressive decode via AudioFileStream + `AVAudioConverter`; Core Audio device control |
| Networking | `SubsonicClient` actor over `URLSession` with typed throws (`SubsonicError`) |
| Caching | Two-tier (memory + disk) artwork cache, scoped per server; library metadata stays in-memory — the app is streaming-first by design |

The `docs/` directory holds the full design docs — architecture, the playback
engine deep-dive (including the gapless and crackle-forensics war stories),
API layer, UI/UX rationale, and the build log (`docs/PROGRESS.md`). The unit
suite (Swift Testing, 66 tests) runs hermetically; an opt-in live suite
exercises a real server when `SONICWAVE_HOST/USER/PASS` are set.

```sh
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' test
```

## Status

Sonicwave is feature-complete for v1 and in the final polish phase
(accessibility sweep, deeper state restoration) ahead of Mac App Store
distribution. See [`docs/10-roadmap.md`](docs/10-roadmap.md) for milestone
status and [`docs/PROGRESS.md`](docs/PROGRESS.md) for the detailed build log.

**Deliberately out of scope for v1:** offline downloads, scrobbling, smart
playlists, multi-server profiles, tag editing.

## License

[MIT](LICENSE)

---

<div align="center">
<sub>Built for people who miss iTunes 12.6 — the patterns, not the chrome.</sub>
</div>
