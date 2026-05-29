#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Cribble"
DISPLAY_NAME="Cribble: Markdown Knowledge Base Manager"
BUNDLE_ID="com.cribble.reader"
MIN_SYSTEM_VERSION="15.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_ICON_SOURCE="$ROOT_DIR/Cribble_App_Icons/cribble-icon-reference-light.icns"
SPARKLE_PUBLIC_ED_KEY="YfAh7JbGoiQoB9KqD7U9S+Olejk9jDNSUc7Z0I+o820="
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-https://github.com/adidshaft/cribble/releases/download/stable/appcast.xml}"

cd "$ROOT_DIR"
pkill -x "$APP_NAME" >/dev/null 2>&1 || true
VERSION_STR="$(cat "$ROOT_DIR/VERSION" | tr -d '\n')"
BUILD_NUMBER="${BUILD_NUMBER:-$(/usr/bin/awk -F. '{ printf "%d%02d%02d", $1, $2, $3 }' <<<"$VERSION_STR")}"

swift build
BUILD_BINARY="$(swift build --show-bin-path)/$APP_NAME"
BUILD_DIR="$(swift build --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_FRAMEWORKS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
/usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true

if [[ -d "$BUILD_DIR/Sparkle.framework" ]]; then
  /usr/bin/ditto "$BUILD_DIR/Sparkle.framework" "$APP_FRAMEWORKS/Sparkle.framework"
fi

if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/Cribble.icns"
fi

shopt -s nullglob
RESOURCE_BUNDLES=("$BUILD_DIR"/*.bundle)
shopt -u nullglob
for RESOURCE_BUNDLE in "${RESOURCE_BUNDLES[@]}"; do
  # Resources live in Contents/Resources (the standard location the app's
  # bundle-lookup redirect resolves). NOTE: do NOT also copy these beside
  # Contents/ — loose items at the .app root are "unsealed contents" that make
  # the code signature invalid, and the kernel then SIGKILLs the app on launch.
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
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
  <string>$VERSION_STR</string>
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
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_ED_KEY</string>
  <key>SUEnableInstallerLauncherService</key>
  <true/>
</dict>
</plist>
PLIST

# Sign inside-out. A single `--deep` ad-hoc pass mis-signs Sparkle's nested
# signed code (XPC services + helpers), producing an invalid signature the
# kernel kills on launch. Sign the nested pieces, then the framework, then the
# main executable, then the app bundle.
SPK="$APP_FRAMEWORKS/Sparkle.framework"
if [[ -d "$SPK" ]]; then
  SPK_V="$SPK/Versions/B"
  for item in \
    "$SPK_V/XPCServices/Installer.xpc" \
    "$SPK_V/XPCServices/Downloader.xpc" \
    "$SPK_V/Autoupdate" \
    "$SPK_V/Updater.app"; do
    [[ -e "$item" ]] && /usr/bin/codesign --force --sign - "$item"
  done
  /usr/bin/codesign --force --sign - "$SPK"
fi
/usr/bin/codesign --force --sign - "$APP_BINARY"
/usr/bin/codesign --force --sign - "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 3
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
