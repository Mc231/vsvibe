#!/usr/bin/env bash
#
# Build VSVibe.app (Release) and package it into a drag-to-Applications DMG.
#
# Two modes:
#
#   1. Ad-hoc (default) — runs on your machine; other Macs need right-click → Open.
#        scripts/build-dmg.sh
#
#   2. Developer ID + notarized — frictionless distribution to any Mac.
#        NOTARIZE=1 scripts/build-dmg.sh
#
#      Requires (one-time setup, see scripts/NOTARIZE.md):
#        - A "Developer ID Application" certificate in your keychain.
#        - A stored notarytool credential profile (App Store Connect API key).
#
# Configurable via env:
#   NOTARIZE         set to 1 to sign with Developer ID + notarize + staple
#   DEV_ID_TEAM      Apple Developer Team ID (default: M3FHKUJ7Z3 — personal)
#   NOTARY_PROFILE   notarytool keychain profile name (default: vsvibe-notary)
#
# Output: build/VSVibe.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="VSVibe"
SCHEME="VSVibe"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"

NOTARIZE="${NOTARIZE:-0}"
DEV_ID_TEAM="${DEV_ID_TEAM:-M3FHKUJ7Z3}"
NOTARY_PROFILE="${NOTARY_PROFILE:-vsvibe-notary}"

# Pull the marketing version out of project.yml for the volume name.
VERSION="$(/usr/bin/sed -n 's/.*CFBundleShortVersionString: *"\(.*\)".*/\1/p' project.yml | head -1)"
VOL_NAME="$APP_NAME ${VERSION:-}"

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Archiving Release build"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

if [[ "$NOTARIZE" == "1" ]]; then
  echo "==> Exporting with Developer ID signing (team $DEV_ID_TEAM)"
  EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
  cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$DEV_ID_TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST"
  APP_PATH="$EXPORT_DIR/$APP_NAME.app"
else
  APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH not found after build" >&2
  exit 1
fi

# Package $APP_PATH into a fresh DMG at $DMG_PATH.
make_dmg() {
  rm -rf "$STAGING_DIR" "$DMG_PATH"
  mkdir -p "$STAGING_DIR"
  cp -R "$APP_PATH" "$STAGING_DIR/"
  ln -s /Applications "$STAGING_DIR/Applications"
  hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  rm -rf "$STAGING_DIR"
}

submit_notary() {
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

if [[ "$NOTARIZE" == "1" ]]; then
  # Pass 1: notarize + staple the .app, so the launched app passes Gatekeeper
  # even with no network. notarytool can't take a bare .app, so zip it first.
  echo "==> Notarizing the app"
  APP_ZIP="$BUILD_DIR/$APP_NAME.zip"
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
  submit_notary "$APP_ZIP"
  xcrun stapler staple "$APP_PATH"
  rm -f "$APP_ZIP"

  # Pass 2: package the now-stapled app into a DMG and notarize + staple the DMG
  # itself, so the downloaded disk image also verifies offline.
  echo "==> Creating DMG"
  make_dmg
  echo "==> Notarizing the DMG"
  submit_notary "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"

  echo "==> Verifying"
  xcrun stapler validate "$APP_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "==> Creating DMG"
  make_dmg
fi

echo "==> Done: $DMG_PATH"
ls -lh "$DMG_PATH"
