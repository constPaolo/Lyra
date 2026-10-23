#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-Lyra}"
VERSION="${VERSION:-0.1.0}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_PATH="${APP_PATH:-$DIST_DIR/$APP_NAME.app}"
VOL_NAME="${VOL_NAME:-$APP_NAME}"
DMG_PATH="${DMG_PATH:-$DIST_DIR/$APP_NAME-$VERSION.dmg}"
DMG_SIGN_IDENTITY="${DMG_SIGN_IDENTITY:-${SIGN_IDENTITY:-}}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

STAGING_DIR="$DIST_DIR/.dmg-staging"
TEMP_DMG="$DIST_DIR/.dmg-temp.dmg"

if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle not found at $APP_PATH, building first..."
    "$ROOT_DIR/scripts/build_app.sh"
fi

mkdir -p "$DIST_DIR"
rm -rf "$STAGING_DIR" "$TEMP_DMG" "$DMG_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG image"
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDRW \
    "$TEMP_DMG" >/dev/null

echo "==> Compressing DMG"
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -rf "$STAGING_DIR" "$TEMP_DMG"

if [[ -n "$DMG_SIGN_IDENTITY" ]]; then
    echo "==> Signing DMG with identity: $DMG_SIGN_IDENTITY"
    codesign --force --timestamp --sign "$DMG_SIGN_IDENTITY" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
else
    echo "==> Skipping DMG signing (set DMG_SIGN_IDENTITY to sign)"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    echo "==> Submitting DMG for notarization via profile: $NOTARY_PROFILE"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
fi

echo "==> DMG ready: $DMG_PATH"
