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
PROVISION_PROFILE="${PROVISION_PROFILE:-}"

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

resolve_executable() {
  local build_dir="$1"
  if [[ -x "$build_dir/$APP_NAME" ]]; then
    printf '%s\n' "$build_dir/$APP_NAME"
    return
  fi

  local found
  found="$(find "$ROOT_DIR/.build" -path '*/release/'"$APP_NAME" -type f -perm -111 -print -quit)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return
  fi

  echo "error: release executable '$APP_NAME' not found under $build_dir or $ROOT_DIR/.build" >&2
  exit 1
}

rm -rf "$OUT_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

swift build -c release --arch arm64
BUILD_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
BINARY_SOURCE="$(resolve_executable "$BUILD_DIR")"

cp "$BINARY_SOURCE" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/Cribble.icns"
fi

shopt -s nullglob
RESOURCE_BUNDLES=("$BUILD_DIR"/*.bundle)
shopt -u nullglob
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
    echo "error: required SPM resource bundle missing from Resources/: $REQUIRED_BUNDLE" >&2
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
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.productivity</string>
  <key>ITSAppUsesNonExemptEncryption</key>
  <false/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if [[ -n "$PROVISION_PROFILE" ]]; then
  cp "$PROVISION_PROFILE" "$APP_CONTENTS/embedded.provisionprofile"
fi

chmod -R u+w "$APP_BUNDLE"
/usr/bin/xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete

/usr/bin/codesign --force --options runtime --entitlements "$ROOT_DIR/Cribble.entitlements" --sign "$APP_SIGN_IDENTITY" "$APP_BUNDLE"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
chmod -R u+w "$APP_BUNDLE"
/usr/bin/xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
  COPYFILE_DISABLE=1 /usr/bin/productbuild --component "$APP_BUNDLE" /Applications --sign "$INSTALLER_SIGN_IDENTITY" "$PKG_PATH"
  /usr/sbin/pkgutil --check-signature "$PKG_PATH"
else
  COPYFILE_DISABLE=1 /usr/bin/productbuild --component "$APP_BUNDLE" /Applications "$PKG_PATH"
  echo "Created unsigned package. Set INSTALLER_SIGN_IDENTITY to a Mac App Store installer signing identity before upload." >&2
fi

echo "$PKG_PATH"
