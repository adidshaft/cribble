# Changelog

All notable changes to Cribble are documented here.

## 1.2.1 — Smarter, more connected Cribble AI

Builds on 1.2.0 with deeper note awareness, faster actions, and important
reliability fixes.

### ✨ New
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

### ✨ New

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
