# CLAUDE.md

Sonicwave: native macOS (15+) music player for OpenSubsonic/Navidrome servers.
Swift 6 (strict concurrency), SwiftUI + AppKit track table, streaming-only.

## Build / test

```sh
xcodebuild -project Sonicwave.xcodeproj -scheme Sonicwave \
  -destination 'platform=macOS' build CODE_SIGNING_ALLOWED=NO   # or: test
swiftlint   # config in .swiftlint.yml; must pass clean
```

- Tests are hermetic (Swift Testing, `SonicwaveTests/`). `LiveDecodeTests`
  hit a real server only when `SONICWAVE_HOST/USER/PASS` are set.
- CI (`.github/workflows/tests.yml`) runs the suite on every push/PR.
- Baseline: zero compiler warnings, zero SwiftLint violations.

## Read the right doc before working (docs/)

- `00` scope & non-goals · `01` architecture/layers · `10` roadmap/status
- API/networking/auth → `02` · playback engine/gapless/devices → `03`
- UI/UX rationale & interaction rules → `04` · artwork cache → `05`
- system integration → `06` · release/distribution → `07` · testing → `08`
- `PROGRESS.md` — running build log, newest-first dated entries. Append an
  entry for every substantive change; keep the "Milestone status" and
  "Verification status" blocks at the top current.

## House rules

- **Zero third-party dependencies** — Apple frameworks only.
- Credentials live in the Keychain; never in URLs, logs, or commits.
- Live-verify player behavior against a real server before claiming done
  (the demo server button in Settings → Connection works for quick checks).
- Releases: `scripts/publish.sh <version>` (bump → notarized build → tag →
  GitHub Release). The website (`site/`, GitHub Pages via
  `.github/workflows/pages.yml`) redeploys itself on release and stamps the
  latest version into the page — no manual edits needed. After publishing:
  hand-write the release notes (`gh release edit`), add a website changelog
  entry, log in PROGRESS.md, and **sync README.md** with the shipped
  feature set (briefly — fold into existing bullets).

## Hard-won gotchas (don't re-break these)

- Up Next rows: no `.contentShape`/tap gestures — they silently kill the
  List's drag reordering (`04`).
- The Now Playing panel is deliberately NOT `.inspector` and lives inside
  the detail column; moving it re-triggers split-view/toolbar jank (`04`).
- NSToolbar swallows right-clicks on its items — no context menus there.
- AirPlay devices: never poke nominal sample rate (fixed network clock);
  rate matching must keep skipping AirPlay transports (`03`).
- Route/config changes rebuild the engine and hard-restart at the playhead;
  recovery echoes are guarded — read `03` before touching that path.
