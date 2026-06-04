# Cribble Intelligence — Branch Summary (`cribble-intelligence`)

> Generated from git history and source review. Factual only — nothing invented.
> Base: `main`. Branch head: `314b1a9`.

---

## Overview

The `cribble-intelligence` branch adds a complete, local, on-device **project intelligence layer** to Cribble. Rather than a single monolithic "understand the repo" pass, the system runs many small, bounded, resumable background jobs that continuously produce reviewable project knowledge: Markdown file summaries, project indexes, diff and commit explanations, Mermaid dependency and architecture diagrams, architecture-drift reports, fallback and I/O behavior audits, an Obsidian-style note connections graph, and a semantic vector index for scoped natural-language queries. All heavy work runs on a thermal/idle/battery-aware scheduler with no cloud dependency; results are stored in a per-project SQLite database and surfaced through a dedicated Intelligence HUD panel. Generated artifacts remain virtual until the user publishes them to `.cribble/intelligence/` via the existing diff-preview flow. The Chat HUD is enriched with intelligence context automatically.

---

## Commits (chronological, oldest first)

**Foundation — engine core**
- `75965e9` Add Cribble Intelligence engine foundation (Phase 1)
- `e94133b` Complete Intelligence engine: git, diagrams, drift, audits, coordinator

**UI layer**
- `072ba63` Add Intelligence HUD UI, sidebar indicator, and app wiring

**Chat integration**
- `9d68e19` Inject project intelligence into Chat HUD; self-contained cache ignore

**Plan tracking**
- `636d203` Track intelligence plan with implementation-status section

**Safety and correctness**
- `f4241ab` Intelligence safety barriers + fix cloud-auth artifact poisoning

**Build**
- `8c7aa93` Ignore dist-release build output

**Second-pass features (IO audits, vectors, Mermaid, seeding)**
- `b71dfa4` Complete remaining plan items: IO audits, vectors, seeding, mermaid

**Bug fixes — queue, project switching, diagram nodes**
- `2e2f09f` Fix queue starvation when no model + correct HUD project name
- `2f9df3f` (merged as `2e2f09f`) Fix: Open Project Intelligence switches the active project
- `9df4e66` Prepare open source contribution surfaces

**Open source scaffolding**
- `9df4e66` Prepare open source contribution surfaces (LICENSE, CONTRIBUTING, GOVERNANCE, SECURITY, ROADMAP, issue templates, CoC, PR template, website update)

**Diagram interactivity**
- `88457ff` Clicked diagram code node reveals in Finder (reader is Markdown-only)
- `b0e7d5e` Fix clickable diagram nodes resolving against wrong project root
- `d3e35c6` Clickable diagram nodes use JS callback + script handler, not URL nav
- `c7ee954` Update click-link test for callback form

**Connections graph + UX polish**
- `8b6f1f8` Intelligence UX: model picker, chat fix+toggles, connections graph, clearer publish

**Docs**
- `19ce2f7` Docs: real READMEs across tree, CI workflow, docs index, changelog convention

**Crash fix**
- `483cea6` Fix recurring SIGTRAP crash from memory-pressure handler isolation

**Scope + spinner + HUD polish**
- `4476f4e` All-folders scope, download spinner, HUD polish

**Panel / window robustness**
- `ea793a2` Make scope/model pickers key-window-robust (inline controls)
- `314b1a9` Fix floating-panel controls swallowing first click (acceptsFirstMouse)

---

## What Was Built

### Engine / Core (21 new Swift files under `Sources/Cribble/Services/Intelligence/`)

