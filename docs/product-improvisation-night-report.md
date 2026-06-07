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

This is intentionally data-only. Cribble validates and displays extension intent, but does not execute arbitrary extension code yet.

### Demo and onboarding

DemoNotes now include `Extensions and Remote Intelligence.md`, linked from the welcome note. It teaches:

- the extension manifest shape,
- project-local extension folders,
- trusted remote intelligence runners,
- and the intended extension lanes: quick actions, intelligence providers, renderers, and importers.

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

Latest pass: 9 tests passed.

## Next best sections

1. Improve first-launch empty state with “Continue Demo Tour” and “Reset Demo Library.”
2. Incrementalize file-change refresh so edits do not trigger full rescans and reindexing.
3. Add registry scan tests with duplicate precedence and enable/disable persistence coverage.
4. Add secure credential handling for remote runner profiles without storing secrets in manifests.
5. Bring the same preflight confirmation to the sidebar brain quick-toggle.
