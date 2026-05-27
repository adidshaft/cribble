#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-$(<VERSION)}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/releases/stage/Cribble.app}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/releases/Cribble-$VERSION.dmg}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Missing DMG: $DMG_PATH" >&2
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
/usr/sbin/spctl -a -vv --type execute "$APP_PATH"

echo
echo "== Notarization tickets =="
/usr/bin/xcrun stapler validate "$APP_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"

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
