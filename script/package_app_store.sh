#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Cribble"
DISPLAY_NAME="Cribble: Markdown KB Manager"
BUNDLE_ID="com.cribble.reader"
MIN_SYSTEM_VERSION="15.0"
VERSION="${1:-$(<VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-Apple Distribution: Aman Pandey (JP4HU7X6G7)}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/appstore-build"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Cribble_App_Icons/cribble-icon-reference-light.icns"
PKG_PATH="$OUT_DIR/$APP_NAME-$VERSION-mas.pkg"

cd "$ROOT_DIR"

rm -rf "$OUT_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c release --arch arm64
BUILD_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

cp "$BUILD_DIR/$APP_NAME" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/Cribble.icns"
fi

if [[ -d "$BUILD_DIR/Cribble_Cribble.bundle" ]]; then
  cp -R "$BUILD_DIR/Cribble_Cribble.bundle" "$APP_RESOURCES/"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>Cribble</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --options runtime --entitlements "$ROOT_DIR/Cribble.entitlements" --sign "$APP_SIGN_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
  /usr/bin/productbuild --component "$APP_BUNDLE" /Applications --sign "$INSTALLER_SIGN_IDENTITY" "$PKG_PATH"
  /usr/sbin/pkgutil --check-signature "$PKG_PATH"
else
  /usr/bin/productbuild --component "$APP_BUNDLE" /Applications "$PKG_PATH"
  echo "Created unsigned package. Set INSTALLER_SIGN_IDENTITY to a Mac App Store installer signing identity before upload." >&2
fi

echo "$PKG_PATH"
