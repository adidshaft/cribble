#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Cribble"
DISPLAY_NAME="Cribble: Markdown Knowledge Base Manager"
BUNDLE_ID="com.cribble.reader"
MIN_SYSTEM_VERSION="15.0"
VERSION="${1:-$(<VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Aman Pandey (JP4HU7X6G7)}"
# Architectures to build, space-separated. Default to a universal binary so
# Intel Macs aren't silently locked out. Set ARCHS="arm64" to opt back into
# Apple-Silicon-only.
ARCHS="${ARCHS:-arm64 x86_64}"
# Keychain profile for `xcrun notarytool` if you want this script to notarize
# + staple the DMG automatically. Leave NOTARY_PROFILE empty to skip.
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

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
APP_NOTARY_ZIP="$OUT_DIR/$APP_NAME-$VERSION-app-notary.zip"
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

resolve_executable() {
  local build_dir="$1"
  local arch="$2"
  if [[ -x "$build_dir/$APP_NAME" ]]; then
    printf '%s\n' "$build_dir/$APP_NAME"
    return
  fi

  local found
  found="$(find "$ROOT_DIR/.build" -path '*/release/'"$APP_NAME" -type f -perm -111 -exec sh -c '/usr/bin/lipo "$1" -verify_arch "$2" >/dev/null 2>&1 && printf "%s\n" "$1"' sh {} "$arch" \; -quit)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return
  fi

  echo "error: release executable '$APP_NAME' for arch '$arch' not found under $build_dir or $ROOT_DIR/.build" >&2
  exit 1
}

SLICE_BINARIES=()
LAST_BUILD_DIR=""
for ARCH in $ARCHS; do
  swift build -c release --arch "$ARCH"
  ARCH_BUILD_DIR="$(swift build -c release --arch "$ARCH" --show-bin-path)"
  ARCH_BINARY="$(resolve_executable "$ARCH_BUILD_DIR" "$ARCH")"
  /usr/bin/lipo "$ARCH_BINARY" -verify_arch "$ARCH"
  SLICE_BINARIES+=("$ARCH_BINARY")
  LAST_BUILD_DIR="$ARCH_BUILD_DIR"
done

# If multiple slices, lipo them into a universal binary; otherwise just copy.
if (( ${#SLICE_BINARIES[@]} > 1 )); then
  /usr/bin/lipo -create "${SLICE_BINARIES[@]}" -output "$APP_BINARY"
else
  cp "${SLICE_BINARIES[0]}" "$APP_BINARY"
fi
chmod +x "$APP_BINARY"
# Sanity-check the final binary's architectures and minimum macOS — these
# are the two things that most often make the DMG refuse to launch on
# someone else's Mac.
/usr/bin/lipo -info "$APP_BINARY"
/usr/bin/otool -l "$APP_BINARY" | /usr/bin/awk '/LC_BUILD_VERSION/{flag=1} flag{print; if (/sdk/){flag=0}}'

BUILD_DIR="$LAST_BUILD_DIR"

if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/Cribble.icns"
else
  echo "warning: app icon not found at $APP_ICON_SOURCE — shipping default Swift icon" >&2
fi

# Copy every SwiftPM resource bundle produced by the linked package graph.
# `Bundle.module` accessors fatalError when their bundle is missing on a
# clean machine, so copying only Cribble_Cribble.bundle can crash features
# supplied by dependencies such as Textual and SwiftUIMath.
shopt -s nullglob
RESOURCE_BUNDLES=("$BUILD_DIR"/*.bundle)
shopt -u nullglob
if (( ${#RESOURCE_BUNDLES[@]} == 0 )); then
  echo "error: no SPM resource bundles found in $BUILD_DIR" >&2
  exit 1
fi

for RESOURCE_BUNDLE in "${RESOURCE_BUNDLES[@]}"; do
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
done

REQUIRED_RESOURCE_BUNDLES=(
  "Cribble_Cribble.bundle"
  "swiftui-math_SwiftUIMath.bundle"
  "textual_Textual.bundle"
)

for REQUIRED_BUNDLE in "${REQUIRED_RESOURCE_BUNDLES[@]}"; do
  if [[ ! -d "$APP_RESOURCES/$REQUIRED_BUNDLE" ]]; then
    echo "error: required SPM resource bundle missing from app: $REQUIRED_BUNDLE" >&2
    exit 1
  fi
done

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
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

chmod -R u+w "$APP_BUNDLE"
/usr/bin/xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

/usr/bin/codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
chmod -R u+w "$APP_BUNDLE"
/usr/bin/xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ -n "$NOTARY_PROFILE" ]]; then
  rm -f "$APP_NOTARY_ZIP"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$APP_NOTARY_ZIP"
  echo "Submitting app bundle to Apple notary service via profile '$NOTARY_PROFILE'..."
  /usr/bin/xcrun notarytool submit "$APP_NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "Stapling notary ticket to app bundle..."
  /usr/bin/xcrun stapler staple "$APP_BUNDLE"
  /usr/bin/xcrun stapler validate "$APP_BUNDLE"
  rm -f "$APP_NOTARY_ZIP"
fi

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
rm -f "$RW_DMG_PATH"

# Notarize + staple if a keychain profile was provided. Without this,
# Gatekeeper on macOS 15.4+ refuses to open the DMG with "Cribble is
# damaged" — that's the most common cause of "the app crashes" reports
# from non-developer users.
if [[ -n "$NOTARY_PROFILE" ]]; then
  echo "Submitting DMG to Apple notary service via profile '$NOTARY_PROFILE'..."
  /usr/bin/xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "Stapling notary ticket to DMG..."
  /usr/bin/xcrun stapler staple "$DMG_PATH"
  /usr/bin/xcrun stapler validate "$DMG_PATH"
else
  echo "warning: NOTARY_PROFILE not set — DMG is signed but NOT notarized." >&2
  echo "         Gatekeeper will block this DMG on other Macs. Set" >&2
  echo "         NOTARY_PROFILE=<keychain-profile> to notarize automatically." >&2
fi

/usr/bin/shasum -a 256 "$DMG_PATH" > "$CHECKSUM_PATH"

echo "$DMG_PATH"
echo "$CHECKSUM_PATH"