- **`IntelligenceDatabase.swift`** (774 lines) — SQLite actor: schema migrations, `files`, `symbols`, `jobs`, `artifacts`, `artifact_provenance`, `embeddings` tables. Hash-skip dedup, job retry/backoff, LRU disk-budget enforcement.
- **`IntelligenceModels.swift`** (207 lines) — All value types: `IntelligenceJobType` (15 types across 3 tiers), `IntelligenceJobTier`, `IntelligenceJobStatus`, `IntelligenceArtifact`, `ArtifactProvenance`, `SymbolRecord`, `ProviderAvailability`.
- **`IntelligenceEngine.swift`** (604 lines) — `@MainActor ObservableObject` coordinator: owns DB, scheduler, job runner, artifact store, provider; drives the idle scan→enqueue→drain loop; exposes `@Published` status (`off`, `ready`, `scanning`, `working`, `idle`, `driftDetected`), `pendingJobs`, `filesIndexed`, `staleCount`, `modelDownloadFraction`; enriches Chat HUD context; handles FSEvents-driven re-scan.
- **`JobRunner.swift`** (369 lines) — Swift `actor`: drains the queue one job at a time; houses all executors for all 3 tiers. Deterministic jobs (dependency diagram, drift detection) run without a model; model jobs are gated per-type.
- **`BackgroundScheduler.swift`** (111 lines) — Swift `actor`: reads user-idle seconds (`CGEventSource`, no accessibility permission), thermal state, battery status, app foreground, and OS memory pressure; returns the maximum `IntelligenceJobTier` currently permitted. Fully injectable for unit testing.
- **`WorkspaceScanner.swift`** (201 lines) — Tier-1 deterministic file walk; multi-root for "all folders" scope; FNV-1a content hashing via `ContentHasher`; language detection for Swift, Markdown, JS/TS, Python, Go, Rust, JSON, YAML, shell; enqueues follow-up jobs for changed files only.
- **`ContentHasher.swift`** (47 lines) — FNV-1a 64-bit hasher with deterministic `combine` for multi-input dedup keys.
- **`SwiftSymbolExtractor.swift`** (155 lines) — Regex-based Swift symbol parser: extracts types, functions, imports with line ranges and signatures; feeds the `symbols` table and static dependency graph.
- **`IntelligenceProvider.swift`** (120 lines) — `IntelligenceProvider` protocol (generate + embed); `LocalEngineIntelligenceProvider` wrapping the existing MLX/CLI engine.
- **`OpenAICompatibleProvider.swift`** (122 lines) — Single HTTP provider covering Ollama, llama.cpp, and LM Studio via the OpenAI-compatible `/chat/completions` + `/embeddings` endpoints.
- **`IntelligenceSettings.swift`** (91 lines) — `UserDefaults`-backed settings: enabled flag, model choice, scope, auto-publish toggle.
- **`ArtifactStore.swift`** (64 lines) — Bridges the DB and the filesystem for artifact reads/writes; translates virtual → published via the `UnifiedDiff` flow.
- **`DependencyGraph.swift`** (130 lines) — Builds a static import/uses graph from `SymbolRecord`s; renders to Mermaid; deterministic drift diff (`.missingInCode` / `.missingInDiagram`).
- **`NoteConnectionsGraph.swift`** (53 lines) — Obsidian-style `[[wiki link]]` graph for Markdown projects; model-free; reuses `DependencyGraph` so nodes are clickable.
- **`VectorIndex.swift`** (57 lines) — `VectorIndex` protocol + `SQLiteVectorIndex` brute-force cosine similarity over stored embeddings (no native extension, no external dependency); backs the semantic "Ask" bar.
- **`GitInspector.swift`** (75 lines) — Shell-out wrapper: recent commits, per-file diffs, blame stubs.
- **`OutputValidator.swift`** (103 lines) — Cross-references LLM output paths against the `files` table; validates Mermaid graph syntax (node count, edge count, balanced brackets).
- **`MermaidRenderValidator.swift`** (95 lines) — Headless `WKWebView` Mermaid parser using the bundled `mermaid.min.js`; 3-second timeout; best-effort (failures pass-through, never block the pipeline).
- **`Prompts.swift`** (107 lines) — All system and user prompt templates for every job type.
- **`DemoSeeder.swift`** (107 lines) — Seeds synthetic intelligence artifacts into a temp project for first-run onboarding without requiring a real model.

### Features (job executor matrix)

| Job type | Tier | Model required |
|---|---|---|
| `scanWorkspace`, `detectChangedFiles`, `parseCodeSymbols`, `extractImports` | 1 | No |
| `summarizeFile`, `summarizeDiff`, `summarizeCommit`, `extractFallbackLogic` | 2 | Yes |
| `extractIOBehavior`, `buildDependencyDiagram`, `buildConnectionsGraph`, `buildArchitectureDiagram`, `updateProjectIndex`, `detectArchitectureDrift` | 3 | Mixed |

- All-folders scope: scanner accepts multiple root URLs; engine populates `scanRoots` from all open library folders.
- On-device model download affordance with `modelDownloadFraction` progress published to the HUD.

### UI (3 new Swift files under `Sources/Cribble/Views/IntelligenceHUD/`, modifications to existing views)

- **`IntelligenceHUDView.swift`** (557 lines) — Full HUD panel: live artifact tree, model/scope picker overlay, status pill, "Run now"/"Clear cache" toolbar, enable prompt, Mermaid-embedded artifact reader, scoped "Ask" bar with semantic retrieval, artifact provenance footer. Triggered via `⌘⇧I`. Styled to match the Chat HUD.
- **`IntelligenceHUDController.swift`** (151 lines) — `NSPanel`-backed floating window controller; `acceptsFirstMouse` fix so controls respond on initial click without first activating the app.
- **`ArtifactBodyView.swift`** (148 lines) — Renders individual artifacts: Markdown via `StructuredText`, embedded Mermaid diagrams with JS-callback click-through to source files (opens in Finder for non-Markdown nodes).
- **`SidebarView.swift`** — Extended with an intelligence status indicator (dot + pending count) driven by `IntelligenceEngine.status`.
- **`ContentView.swift`** — Wired up `IntelligenceEngine` and the `⌘⇧I` command.
- **`ChatHUDView.swift` / `ChatHUDViewModel.swift`** — Extended to inject the current project's intelligence context into the chat prompt.

