#!/usr/bin/env bash
#
# Regenerates the MLX Metal shader library (mlx-swift_Cmlx.bundle / default.metallib)
# and caches it under Vendor/MLXMetallib so the SwiftPM command-line build can
# ship a working on-device MLX engine.
#
# Why: mlx-swift's Metal shaders can ONLY be compiled by an Xcode build (see
# mlx-swift README). Cribble ships via `swift build` + hand assembly, which never
# produces the metallib. This script runs the Xcode build just to produce that
# one bundle, then caches it. Re-run it whenever the mlx-swift version changes.
#
# Requires the Metal Toolchain component:
#   xcodebuild -downloadComponent MetalToolchain
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DEST_DIR="$ROOT_DIR/Vendor/MLXMetallib"
DERIVED="$ROOT_DIR/.xcdd"
WORKSPACE="$ROOT_DIR/Cribble.xcworkspace"
MOVED_WORKSPACE=""

# xcodebuild auto-discovers the schemeless workspace and fails; build the
# package directly by moving the workspace aside, always restoring it.
restore_workspace() {
  if [[ -n "$MOVED_WORKSPACE" && -d "$MOVED_WORKSPACE" ]]; then
    mv "$MOVED_WORKSPACE" "$WORKSPACE"
  fi
}
trap restore_workspace EXIT

if [[ -d "$WORKSPACE" ]]; then
  MOVED_WORKSPACE="$(mktemp -d)/Cribble.xcworkspace"
  mv "$WORKSPACE" "$MOVED_WORKSPACE"
fi

echo "Building MLX metallib via xcodebuild (this is slow)…"
# CODE_SIGNING_ALLOWED=NO so the app-bundling/signing steps don't fail; the
# metallib is produced earlier in the graph regardless.
xcodebuild -scheme Cribble \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO \
  build || true

SRC="$DERIVED/Build/Products/Release/mlx-swift_Cmlx.bundle"
if [[ ! -d "$SRC" ]]; then
  echo "error: mlx-swift_Cmlx.bundle was not produced. Is the Metal Toolchain installed?" >&2
  echo "       Run: xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/mlx-swift_Cmlx.bundle"
/usr/bin/ditto "$SRC" "$DEST_DIR/mlx-swift_Cmlx.bundle"
echo "Cached metallib bundle at $DEST_DIR/mlx-swift_Cmlx.bundle"
