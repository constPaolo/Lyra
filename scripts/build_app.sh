#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="${APP_NAME:-Lyra}"
EXECUTABLE_NAME="${EXECUTABLE_NAME:-Lyra}"
CONFIGURATION="${CONFIGURATION:-release}"
RESOURCE_BUNDLE_NAME="${RESOURCE_BUNDLE_NAME:-Lyra_Lyra.bundle}"

BUNDLE_ID="${BUNDLE_ID:-com.paolo.lyra}"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-15.0}"

DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_PATH="${APP_PATH:-$DIST_DIR/$APP_NAME.app}"
PLIST_TEMPLATE="${PLIST_TEMPLATE:-$ROOT_DIR/packaging/Info.plist.template}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

ICON_SOURCE="$ROOT_DIR/icon.png"
if [[ ! -f "$ICON_SOURCE" ]]; then
    ICON_SOURCE="$ROOT_DIR/Sources/Lyra/AppIcon.png"
fi

if [[ ! -f "$PLIST_TEMPLATE" ]]; then
    echo "Missing plist template: $PLIST_TEMPLATE" >&2
    exit 1
fi
if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Missing icon source (expected icon.png or Sources/Lyra/AppIcon.png)." >&2
    exit 1
fi

echo "==> Building Swift package ($CONFIGURATION)"
swift build -c "$CONFIGURATION"

# Ask SwiftPM where it put the products: the layout changed between toolchains.
BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BIN_PATH="$BUILD_DIR/$EXECUTABLE_NAME"
RESOURCE_BUNDLE_PATH="$BUILD_DIR/$RESOURCE_BUNDLE_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
    echo "Missing executable after build: $BIN_PATH" >&2
    exit 1
fi
if [[ ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
    echo "Missing resource bundle after build: $RESOURCE_BUNDLE_PATH" >&2
    exit 1
fi

echo "==> Creating app bundle at $APP_PATH"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME"
cp -R "$RESOURCE_BUNDLE_PATH" "$APP_PATH/Contents/Resources/"

ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"

sed \
    -e "s|__APP_NAME__|$APP_NAME|g" \
    -e "s|__EXECUTABLE_NAME__|$EXECUTABLE_NAME|g" \
    -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
    -e "s|__VERSION__|$VERSION|g" \
    -e "s|__BUILD_NUMBER__|$BUILD_NUMBER|g" \
    -e "s|__MIN_SYSTEM_VERSION__|$MIN_SYSTEM_VERSION|g" \
    "$PLIST_TEMPLATE" > "$APP_PATH/Contents/Info.plist"

printf "APPL????" > "$APP_PATH/Contents/PkgInfo"

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Signing app with identity: $SIGN_IDENTITY"
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
    echo "==> Skipping codesign (set SIGN_IDENTITY to sign for distribution)"
fi

echo "==> App ready: $APP_PATH"