### Safety / Fixes

- Memory-pressure SIGTRAP crash: the `DispatchSource`-backed OS memory-pressure monitor was moved to a non-isolated helper to avoid Swift 6 actor-isolation violations on `deinit`.
- Queue starvation when no model: `JobRunner` now distinguishes model-required vs deterministic jobs and drains deterministic jobs even with `provider == nil`.
- Cloud-auth artifact poisoning: output from a cloud-auth provider is rejected before it can be stored as an intelligence artifact.
- Clickable Mermaid node navigation: nodes use a `WKScriptMessageHandler` JS callback (not URL navigation) so they work correctly in a `WKWebView` with a `file://` base URL and resolve against the actual project root.
- First-mouse panel controls: `IntelligenceHUDController` sets `acceptsFirstMouse` on the panel so toolbar buttons respond to the first click even when the panel is not the key window.
- Scope/model pickers made key-window-robust by inlining controls (avoiding `NSPopUpButton` which requires key-window status).
- "Open Project Intelligence" now also switches the active project to the selected folder.

### Docs and Open Source Scaffolding

- **`docs/cribble-intelligence-plan.md`** (776 lines) — Full technical design document: architecture diagram, glossary, all phases, implementation status, deferred items.
- **`docs/cribble-intelligence-research.md`** (505 lines) — Research and UX strategy doc: competitive analysis (CodeBoarding, Pieces, Cursor, etc.), "living second-brain" framing, honest take on bidirectional diagram→code editing, open-source strategy outline.
- **Per-directory READMEs** added to every folder in the source tree (`Sources/Cribble/Services/Intelligence/`, `Views/IntelligenceHUD/`, `Tests/CribbleTests/`, `docs/`, etc.).
- **`.github/workflows/ci.yml`** — Build + test CI workflow (Xcode on macOS).
- **Open source scaffolding** (`LICENSE` — Apache-2.0, `CONTRIBUTING.md`, `GOVERNANCE.md`, `SECURITY.md`, `ROADMAP.md`, `CODE_OF_CONDUCT.md`, `TRADEMARK.md`, `DISCUSSIONS.md`, `MAINTAINER_HANDBOOK.md`, `CHANGELOG.md`, issue templates for bug/feature/docs/provider, PR template, `website/index.html` update).

---

## Tests

**30 test functions** across 2 new files:

| File | Tests |
|---|---|
| `Tests/CribbleTests/IntelligenceEngineTests.swift` | 16 |
| `Tests/CribbleTests/IntelligenceJobsTests.swift` | 14 |

Coverage includes: `ContentHasher` determinism and sensitivity, `SwiftSymbolExtractor` (types, functions, imports, cross-file uses), `IntelligenceDatabase` CRUD (file upsert, job queue enqueue/claim/complete, artifact write/read), `DependencyGraph` edge building and Mermaid rendering, drift detection, `OutputValidator` path cross-reference and Mermaid syntax checks, `BackgroundScheduler` tier policy under all condition combinations (idle, battery, thermal, memory pressure), `NoteConnectionsGraph` wiki-link extraction, `VectorIndex` cosine similarity and ranking, and `JobRunner` executor integration (summarize-file, fallback-audit, project-index, dependency-diagram, clickable Mermaid node script injection). All tests use injected mocks (`MockIntelligenceProvider`, `StubProvider`, synthetic temp directories) — no real model or live database connection required.

---

## Deliberately Deferred Items

From `docs/cribble-intelligence-plan.md` implementation status:

1. **Visual-sync "edit diagram → mutate code"** — The research doc argues true round-tripping is a reliability trap; drift-detection + propose-diff is the implemented substitute.
2. **React Flow interactive canvas (Phase 3)** — Large web-app dependency with marginal value over the now-clickable Mermaid maps.
3. **SwiftSyntax / IndexStore parser** — ~50 MB binary cost for marginal parse precision over the regex extractor; revisit if symbol accuracy becomes a real issue.
4. **`sqlite-vec` native extension** — The dependency-free brute-force `SQLiteVectorIndex` is sufficient at local project scale; the protocol makes a future swap transparent.
