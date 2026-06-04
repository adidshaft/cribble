# Cribble Intelligence — Experimental Preview

**Version:** `1.3.0-intelligence-preview`  
**Tag:** `v1.3.0-intelligence-preview`  
**Branch:** `cribble-intelligence`  
**Build:** Apple Silicon (arm64) only · Developer ID signed · Manual download (not delivered via Sparkle auto-update)

---

Project Intelligence turns Cribble into a local, private "second brain" for your code and notes. It runs quietly in the background while you work — summarizing files, mapping dependencies, tracking architecture drift, explaining commits, detecting fallback logic and I/O behavior, and building an Obsidian-style connections graph across your Markdown vault. No cloud, no subscriptions, no data leaving your machine. Everything is computed on-device using your choice of local MLX model or any OpenAI-compatible runner, stored in a per-project SQLite database, and surfaced through a dedicated HUD panel.

This is an **experimental preview**. It works, the guardrails are solid, and 18+ hours of continuous uptime back that up — but rough edges remain. Read the notes below before diving in.

---

## ✨ What's new / Highlights

### Project Intelligence engine

- **File summaries & project index** — every code and Markdown file is summarized at idle; an aggregate project-level index is kept up to date as files change.
- **Architecture & dependency diagrams** — static import/uses graphs rendered as interactive Mermaid diagrams. Click any node to reveal the source file in Finder.
- **Obsidian-style connections graph** — model-free `[[wiki link]]` graph for Markdown projects; same clickable node UX.
- **Diff & commit explanations** — concise natural-language summaries of recent diffs and git commits, fed by `git log` and per-file diffs.
- **Drift detection** — compares the static dependency graph against the stored architecture diagram and surfaces discrepancies (missing-in-code / missing-in-diagram) without requiring a model.
- **Fallback & I/O behavior audits** — per-file extraction of error-handling paths and external I/O patterns.
- **Semantic "Ask about this project"** — vector-search bar in the HUD backed by Apple NL embeddings; keyword fallback when embeddings aren't ready.
- **Per-folder and all-folders scope** — run intelligence against the active project or span every open library folder at once.
- **Model picker** — choose between on-device MLX models (Gemma 4 Flash, Gemma 4 Balanced, Qwen 3.5 4B, Gemma 4 12B) or any OpenAI-compatible local runner (Ollama, llama.cpp, LM Studio). Download progress is shown inline.
- **Chat HUD integration** — the existing Chat HUD automatically receives the current project's intelligence context, so chat responses are grounded in your actual codebase.

### On-device model support

| Model | Notes |
|---|---|
| Gemma 4 Flash | Fast; lighter summaries |
| Gemma 4 Balanced | Good quality/speed balance |
| Qwen 3.5 4B | Efficient; solid for code |
| **Gemma 4 12B** (new) | Best quality; requires ~24 GB RAM |
| Claude CLI / Codex CLI | Requires separate install |
| Any OpenAI-compatible runner | Ollama, llama.cpp, LM Studio |

**Deterministic features — dependency map, connections graph, drift detection — work with no model at all.** You get value from the moment you open a folder.

### UX & correctness fixes in this branch

- Floating panel controls respond on first click even when Cribble is not the key window (`acceptsFirstMouse`).
- Scope and model pickers are key-window-robust (inline controls, no `NSPopUpButton` dependency).
- Opening a folder via "Open Project Intelligence" now also switches the active project.
- Fixed a recurring SIGTRAP crash from the memory-pressure handler under Swift 6 actor isolation.
- Fixed queue starvation so deterministic jobs drain even when no model is configured.
- Fixed Mermaid clickable nodes resolving against the wrong project root.

---

## 🧠 How to try it

1. Open a folder in Cribble as usual.
2. Press **⌘⇧I** (or AI menu → Project Intelligence, or the brain indicator in the sidebar).
3. The Intelligence HUD opens. If no model is configured, the picker prompts you to download one or point at a local runner.
4. Status transitions: **scanning → working → idle**. Deterministic artifacts (dependency map, connections graph) appear first; model-backed summaries follow at idle as jobs drain.
5. Click any diagram node to reveal the source file in Finder.
6. Use the **Ask** bar for natural-language questions scoped to the current project (or all folders).
7. When you're happy with an artifact, click **Save to folder** to publish it into `.cribble/intelligence/` via the standard diff-preview flow — generated artifacts stay virtual until you explicitly save them.

---

## 🔒 Privacy

Everything is on-device and local. Intelligence jobs run against your local model or local runner. No file content, no summaries, no embeddings, and no queries are transmitted to any external server. The SQLite database and all artifacts live on your machine under `.cribble/intelligence/` (published) or in a sandboxed cache (virtual).

---

## ⚠️ Experimental — read this

**Apple Silicon only.** This build is `arm64`; it will not run on Intel Macs.

**Not notarized.** The app is Developer ID signed but has not been submitted for Apple notarization. On first launch, macOS will show: *"Apple cannot check it for malicious software."* To open it:

> **Option A (recommended):** Right-click `Cribble.app` in the mounted DMG → **Open** → confirm in the dialog.  
> **Option B:** After a blocked launch attempt, go to **System Settings → Privacy & Security**, scroll to the bottom, and click **"Open Anyway"** next to the Cribble entry.

A SHA-256 checksum file (`Cribble-1.3.0-intelligence-preview.dmg.sha256`) is provided alongside the DMG so you can verify the download before opening.

**First indexing takes time on large repos.** The scheduler runs one model job at a time, only when the machine is idle, unplugged power is not draining the battery, and thermal/memory pressure is low. On a large project (hundreds of files) the first full pass can take hours of accumulated idle time — this is by design, not a hang. Deterministic artifacts appear immediately; model summaries fill in progressively.

**Not delivered via auto-update.** This build is not pushed to the Sparkle feed. Download the DMG manually from GitHub Releases. When the feature stabilizes it will land in a normal release.

**Rough edges.** This is a preview. Expect occasional thin summaries from smaller models, incomplete aggregates on the first pass (the project index synthesizes from whatever summaries exist at the time it runs), and UI details that will be refined before stable release.

---

## 🐞 Known limitations

- **Per-file model fan-out is heavy on large repos.** Each code file currently enqueues three separate model jobs (summary + fallback audit + I/O audit). On a 1,000+ file repo, first indexing involves thousands of serialized model calls. This is the single biggest throughput issue and is the top priority for the next iteration. Combining these into a single structured prompt per file is planned.
- **Small models produce thinner summaries.** Gemma 4 Flash and Qwen 3.5 4B are fast but give shallower per-file summaries and are more likely to drift from the requested output format. Gemma 4 12B produces noticeably better results if your machine has the RAM.
- **Large files are truncated.** Files over ~12,000 characters are summarized from the first 12K only; the tail is not visible to the summary. Map-reduce chunking for large files is planned.
- **Aggregate jobs can run on a partial index.** On the first pass, the project index and architecture diagram may be generated before all file summaries are complete. They regenerate when the combined file-hash changes, but not solely when more summaries arrive. This will be addressed by gating aggregates on summary coverage.

---

*Built from the `cribble-intelligence` branch · 25 commits ahead of `main`*
