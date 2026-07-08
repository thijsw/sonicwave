<div align="center">

# Sonicwave

**A native macOS music player for your own OpenSubsonic server.**

The interaction design iTunes got right — a dense sortable track list, a
column browser, Up Next, fast search — rebuilt as a modern, restrained
Mac app. Streaming-only, audiophile-grade playback, no Electron in sight.

![Platform](https://img.shields.io/badge/platform-macOS%2015%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-orange)
![Frameworks](https://img.shields.io/badge/dependencies-Apple%20frameworks%20only-green)
![Server](https://img.shields.io/badge/server-OpenSubsonic%20%2F%20Navidrome-8A2BE2)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

</div>

---

Sonicwave connects to a self-hosted [OpenSubsonic](https://opensubsonic.netlify.app/)
library ([Navidrome](https://www.navidrome.org/) is the reference server).
It's for people who run their own music server and want a real Mac app —
keyboard-friendly, low-footprint, native — instead of a browser tab.

## Download

Grab `Sonicwave-x.y.z.zip` from the
[latest release](https://github.com/thijsw/sonicwave/releases/latest), unzip,
and drop `Sonicwave.app` into `/Applications`. Builds are signed and
**notarized by Apple** — they launch without Gatekeeper warnings.

**First launch:** open **Settings → Connection** (⌘,), enter your server
address and credentials, hit **Test Connection** → **Save & Connect**.
Credentials go straight to the Keychain; your password never travels in a URL.

## Highlights

**🎧 Serious about audio**
- **True gapless playback** — album transitions are seamless by construction.
- **Hardware sample-rate matching** (Audirvana/Roon-style, on by default):
  your DAC runs at each track's native rate, nothing gets resampled.
- **Streaming decode** of MP3, FLAC, AAC, WAV, AIFF and more — playback
  starts fast and memory stays flat.
- **Robust output routing**: pick any output device; unplugging or replugging
  a USB DAC mid-track recovers automatically, and your system-default device
  is never touched.

**📚 A library you can drive**
- Dense, sortable track table: double-click or ⏎ to play, ⌥-double-click to
  queue next, multi-select, drag to playlists.
- Column browser (Genre → Artist → Album), global search (⌘F), quality
  badges ("FLAC", "320 kbps") with lossless-first sorting.
- Server playlists round-trip fully: create, rename, reorder, delete.
- Favorites everywhere, with a ★ column.

**🖥 A proper Mac citizen**
- iTunes-style "LCD" in the toolbar; Now Playing panel with a reorderable
  Up Next queue; a menu-bar player that works with the window closed.
- Media keys, Control Center / Now Playing widget, live artwork.
- Light/Dark, full keyboard shortcuts, VoiceOver support, state restoration,
  sandboxed with a single entitlement (outgoing network).

## Requirements

- **macOS 15 Sequoia** or later
- An **OpenSubsonic-compatible server** (Navidrome, Gonic, LMS, Astiga, …)

## Status

v0.1.0 is out — feature-complete, with Mac App Store distribution in
progress. Deliberately out of scope for v1: offline downloads, scrobbling,
smart playlists, multi-server profiles, tag editing.

## For developers

Swift 6 (strict concurrency), SwiftUI with an AppKit core for the track
table, and **zero third-party dependencies**. Build with Xcode 26, or:

```sh
git clone https://github.com/thijsw/sonicwave.git && cd sonicwave
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' build   # or: test
```

The [`docs/`](docs/) directory holds the full design docs — architecture,
the playback-engine deep-dive (gapless + crackle forensics), API layer,
UI/UX rationale — and the running build log
([`docs/PROGRESS.md`](docs/PROGRESS.md)). The test suite runs hermetically;
an opt-in live suite exercises a real server via `SONICWAVE_HOST/USER/PASS`
env vars. Releases ship through [`scripts/release.sh`](scripts/release.sh)
(archive → notarize → staple) and [`scripts/publish.sh`](scripts/publish.sh).

## License

[MIT](LICENSE)

---

<div align="center">
<sub>Built for people who miss iTunes 12.6 — the patterns, not the chrome.</sub>
</div>
