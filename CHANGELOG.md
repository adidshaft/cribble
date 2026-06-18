# Changelog

All notable changes to Cribble are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and Cribble aims to follow
[Semantic Versioning](https://semver.org/) (see the versioning guidance in
[MAINTAINER_HANDBOOK.md](MAINTAINER_HANDBOOK.md#release-model)).

## Unreleased

### Connected Reading
- Added the local backlink index foundation for Linked Mentions, including
  source-range-aware wiki-link parsing and code-aware link exclusion.
- Surfaced Linked Mentions in the reader as a calm collapsible section with
  source-note navigation and hover previews.
- Improved Linked Mentions snippets with nearest-heading context and
  VoiceOver-friendly row labels.
- Added parser support for Obsidian-style callout blocks so styled native
  callouts can land cleanly in the render pass.
- Rendered callouts as native material cards with semantic SF Symbols and
  nested Markdown body rendering.
- Added foldable callout behavior for `[!type]+` / `[!type]-`, including
  Reduce Motion-aware toggles and expanded/collapsed accessibility labels.
- Added the Transclusion parser foundation for Obsidian-style `![[note]]`,
  `![[note#heading]]`, and `![[note^block]]` embeds.
- Added read-only embed resolution for whole-note, heading, and block slices
  with bounded cycle/depth guards.
- Rendered resolved embeds as calm native inset cards with a source chip and
  recursive rich Markdown body rendering.
- Added bounded embed-resolution caching and clearer accessibility labels for
  resolved, unresolved, cyclic, and depth-limited embed states.
- Added the pure fuzzy-match scoring foundation for quick switcher and command
  palette ranking.
- Added a native Quick Switcher overlay on `⌘O` for fuzzy note navigation with
  recent notes first.
- Added a native Command Palette overlay on `⌘P` for fuzzy command discovery
  with visible shortcuts and existing command actions.
- Improved palette focus handling so Quick Switcher and Command Palette support
  arrow-key row movement, Return activation, and Esc/outside-click dismissal.
- Added a read-only tag index that unifies frontmatter and inline tags,
  including nested tag lookup and code/heading exclusion.
- Rendered inline tags in the reader as clickable chips that apply the local
  tag filter without writing notes.
- Added a compact sidebar Tags pane with counts, selected-tag filtering, and a
  clear filter control.
- Added a stored-vector related-notes query that ranks indexed notes by local
  cosine similarity while excluding the current note and near-duplicates.
- Surfaced Related Notes in the reader as a lazy, debounced, collapsible local
  semantic section with hover previews and subtle similarity bars.

## 1.4.0 — Night Shift

Cribble 1.4.0 is the "Night Shift" release: a smoother, safer, more
Mac-native workspace for beginners, daily note work, local-first AI, trusted
remote intelligence, and the first serious extension/plugin contribution path.

### Performance
- **Lower memory on big vaults** — Cribble no longer keeps every note's full
  text in memory; bodies load on demand, so large libraries stay light.
- **Adaptive performance modes** — Light / Balanced / Power, auto-selected from
  your Mac's memory and core count and adjustable in the intelligence model
  menu. Light keeps background analysis idle until you ask for it.
- **Cleaner large-folder scans** — generated dependency and tool-cache folders
  are skipped more aggressively, so broad project folders stay quieter.

### Safety
- **Recoverable edits** — every change Cribble makes to a note (AI diffs, task
  exports, checkbox toggles, new notes) is now backed up first, can't silently
  overwrite an existing file, and never hard-deletes. A new **File → Undo Last
  Note Change** (⇧⌘Z) reverts the open note to its previous version.
- **Review-first AI stays explicit** — empty AI diff previews now explain that
  no safe patch was received and that nothing has been written.
- **Trusted remote intelligence** — local, VPS, and team OpenAI-compatible
  runners now have clearer consent, Keychain-secret, diagnostics, and copied
  review handoffs before note context leaves the Mac.
- **Extension guardrails** — extension contribution docs and in-app guidance now
  require read-only first versions, least access, least writing, clean disable
  behavior, and native SwiftUI/system-control surfaces.

### Quality of life
- **Reopens where you left off** — launching restores the note you were last
  reading instead of jumping to the first file.
- **Better first-run recovery** — DemoNotes, Help, welcome cards, and starter
  checklists now guide users into tasks, research review, decisions, Project
  Intelligence, remote runners, and extension contribution.
- **Zero-file handoffs** — copy README starters, reading trail starters and
  summaries, search-miss handoffs, missing slash-command ideas, diagnostics,
  task snippets, diffs, and review templates before creating or changing notes.
- **Import-lane setup guidance** — failed import attempts now point to native
  setup and Settings review routes instead of stopping at terse errors.
- **Open-source extension guide** — a bundled and documented contribution path
  helps people propose useful plugins/extensions while API v1 remains
  declarative and safe.

## 1.3.1 — Generic intelligence & tasks (experimental)

> ⚠️ **Experimental build.** New on-device intelligence lenses, task export, and
> image handling. Feedback welcome before this is promoted to a stable release.

### New
- **More images render** — Obsidian-style `![[embeds]]`, raw HTML `<img>` tags,
  and images kept in `attachments/`, `assets/`, or `images/` folders now display
  in the reader instead of showing as broken text.
- **Choose how Cribble AI runs** — a first-run chooser lets you pick on-device
  (private, local-first) or a cloud CLI. On-device is now the default when your
  build supports it, and your choice is remembered.
- **Intelligence for any kind of work** — new generic, on-device insights that
  serve notes, research, contracts, and case files (not just code): a
  **Contradiction Report**, a **Glossary** of recurring terms, and a **Timeline**
  of dated events. Code-only diagrams are skipped automatically in prose vaults.
- **Send tasks anywhere** — hover a checkbox to add it to Reminders, Calendar, or
  Cribble's own **Tasks.md**, which collects everything you flag with a backlink
  to the exact source line. A sidebar Tasks button opens that living index.
- **Block-reference links** — `[[Note#^anchor]]` links (including the backlinks in
  Tasks.md) now scroll to the linked line's section, not just the top of the note.
- **Project Pulse** — a glanceable health + progress card in the Intelligence HUD.

### Privacy
- Remote `http(s)` images are shown as click-to-open links by default rather than
  loaded automatically (no IP leak). A "Load remote images" setting re-enables
  inline loading.

## 1.2.1 — Smarter, more connected Cribble AI

Builds on 1.2.0 with deeper note awareness, faster actions, and important
reliability fixes.

### New
- **Vault-aware answers** — the chat automatically pulls in the most relevant
  notes from your workspace (via the on-device semantic index), so it can answer
  about your whole library, not just the open or tagged note.
- **Quick actions & slash commands** — one-tap chips (Summarize, Find related,
  Suggest links, Create index, Explain simply) and a `/` command palette.
- **Message actions** — Copy, **Save as new note**, and **Insert into current
  note** (appended via the safe diff preview) on every answer.
- **Attach anything** — the `+` button can **Choose File…** from Finder to use a
  file as context (even files outside the workspace), plus **Attach All Notes**.
  The `@` search is now folder-aware (type `folder/file`).

### 🐞 Fixes
- **Claude / Codex now load reliably** — the CLIs run through your login shell,
  so they inherit Terminal's PATH and signed-in session.
- **Attached files now stay authoritative** — when you scope a chat with `@` or
  `+` attachments, Cribble no longer lets the open reader note or related-note
  search distract the answer.
- **Chat HUD reliability tightened** — stalled generations now recover cleanly,
  Stop escalates stuck CLI processes, and large "Attach All Notes" prompts stay
  inside a total context budget.
- **Download progress no longer appears stuck at 0%** — shows honest progress
  for large single-file models.
- **Local model sizes are labeled accurately** — Gemma downloads now show their
  real multi-GB footprint before you start them.
- Compact model chip and a tidier input bar.

---

## 1.2.0 — Cribble AI (on-device assistant)

The headline of 1.2.0 is **Cribble AI**: a private AI assistant that runs fully
on your Mac. Ask questions about the note you're reading, tag notes with `@`,
auto-link them, synthesize new notes, and explain how two notes connect — all
with safe, reviewable previews and nothing ever leaving your machine.

### New

- **Local Chat HUD (Cribble AI).** A floating, resizable chat backed by an
  on-device Apple MLX model. Open it with **C**, the menu-bar icon, or the
  toolbar. It does four things:
  1. **Reading Q&A** — answers about the note you're reading (auto-included as
     context) or files you tag.
  2. **Auto-Link** — proposes `[[Wiki Links]]` as a safe unified-diff preview.
  3. **Synthesis** — generates an index/overview as a new note (preview first).
  4. **Pathfinder explanations** — one-paragraph "conceptual bridge" between two
     notes, now runnable on-device.
- **Model picker** with download-state icons (download / downloaded / cloud).
  On-device models (Gemma 4, Qwen 3.5) download once; **Cloud** models (Claude,
  Codex) use the sessions already logged in to your Terminal.
- **Menu-bar mode.** Tuck the chat into the menu bar (**^**) and pop it back to a
  window (**v**), or type directly from the menu-bar popover.
- **`@`-tagging** to attach specific notes as context.
- **In-app purchase unlock** for the Local AI on the Mac App Store build; the
  direct DMG download includes it unlocked.

### 🔧 Improvements

- **Smaller windows.** The main window now shrinks much further; below a
  threshold the sidebar collapses and can be summoned as an overlay without
  resizing the window.
- **Cleaner menu bar.** Consolidated from ~12 top-level menus to ~7 and removed a
  duplicate "View" menu — no lost functionality.
- **Refreshed demo library** — fewer, more interactive tutorial notes that now
  cover Cribble AI.
- The chat HUD floats above Cribble's window but steps aside for other apps
  (no longer a global always-on-top overlay).

### 🐞 Fixes

- Fixed a crash on first AI use caused by a retain-count bug in the bundle-path
  redirect (now compiled without ARC).

### Under the hood

- Integrated Apple **MLX** (`mlx-swift-lm` + `swift-huggingface` +
  `swift-transformers`), isolated behind a protocol so the rest of the app is
  unaffected.
- Added `script/build_metallib.sh` to compile and cache MLX's Metal shader
  library (`Vendor/MLXMetallib/`), which the packaging scripts bundle — MLX
  can't build its shaders from a plain `swift build`.

---

## Upgrading from 1.1.3

- **Direct download (DMG):** download `Cribble-1.2.0.dmg` from the release and
  drag Cribble to Applications (replacing the old copy). Local AI is included and
  unlocked.
- **Mac App Store:** update as usual; unlock Local AI with the one-time in-app
  purchase.
- **Requirements:** macOS 15+ and an Apple Silicon (M-series) Mac for on-device
  models. Cloud models (Claude/Codex) require their CLI installed and signed in.
- **First AI use:** pick a model in the chat; on-device models download once
  (~2.9–4.9 GB). Tap the ↓ next to a model to download it ahead of time.
- Your notes, highlights, bookmarks, and settings are unchanged.

---

## 1.1.3 and earlier

See the [GitHub releases](https://github.com/adidshaft/cribble/releases) for
prior versions (reading trails, semantic search, Pathfinder, folder pinning,
custom fonts, and the core Markdown reader).
