#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-$(<VERSION)}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/releases/stage/Cribble.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/releases/Cribble-$VERSION.dmg}"
CHECKSUM_PATH="$DMG_PATH.sha256"
APPCAST_PATH="${APPCAST_PATH:-$ROOT_DIR/releases/appcast.xml}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG: $DMG_PATH" >&2
  exit 1
fi

if [[ ! -f "$CHECKSUM_PATH" ]]; then
  echo "Missing checksum: $CHECKSUM_PATH" >&2
  exit 1
fi

if [[ "${REQUIRE_APPCAST:-0}" == "1" && ! -f "$APPCAST_PATH" ]]; then
  echo "Missing appcast: $APPCAST_PATH" >&2
  exit 1
fi

if /usr/bin/grep -q '/' "$CHECKSUM_PATH"; then
  echo "Checksum file must contain only the DMG basename, not a local path" >&2
  exit 1
fi

echo "== Binary architecture =="
/usr/bin/lipo -info "$APP_PATH/Contents/MacOS/Cribble"
/usr/bin/lipo "$APP_PATH/Contents/MacOS/Cribble" -verify_arch arm64

echo
echo "== Minimum macOS =="
/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP_PATH/Contents/Info.plist"

echo
echo "== Code signature =="
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo
echo "== Sparkle updater =="
/bin/test -d "$APP_PATH/Contents/Frameworks/Sparkle.framework"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH/Contents/Frameworks/Sparkle.framework"
/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP_PATH/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Print :SUEnableInstallerLauncherService" "$APP_PATH/Contents/Info.plist"
/usr/bin/otool -L "$APP_PATH/Contents/MacOS/Cribble" | /usr/bin/grep -q '@rpath/Sparkle.framework'
if [[ -f "$APPCAST_PATH" ]]; then
  /usr/bin/grep -q "Cribble-$VERSION.dmg" "$APPCAST_PATH"
fi

echo
echo "== Resource bundles =="
REQUIRED_RESOURCE_BUNDLES=(
  "Cribble_Cribble.bundle"
  "swiftui-math_SwiftUIMath.bundle"
  "textual_Textual.bundle"
)
for bundle in "${REQUIRED_RESOURCE_BUNDLES[@]}"; do
  /bin/test -d "$APP_PATH/Contents/Resources/$bundle"
  echo "$bundle"
done

echo
echo "== Gatekeeper app assessment =="
if [[ "${REQUIRE_GATEKEEPER:-0}" == "1" ]]; then
  /usr/sbin/spctl -a -vv --type execute "$APP_PATH"
else
  echo "skipped (set REQUIRE_GATEKEEPER=1 for Developer ID/notarized release validation)"
fi

echo
echo "== Notarization tickets =="
if [[ "${REQUIRE_NOTARIZATION:-0}" == "1" ]]; then
  /usr/bin/xcrun stapler validate "$APP_PATH"
  /usr/bin/xcrun stapler validate "$DMG_PATH"
else
  echo "skipped (set REQUIRE_NOTARIZATION=1 for notarized release validation)"
fi

echo
echo "== DMG contents =="
MOUNT_DIR="$(/usr/bin/mktemp -d /tmp/cribble-release-check.XXXXXX)"
DEVICE=""
cleanup() {
  if [[ -n "$DEVICE" ]]; then
    /usr/bin/hdiutil detach "$DEVICE" >/dev/null 2>&1 || true
  fi
  /bin/rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

DEVICE="$(/usr/bin/hdiutil attach "$DMG_PATH" -readonly -noverify -noautoopen -mountpoint "$MOUNT_DIR" | /usr/bin/awk '/Apple_HFS|Apple_APFS/ { print $1; exit }')"
/bin/test -d "$MOUNT_DIR/Cribble.app"
/bin/test -L "$MOUNT_DIR/Applications"
if [[ ! -f "$MOUNT_DIR/.background/background.png" && ! -f "$MOUNT_DIR/.background.png" ]]; then
  echo "Missing DMG background image" >&2
  exit 1
fi
for bundle in "${REQUIRED_RESOURCE_BUNDLES[@]}"; do
  /bin/test -d "$MOUNT_DIR/Cribble.app/Contents/Resources/$bundle"
done
/bin/ls -la "$MOUNT_DIR"

echo
echo "Release artifact looks ready."
