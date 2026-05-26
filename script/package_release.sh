#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Cribble"
DISPLAY_NAME="Cribble: Markdown Knowledge Base Manager"
BUNDLE_ID="com.cribble.reader"
MIN_SYSTEM_VERSION="15.0"
VERSION="${1:-$(<VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Aman Pandey (JP4HU7X6G7)}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/releases"
STAGE_DIR="$OUT_DIR/stage"
APP_BUNDLE="$STAGE_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_PATH="$OUT_DIR/$APP_NAME-$VERSION.dmg"
RW_DMG_PATH="$OUT_DIR/$APP_NAME-$VERSION-rw.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
APP_ICON_SOURCE="$ROOT_DIR/Cribble_App_Icons/cribble-icon-reference-light.icns"
PYTHON_DEPS="$OUT_DIR/python-deps"
DMG_ROOT="$STAGE_DIR/dmg-root"
DMG_BACKGROUND_DIR="$DMG_ROOT/.background"
DMG_BACKGROUND_PATH="$DMG_BACKGROUND_DIR/background.png"
DMG_MOUNT="$STAGE_DIR/mount"

cd "$ROOT_DIR"

rm -rf "$STAGE_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$OUT_DIR"

swift build -c release --arch arm64
BUILD_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

/usr/bin/lipo "$BUILD_DIR/$APP_NAME" -verify_arch arm64

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
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -rf "$DMG_ROOT" "$DMG_MOUNT"
mkdir -p "$DMG_BACKGROUND_DIR" "$DMG_MOUNT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
swift "$ROOT_DIR/script/create_dmg_background.swift" "$DMG_BACKGROUND_PATH"

rm -f "$DMG_PATH" "$RW_DMG_PATH" "$CHECKSUM_PATH"
/usr/bin/hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDRW "$RW_DMG_PATH"
DEVICE="$(/usr/bin/hdiutil attach "$RW_DMG_PATH" -readwrite -noverify -noautoopen -mountpoint "$DMG_MOUNT" | /usr/bin/awk '/Apple_HFS/ { print $1; exit }')"

cleanup_mount() {
  if [[ -n "${DEVICE:-}" ]]; then
    for _ in 1 2 3 4 5; do
      /usr/bin/hdiutil detach "$DEVICE" >/dev/null 2>&1 && return
      /usr/bin/hdiutil detach "$DEVICE" -force >/dev/null 2>&1 && return
      /bin/sleep 1
    done
  fi

  if [[ -d "$DMG_MOUNT" ]]; then
    for _ in 1 2 3; do
      /usr/bin/hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 && return
      /usr/bin/hdiutil detach "$DMG_MOUNT" -force >/dev/null 2>&1 && return
      /bin/sleep 1
    done
  fi
}
trap cleanup_mount EXIT

if ! PYTHONPATH="$PYTHON_DEPS" /usr/bin/python3 -c "import ds_store, mac_alias" >/dev/null 2>&1; then
  PIP_DISABLE_PIP_VERSION_CHECK=1 /usr/bin/python3 -m pip install --quiet --target "$PYTHON_DEPS" ds_store mac_alias
fi

/usr/bin/SetFile -a V "$DMG_MOUNT/.background"
PYTHONPATH="$PYTHON_DEPS" /usr/bin/python3 "$ROOT_DIR/script/write_dmg_ds_store.py" \
  "$DMG_MOUNT" \
  "$DMG_MOUNT/.background/background.png" \
  "$APP_NAME.app" \
  "Applications"

/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to POSIX file "$DMG_MOUNT" as alias
  open dmgFolder
  delay 1
  set dmgWindow to container window of dmgFolder
  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set bounds of dmgWindow to {120, 120, 880, 580}
  set viewOptions to icon view options of dmgWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 128
  set background picture of viewOptions to POSIX file "$DMG_MOUNT/.background/background.png"
  set position of item "$APP_NAME.app" of dmgFolder to {182, 228}
  set position of item "Applications" of dmgFolder to {575, 228}
  update dmgFolder without registering applications
  delay 2
  close dmgWindow
end tell
APPLESCRIPT

/bin/sync
cleanup_mount
/bin/sleep 2
trap - EXIT

/usr/bin/hdiutil convert "$RW_DMG_PATH" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH"
/usr/bin/shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"
rm -f "$RW_DMG_PATH"

echo "$DMG_PATH"
echo "$CHECKSUM_PATH"
