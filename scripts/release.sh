#!/bin/bash
# Sonicwave release pipeline. See docs/07-distribution.md.
#
#   scripts/release.sh [developer-id|app-store]     (default: developer-id)
#
# developer-id — archive → export a Developer ID .app → verify signature →
#   notarize + staple (when notary credentials are configured) → zip.
#   One-time notarization setup (needs an app-specific password from
#   appleid.apple.com, or an App Store Connect API key):
#     xcrun notarytool store-credentials sonicwave \
#       --apple-id <apple-id> --team-id 4HNWJ993V9
#
# app-store — archive → export a signed .pkg for App Store Connect upload.
#   Prerequisites are listed in scripts/ExportOptions-app-store.plist.
set -euo pipefail

cd "$(dirname "$0")/.."

METHOD="${1:-developer-id}"
SCHEME=Sonicwave
BUILD=build
ARCHIVE="$BUILD/Sonicwave.xcarchive"
EXPORT="$BUILD/export-$METHOD"
NOTARY_PROFILE=sonicwave

case "$METHOD" in
  developer-id|app-store) ;;
  *) echo "usage: $0 [developer-id|app-store]" >&2; exit 2 ;;
esac

echo "==> Archiving (Release)"
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild -project Sonicwave.xcodeproj -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive | tail -2

echo "==> Exporting ($METHOD)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "scripts/ExportOptions-$METHOD.plist" \
  -exportPath "$EXPORT" | tail -2

if [[ "$METHOD" == "app-store" ]]; then
  PKG=$(ls "$EXPORT"/*.pkg)
  echo "==> Exported $PKG"
  echo "Upload with: xcrun altool --upload-package … or Xcode Organizer /"
  echo "Transporter. Done."
  exit 0
fi

APP="$EXPORT/Sonicwave.app"

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E 'Authority=Developer ID|flags=.*runtime' || {
  echo "error: expected a Developer ID signature with the hardened runtime" >&2
  exit 1
}

VERSION=$(defaults read "$(pwd)/$APP/Contents/Info" CFBundleShortVersionString)
ZIP="$BUILD/Sonicwave-$VERSION.zip"

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "==> Notarizing (profile: $NOTARY_PROFILE)"
  ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
  xcrun notarytool submit "$BUILD/notarize.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait
  rm "$BUILD/notarize.zip"
  echo "==> Stapling"
  xcrun stapler staple "$APP"
  echo "==> Gatekeeper assessment"
  spctl --assess --type execute --verbose=2 "$APP"
else
  echo "==> Skipping notarization (no '$NOTARY_PROFILE' keychain profile;"
  echo "    see the header of this script for the one-time setup)"
fi

echo "==> Zipping"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "==> Done: $ZIP"
