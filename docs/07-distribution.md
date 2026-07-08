# 07 — Distribution: Sandbox, Entitlements, Mac App Store

Primary distribution is the **Mac App Store**, which mandates the **App
Sandbox**. Design signing/notarization in from day one so a direct-distribution
fallback is also possible.

## App Sandbox ✅

- Enable `com.apple.security.app-sandbox`.
- Request only what's needed:
  - `com.apple.security.network.client` — outgoing connections to the
    OpenSubsonic server (the only essential entitlement for v1).
  - Keychain access for stored credentials (see below).
  - **Not** requested: incoming network server, camera/mic, location, address
    book, etc. Add `com.apple.security.files.user-selected.read-only` +
    security-scoped bookmarks **only if** external-file drag import ships later
    (currently ⏳, see `04`/`06`).

## Keychain ✅

- Store the server base URL, username, and password (token+salt) or API key in
  the Keychain via the Security framework (`SecItem*`) or a thin wrapper.
- Use a Keychain access group / service identifier tied to the app's bundle ID.
- Never store the derived token or log credentials. Credentials are entered and
  updated only in the Settings window.

## App Store Connect / packaging ✅

- Bundle identifier, app category (Music), and app icon set.
- `Info.plist`: app name "Sonicwave", versioning (`CFBundleShortVersionString`
  + build), minimum system version (macOS 15.0), `LSApplicationCategoryType`
  = `public.app-category.music`.
- **Privacy:** the app sends credentials and stream requests only to the
  user-configured server. Provide an accurate App Privacy disclosure
  (no tracking, no analytics in v1). Add any usage-description strings only for
  capabilities actually used (none extra for v1).
- No private APIs; no Tahoe-only hard dependencies (availability-guarded — see
  `04`).

## Signing & notarization ✅ (pipeline implemented 2026-07-07)

`scripts/release.sh [developer-id|app-store]` archives the Release
configuration and exports a signed artifact (`scripts/ExportOptions-*.plist`).
Release build settings: Manual signing, Developer ID Application
(team 4HNWJ993V9), **Hardened Runtime on** — verified: no runtime exceptions
needed (playback, Keychain, networking all work in the exported app).

- **Developer ID path (working end-to-end):** archive → export → signature
  verification (`codesign --verify --strict` + Developer ID authority +
  `runtime` flag check) → notarize + staple + Gatekeeper assess (runs when a
  `sonicwave` notarytool keychain profile exists; skipped with instructions
  otherwise) → versioned zip. One-time setup for notarization:
  `xcrun notarytool store-credentials sonicwave --apple-id … --team-id
  4HNWJ993V9` (app-specific password or ASC API key).
- **Mac App Store path (config prepared; blocked on portal artifacts):**
  `release.sh app-store` exports an upload-ready `.pkg` once these exist —
  an **Apple Distribution** + **Mac Installer Distribution** certificate, an
  App Store Connect app record for `nl.huell.sonicwave`, and a Mac App Store
  provisioning profile (prerequisites also listed in
  `ExportOptions-app-store.plist`).
- Debug still signs with Developer ID (hardened runtime off) for the stable
  Keychain designated requirement — see `PROGRESS.md`.
- **GitHub Releases:** `scripts/publish.sh <version>` bumps
  `MARKETING_VERSION` + build number, commits, runs the notarized
  Developer ID build, refuses to ship anything Gatekeeper rejects, tags
  `v<version>`, pushes, and creates the GitHub Release with the zip attached
  (`gh release create … --generate-notes`). Downloads are public only once
  the repository is public.

## Review considerations 🔶

- Functionality requires a user-supplied server — provide reviewer notes / a
  demo server + credentials, or a clear empty/onboarding state, so App Review
  can exercise the app.
- Ensure graceful behavior with no server configured (onboarding to Settings)
  and on auth failure (re-auth prompt) — see `02`.

## Checklist
- [x] App Sandbox on; only `network.client` (+ Keychain) entitled — verified
      on the exported artifact (`codesign -d --entitlements`).
- [x] Hardened Runtime on (Release); no exceptions needed — exported app
      plays audio and reads the Keychain.
- [x] Credentials in Keychain; nothing sensitive logged.
- [x] Info.plist: min macOS 15, music category, versioning, icon (placeholder
      icon still to be replaced before submission).
- [x] No Tahoe-only API without `#available` guard (none used).
- [ ] App Privacy details accurate (no tracking/analytics v1) — fill in at
      App Store Connect submission time.
- [ ] Reviewer notes / demo credentials prepared.
- [x] Signing pipeline produces a verified Developer ID build
      (`scripts/release.sh`); MAS export configured, pending the Apple
      Distribution certificate + app record + profile.
- [x] Notarization round-trip — Accepted, stapled, Gatekeeper
      `source=Notarized Developer ID` (2026-07-07).
