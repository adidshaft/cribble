# Cribble Intelligence — Performance Audit

| Field        | Value                                            |
|--------------|--------------------------------------------------|
| Scope        | The intelligence layer on branch `cribble-intelligence` |
| Date         | 2026-06-05                                        |
| Method       | Static review of the engine + UI code, plus live observation of the running app (DemoNotes, zook = 1426 files, all-folders ≈ 1470 files) |

This audit covers two axes: **software/runtime performance** (memory, I/O, concurrency,
storage, UI) and **LLM-usage performance** (how the model's time/tokens are spent and how
well the small on-device models are used). Findings are tagged **[High] / [Med] / [Low]**
by impact, each with a concrete recommendation. Severity reflects worst-case (large repos /
all-folders), not the DemoNotes happy path.

---

## 1. Software / runtime performance

### Observed baselines
- **Process RSS:** ~1.9 GB while a Gemma model is loaded for intelligence/chat (MLX weights
  dominate). Idle-with-no-model is far lower.
- **`SemanticIndex.json`:** ~25 MB on disk (pre-existing reader feature, loaded at launch).
- **Stability:** 18 h+ continuous uptime, zero crashes after the memory-pressure fix.
- **Scheduling:** one SLM job at a time; loop ticks every 30 s; each tick drains ≤ 6 jobs;
  scans are FSEvents-driven (not polled), so steady-state idle cost is ~0.

### Findings

**1.1 [High] Per-file model fan-out is the dominant cost.**
Each code file enqueues **three** model jobs — `summarizeFile` + `extractFallbackLogic` +
`extractIOBehavior` (`WorkspaceScanner.scan`), plus aggregate jobs. On a 1426-file repo that
is potentially **thousands of model calls**, serialized one at a time at idle. Quality is fine;
*throughput* is the issue — a full first pass on a large repo can take hours of idle time.
- **Recommend:** (a) make fallback/IO audits **opt-in or on-demand** per file rather than
  auto-enqueued for every code file; (b) prioritize recently-edited files; (c) consider a
  single combined "summary + fallbacks + IO" prompt per file (1 call instead of 3) for small
  files. This is the single biggest win.

**1.2 [Med] Brute-force vector search loads all embeddings per query.**
`SQLiteVectorIndex.search` calls `db.embeddings(projectID:)`, which materializes **every**
stored vector into memory and computes cosine in Swift on each "Ask" (`O(n·d)`). Fine at
hundreds–low-thousands; a memory + latency spike at tens of thousands (all-folders over big
vaults).
- **Recommend:** cap candidates (e.g. only `fileSummary`/`projectIndex` vectors), or move to
  the `sqlite-vec` extension behind the existing `VectorIndex` protocol when counts grow.

**1.3 [Med] One WKWebView per Mermaid block, plus a headless validator WebView.**
Each diagram artifact renders in its own `WKWebView` (`MermaidDiagramWeb`), and
`MermaidRenderValidator` keeps another. WebViews are memory-heavy (tens of MB each); several
open diagrams add up.
- **Recommend:** the artifact reader shows one artifact at a time, so this is bounded today;
  if multiple diagrams ever render at once, pool/reuse a single WebView. The validator is a
  singleton (good).

**1.4 [Med] All-folders enable hashes every file across every root, up front.**
`enableAllFolders` scans all opened roots; the first scan reads + FNV-hashes every eligible
file (≤ 512 KB each). For large multi-vault setups that's a noticeable one-time burst (then
cheap, since re-scans are FSEvents-gated). `node_modules`/`.git`/`build` etc. are already
skipped.
- **Recommend:** store the file's mtime+size and skip re-hashing unchanged files (a v3
  migration) to make re-scans after partial changes cheaper still; show scan progress.

**1.5 [Low] `@Published artifacts` re-renders the whole tree on every refresh.**
`refreshState()` reassigns the full `artifacts` array each tick; SwiftUI re-diffs the sidebar
list. Fine for hundreds; could stutter with thousands of file summaries.
- **Recommend:** diff/merge in place, or paginate the FILES section.

**1.6 [Low] `recoverIfPoisoned` reads up to 60 artifact files on every enable.**
Acceptable (bounded to 60), but it's disk I/O on the enable path.
- **Recommend:** sample fewer (e.g. 20) or check a stored "provider was healthy" flag instead.

