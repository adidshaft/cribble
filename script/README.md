# script

Build, packaging, and release automation. Run from the repo root.

## Develop

| Script | What it does |
| --- | --- |
| `build_and_run.sh` | Build the Swift package and launch the app. |
| `build_metallib.sh` | Build the MLX Metal library used for on-device AI. |

## Release (direct DMG)

| Script | What it does |
| --- | --- |
| `package_release.sh <version>` | Universal release build → `Cribble.app` → signed (and optionally notarized) DMG in `releases/`. |
| `validate_release.sh <version>` | Verify arch, min macOS, signing, Gatekeeper, notarization, and DMG contents. |
| `build_dmg.py` / `create_dmg_background.swift` / `write_dmg_ds_store.py` | DMG layout, background art, and Finder window state. |

## Release (Mac App Store)

| Script | What it does |
| --- | --- |
| `package_app_store.sh` | Build + package the App Store variant. |
| `create_app_store_screenshots.py` | Generate App Store screenshot assets. |

See the root [README → Release](../README.md#release) and
[MAINTAINER_HANDBOOK.md](../MAINTAINER_HANDBOOK.md) for the full release runbook.
