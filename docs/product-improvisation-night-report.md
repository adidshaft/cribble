# Product Improvisation Night Report

Date: 2026-06-07
Branch: `codex/product-improvisation-night`

## What changed

### Extension foundation

Cribble now has a concrete, safe foundation for plugins/extensions:

- `cribble-extension.json` manifests with `apiVersion`, reverse-DNS ids, typed extension kinds, typed permissions, optional homepage, and safe relative entrypoints.
- Discovery from the user's Application Support extension folder.
- Discovery from each opened folder's `.cribble/extensions` directory.
- Settings UI for installed extensions, load warnings, permissions, location, enable/disable state, and starter manifest creation.
- Duplicate id handling, with project-local extensions taking precedence over user-level extensions.
- Data-only quick action contributions that merge enabled extension prompts into the Chat HUD empty state and `/` slash palette.
- Data-only intelligence provider profiles that add OpenAI-compatible runner presets to the Intelligence HUD, including remote-runner warnings.
- A Project Intelligence preflight sheet in the HUD before starting folder/all-folder scans, summarizing scope, local vs remote processing, disk/cache expectations, and performance mode.
- The same preflight confirmation now guards sidebar/context-menu Project Intelligence starts, so quick entry points are safer too.
- A richer empty state that lets new users open a Markdown folder, open the bundled DemoNotes tour, or reset DemoNotes to a clean sandbox.
- Extension registry coverage for user/project scans, project-over-user duplicate precedence, warnings, and disabled extension filtering.
- Cleaned up a SQLite vector-binding compiler warning so verification output stays easier to read.
- Updated MLX cache-limit setup to the current `Memory.cacheLimit` API, removing the deprecation warning from focused builds.
- Data-only renderer and importer contribution declarations, with Settings summaries and validation that keeps each contribution under its matching extension kind.
- Cached sidebar note previews by URL and modification date, so repeated hover previews avoid rereading and preprocessing note bodies.
- Remote Intelligence runner API keys can be entered in the HUD and stored in Keychain; manifests and defaults keep only non-secret profile metadata/URL markers.
- DemoNotes home now includes a checklist-style tour that exercises highlights, bookmarks, zoom, trails, chat, Intelligence preflight, extensions, and search.

This is intentionally data-only. Cribble validates and displays extension intent, but does not execute arbitrary extension code yet.

### Demo and onboarding

DemoNotes now include `Extensions and Remote Intelligence.md`, linked from the welcome note. It teaches:

- the extension manifest shape,
- project-local extension folders,
- trusted remote intelligence runners,
- and the intended extension lanes: quick actions, intelligence providers, renderers, and importers.
- copy-ready manifest patterns for quick actions, remote runners, renderer aliases, and import lanes.

The first-run demo now points users toward the product's broader future without hiding the current safety boundary.

### Mac-native keyboard behavior

Global single-letter app shortcuts were replaced with Mac-style modified shortcuts:

- `Command O`: open folder
- `Command R`: refresh
- `Command Option E`: open in editor
- `Command Option O`: outline
- `Command Shift F`: focus mode
- `Command Option L`: AI Link Notes
- `Command Option I`: Project Intelligence
- `Command J`: Cribble AI chat
- `Command Left/Right`: back/forward

Reader-only quick keys (`H`, `B`, `P`, `Esc`) remain handled by the reader context, so typing in search, chat, and sheets is less surprising.

## Product signal

The highest-signal direction is: **Cribble as a calm native reader that can grow into a trustworthy knowledge workbench.**

The branch strengthens that story in three ways:

- beginners get clearer demos and safer defaults,
- power users see an extension path,
- advanced users can imagine trusted remote intelligence without losing the local-first posture.

## Validation

Ran:

```sh
swift test --filter ExtensionManifestTests
```

Latest pass:

- `swift test --filter Extension`
- 17 tests passed across manifest, registry, and runner credential suites.
- Latest runs built without the previous SQLite vector-binding or MLX cache-limit warnings.

## Next best sections

1. Incrementalize file-change refresh so edits do not trigger full rescans and reindexing.
2. Consider a dedicated Extensions developer guide outside DemoNotes for longer examples.
3. Add a full-app validation pass beyond focused extension/credential tests.
4. Continue reducing warning noise from broader full-suite builds as new dependency APIs shift.

Note: a first attempt to pass FSEvent changed paths into the store hit a Swift 6.3 compiler crash in sendability analysis, so that risky path was not kept. The committed performance work stays on a stable preview-cache path.
