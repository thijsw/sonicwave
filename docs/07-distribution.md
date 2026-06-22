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

## Signing & notarization ✅

- **Mac App Store build:** managed Apple Distribution signing + App Store
  provisioning profile; upload via Xcode Organizer / `xcodebuild` +
  `altool`/`notarytool` pipeline as applicable.
- **Direct-distribution fallback (optional):** Developer ID Application signing
  + **notarization** (`notarytool`) + stapling. Build code signing into the CI
  pipeline from the start (Hardened Runtime enabled) so switching distribution
  modes is configuration, not rework.
- Enable **Hardened Runtime**; no special exceptions expected for v1
  (AVAudioEngine/MediaPlayer/Keychain/URLSession need none beyond the sandbox
  network entitlement).

## Review considerations 🔶

- Functionality requires a user-supplied server — provide reviewer notes / a
  demo server + credentials, or a clear empty/onboarding state, so App Review
  can exercise the app.
- Ensure graceful behavior with no server configured (onboarding to Settings)
  and on auth failure (re-auth prompt) — see `02`.

## Checklist
- [ ] App Sandbox on; only `network.client` (+ Keychain) entitled.
- [ ] Hardened Runtime on; no unjustified exceptions.
- [ ] Credentials in Keychain; nothing sensitive logged.
- [ ] Info.plist: min macOS 15, music category, versioning, icon.
- [ ] No Tahoe-only API without `#available` guard.
- [ ] App Privacy details accurate (no tracking/analytics v1).
- [ ] Reviewer notes / demo credentials prepared.
- [ ] Signing pipeline produces MAS build (and Developer ID build if needed).