**1.7 [Good, keep] Safety gating is solid.**
Single concurrent SLM job, idle/thermal/battery/**memory-pressure** gating, 6-job drain cap,
500 MB LRU disk budget, RAM-gated model loading, bounded prompt inputs. These are the right
guardrails and are why the app is stable under load.

---

## 2. LLM-usage performance

### How model time/tokens are spent
- **Inputs bounded:** ≤ 12 K chars per file (`maxInputChars`); diff ≤ 12 K.
- **Output budgets:** file summary 512 tok, fallback/IO audit 512, diff 768, commit 512,
  project index 1200, architecture 1200. Reasonable; no runaway generations.
- **Prompts:** centralized in `Prompts.swift`, format-locked, every one carries an explicit
  anti-hallucination instruction. Output is validated (path cross-ref + Mermaid structural +
  headless render) and **error-shaped output is rejected**, not stored.
- **Retrieval:** "Ask" uses semantic vector search (Apple `NLContextualEmbedding`) with a
  keyword fallback; embeddings are computed once per artifact and persisted.

### Findings

**2.1 [High] 3 model calls per code file (mirror of 1.1, from the LLM side).**
The per-file fan-out triples token spend and wall-clock per file. For local models this is
the difference between "indexed in minutes" and "indexed in hours."
- **Recommend:** combine into one structured prompt per file where feasible; reserve separate
  audit passes for explicit user request or changed files only.

**2.2 [Med] No structured-output enforcement on the on-device path.**
MLX/CLI providers get prompt-only shaping (the schema example is appended to the system
prompt); only `OpenAICompatibleProvider` can use `response_format`. Small models (e.g. Gemma
2B "Flash") sometimes drift from the requested Markdown/Mermaid shape; validation catches
gross errors but costs a retry.
- **Recommend:** prefer runners that support `response_format` for diagram/JSON jobs; or add a
  lightweight post-parse repair before retrying.

**2.3 [Med] Large files are truncated, not map-reduced.**
Files > 12 K chars are summarized from the first 12 K only. A long file's tail is invisible to
the summary.
- **Recommend:** for large files, chunk + summarize-the-summaries (map-reduce) so the whole
  file is represented. Keep the 12 K cap per chunk.

**2.4 [Med] Model choice drives quality *and* speed; defaults favor speed.**
The default prefers any already-downloaded local model. Gemma 2B "Flash" is fast but produces
thin summaries; the new **Gemma 4 12B** is markedly better but slower and needs ~24 GB. The
model picker now exposes the trade-off.
- **Recommend:** surface a one-line hint per model ("Flash: quick, lighter summaries" /
  "12B: best quality, slower, high-memory") in the picker; consider auto-selecting a heavier
  model only when idle + plugged + enough RAM.

**2.5 [Low] Aggregate jobs can run before all file summaries exist.**
`updateProjectIndex` / `buildArchitectureDiagram` synthesize from whatever summaries are
present; on a slow first pass they may run against a partial set (they regenerate when the
combined file-hash changes, but not when more summaries merely complete).
- **Recommend:** gate aggregates on "summary coverage ≥ X%," or re-enqueue them once the
  summary queue drains.

**2.6 [Good, keep] Deterministic-first design.**
Dependency map, connections graph, and drift detection are **model-free** and run even with no
model downloaded — users get value immediately, and the static graph grounds the model's
narration (anti-hallucination). Embeddings use the cheap on-device Apple NL path. This is the
right architecture.

---

## 3. Prioritized recommendations

| # | Change | Impact | Effort |
|---|--------|--------|--------|
| 1 | Stop auto-enqueuing fallback + IO audits for every code file; make them on-demand / changed-files-only (1.1, 2.1) | **High** — cuts model work ~3× on large repos | Low |
| 2 | Combine per-file summary+fallback+IO into one prompt for small files (2.1) | High | Med |
| 3 | Cap/scope vector candidates; move to `sqlite-vec` at scale (1.2) | Med | Med |
| 4 | mtime+size skip in the scanner to avoid re-hashing unchanged files (1.4) | Med | Med |
| 5 | Map-reduce summaries for large files (2.3) | Med | Med |
| 6 | Prefer `response_format` runners for structured jobs (2.2) | Med | Low |
| 7 | Gate aggregate jobs on summary coverage (2.5) | Low | Low |
| 8 | In-place artifact diffing for the tree at thousands of artifacts (1.5) | Low | Med |

**Bottom line:** the architecture is sound and the safety guardrails are strong — the app
stays responsive and stable under load. The one change that matters most is **reducing the
per-file model fan-out** (recommendations 1–2); everything else is incremental. Nothing here
is a correctness risk; these are throughput/scale optimizations for large projects and the
all-folders scope.
