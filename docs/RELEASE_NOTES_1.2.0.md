# Cribble 1.2.0 — Local Chat HUD

**Your notes, now with a private AI that never leaves your Mac.**

Cribble 1.2.0 adds a floating **Local Chat HUD** — an on-device AI assistant
powered by Apple MLX. Ask questions about your notes, tag files with `@`, and get
safe, reviewable edits. Everything runs locally: no cloud, no account, no data
ever leaves your machine.

## What's new

- **On-device AI chat.** A resizable, always-on-top chat panel backed by a local
  MLX model. Open it from the toolbar (**Cribble AI**) or press **C**.
- **`@`-tag your notes.** Type `@` to pin Markdown files as context so the model
  answers about *your* knowledge base, not the open internet.
- **Safe, reviewable edits.** When the AI proposes changes, they appear as a
  unified diff (or a new-note preview) you approve before anything is written.
  The assistant never edits files silently.
- **Choose your model.** Pick from on-device models tuned for speed or reasoning:
  - **Gemma 4** (balanced, default)
  - **Gemma 4 Flash** (fastest, lightest)
  - **Qwen 3.5 4B** (strongest reasoning)
  Models download on demand the first time you use them.
- **100% private & offline.** Inference runs on the Apple Silicon GPU via Metal.

## Availability

- **Mac App Store:** the app is a paid download; the Local AI chat unlocks with a
  one-time **$6.99** in-app purchase.
- **Direct download (DMG):** the Local AI chat is **included and unlocked**.

## Requirements

- macOS 15 or later, Apple Silicon (M-series) Mac.
- ~1.2–2.9 GB free disk for the chosen model (downloaded once, on first use).

---

_Existing features — reading, wiki-linking, outlines, reading trails, AI Link
Notes — are unchanged._
