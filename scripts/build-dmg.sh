#!/usr/bin/env bash
#
# Build VSVibe.app (Release) and package it into a drag-to-Applications DMG.
#
# Two modes:
#
#   1. Ad-hoc (default): runs on your machine; other Macs need right-click > Open.
#        scripts/build-dmg.sh
#
#   2. Developer ID + notarized: frictionless distribution to any Mac.
#        NOTARIZE=1 scripts/build-dmg.sh
#
#      Needs a "Developer ID Application" identity in a keychain on the search
#      list and notarytool credentials (see scripts/NOTARIZE.md).
#
# The archive is always built ad-hoc, then re-signed here inside-out (Sparkle's
# XPC services, Autoupdate, Updater.app, the framework, then the app) with the
# hardened runtime. No `--deep`, no Xcode account needed for export.
#
# Configurable via env:
#   NOTARIZE           1 = sign with Developer ID, notarize and staple (default 0)
#   MARKETING_VERSION  CFBundleShortVersionString (default: project.yml value)
#   BUILD_NUMBER       CFBundleVersion, compared by Sparkle
#                      (default: `git rev-list --count HEAD`)
#   DEV_ID_TEAM        Apple Developer Team ID (default: M3FHKUJ7Z3)
#   SIGN_IDENTITY      codesign identity for NOTARIZE=1, name or SHA-1
#                      (default: "Developer ID Application: Volodymyr Shyrochuk (DEV_ID_TEAM)")
#   SIGN_KEYCHAIN      keychain holding that identity (default: search list)
#   ASC_API_KEY_PATH   App Store Connect API key (.p8) for notarytool; with
#   ASC_API_KEY_ID     and ASC_API_ISSUER_ID. When unset, falls back to the
#   NOTARY_PROFILE     notarytool keychain profile (default: vsvibe-notary)
#
# Output: build/VSVibe.dmg. Derived data (incl. Sparkle's sign_update) lives in
# build/dd-release.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="VSVibe"
SCHEME="VSVibe"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/dd-release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
STAGING_DIR="$BUILD_DIR/dmg-staging"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"

NOTARIZE="${NOTARIZE:-0}"
DEV_ID_TEAM="${DEV_ID_TEAM:-M3FHKUJ7Z3}"
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-vsvibe-notary}"

DEFAULT_VERSION="$(/usr/bin/sed -n 's/.*MARKETING_VERSION: *"\(.*\)".*/\1/p' project.yml | head -1)"
MARKETING_VERSION="${MARKETING_VERSION:-${DEFAULT_VERSION:-0.0.0}}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
VOL_NAME="$APP_NAME $MARKETING_VERSION"

if [[ "$NOTARIZE" == "1" ]]; then
  SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Volodymyr Shyrochuk ($DEV_ID_TEAM)}"
else
  SIGN_IDENTITY="-"
fi

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Archiving Release build $MARKETING_VERSION ($BUILD_NUMBER)"
rm -rf "$ARCHIVE_PATH"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$ARCHIVE_PATH" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_IDENTITY="-" \
  archive

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: $APP_PATH not found after build" >&2
  exit 1
fi

# sign_code <path> [extra codesign args...]: hardened runtime, plus a secure
# timestamp and the given keychain for Developer ID.
sign_code() {
  local target="$1"
  shift
  local args=(--force --options runtime --sign "$SIGN_IDENTITY")
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    args+=(--timestamp=none)
  else
    args+=(--timestamp)
  fi
  if [[ -n "$SIGN_KEYCHAIN" ]]; then
    args+=(--keychain "$SIGN_KEYCHAIN")
  fi
  /usr/bin/codesign "${args[@]}" "$@" "$target"
}

# Inside-out, as Sparkle documents for manual signing.
sign_app() {
  local frameworks="$APP_PATH/Contents/Frameworks"
  local sparkle="$frameworks/Sparkle.framework"
  local item
  if [[ -d "$sparkle" ]]; then
    sign_code "$sparkle/Versions/B/XPCServices/Installer.xpc"
    sign_code "$sparkle/Versions/B/XPCServices/Downloader.xpc" --preserve-metadata=entitlements
    sign_code "$sparkle/Versions/B/Autoupdate"
    sign_code "$sparkle/Versions/B/Updater.app"
    sign_code "$sparkle"
  fi
  if [[ -d "$frameworks" ]]; then
    for item in "$frameworks"/*; do
      [[ "$item" == "$sparkle" ]] && continue
      sign_code "$item"
    done
  fi
  # The app has no entitlements (not sandboxed); re-signing drops any
  # get-task-allow Xcode may have added, which notarization rejects.
  sign_code "$APP_PATH"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
}

echo "==> Signing ($SIGN_IDENTITY)"
sign_app

# Package $APP_PATH into a fresh DMG at $DMG_PATH.
make_dmg() {
  rm -rf "$STAGING_DIR" "$DMG_PATH"
  mkdir -p "$STAGING_DIR"
  /usr/bin/ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
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
  if [[ -n "${ASC_API_KEY_PATH:-}" ]]; then
    : "${ASC_API_KEY_ID:?ASC_API_KEY_ID is required with ASC_API_KEY_PATH}"
    : "${ASC_API_ISSUER_ID:?ASC_API_ISSUER_ID is required with ASC_API_KEY_PATH}"
    xcrun notarytool submit "$1" \
      --key "$ASC_API_KEY_PATH" \
      --key-id "$ASC_API_KEY_ID" \
      --issuer "$ASC_API_ISSUER_ID" \
      --wait
  else
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
  fi
}

if [[ "$NOTARIZE" == "1" ]]; then
  # Pass 1: notarize + staple the .app, so the installed app passes Gatekeeper
  # even with no network. notarytool can't take a bare .app, so zip it first.
  echo "==> Notarizing the app"
  APP_ZIP="$BUILD_DIR/$APP_NAME.zip"
  /usr/bin/ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
  submit_notary "$APP_ZIP"
  xcrun stapler staple "$APP_PATH"
  rm -f "$APP_ZIP"

  # Pass 2: package the stapled app, sign + notarize + staple the DMG itself so
  # the downloaded disk image also verifies offline.
  echo "==> Creating DMG"
  make_dmg
  sign_code "$DMG_PATH"
  echo "==> Notarizing the DMG"
  submit_notary "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"

  echo "==> Verifying"
  xcrun stapler validate "$APP_PATH"
  xcrun stapler validate "$DMG_PATH"
  /usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"
else
  echo "==> Creating DMG"
  make_dmg
fi

echo "==> Done: $DMG_PATH ($MARKETING_VERSION, build $BUILD_NUMBER)"
ls -lh "$DMG_PATH"
