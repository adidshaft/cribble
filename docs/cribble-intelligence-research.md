# Cribble Intelligence — Research, UX Direction & Open-Source Plan

| Field        | Value                                                  |
|--------------|--------------------------------------------------------|
| Status       | Research / strategy companion to `cribble-intelligence-plan.md` |
| Version      | 0.1                                                    |
| Last Updated | 2026-06-03                                             |
| Scope        | Competitive OSS landscape · net UX · idle second-brain · macOS-native · long-term open-source strategy |

> This document does **not** replace the technical design (`cribble-intelligence-plan.md`).
> It sits in front of it: it pressure-tests *what we should build and why*, grounded in
> what already exists in the open-source world, and reframes the build around the
> user's actual job-to-be-done before we commit engineering to it.

---

## 0. The real problem (restated in the user's words)

Strip the feature talk away and the request is one sentence:

> *"Most of my code now comes from prompting, so I've lost the mental model of what it
> does — the logic, the fallbacks, the design decisions. I want a living, visual,
> end-to-end representation of the codebase that the code actually follows, and I want
> to keep ownership of it."*

Three sub-needs fall out of that:

1. **Transparency / recall** — "What did the AI actually build here, and why?" Today the
   user re-asks Claude to explain logic it already wrote. That knowledge is generated,
   used once, and thrown away. **The core feature is making that explanation persistent,
   provenance-linked, and always up to date.**
2. **Visibility / structure** — an SDLC-style top-down picture (requirements → architecture
   → component/UML → code) that stays *true* as code changes.
3. **Bidirectional control (aspirational)** — "edit the diagram, the code follows."

The single most important framing decision in this whole effort:

> **#1 is the product. #2 is the surface. #3 is a trap.**

Diagrams are how we *show* understanding, but the durable value is the continuously
maintained, source-cited explanation of a codebase that one human increasingly did not
hand-write. Lead with that. Sections 1–4 justify this; Section 8 is the honest take on #3.

---

## 1. Does anything already solve this? (Direct competitors)

Short answer: **the codebase-diagram half is largely solved; the "living, native,
second-brain, you-own-it" half is not.** Build the second, borrow the first.

### 1.1 CodeBoarding — the closest thing to "directly solves it"

[CodeBoarding](https://github.com/CodeBoarding/CodeBoarding) is the most important
project to study because it is doing *exactly* the pipeline our plan proposes, and doing
it well enough that we should not reinvent its core.

- **What it does:** combines **static analysis (control-flow / call graph as ground truth)**
  with **LLM reasoning** to produce architecture diagrams + component-level Markdown docs.
  Output is **Mermaid**, stored in a `.codeboarding/` folder — almost identical to our
  proposed `.cribble/intelligence/`.
- **Incremental & CI:** it has an "Incremental Analysis Engine" (re-analyze on change) and a
  GitHub Action that keeps diagrams fresh in CI. This validates our hash-based incremental
  approach (`plan §7.3`).
- **Local-capable:** **Ollama is a first-class provider**, so it can run fully offline. Also
  supports OpenAI/Anthropic/Bedrock/OpenRouter.
- **Languages:** Python, TS/JS, Java, Go, PHP, Rust, C#. (Node runtime auto-downloaded for the
  JS/TS/PHP analyzers.)
- **Surfaces:** CLI, VS Code extension (in-editor diagrams), and a web explorer
  (`codeboarding.org/diagrams`).

**The single most valuable lesson from CodeBoarding — adopt it verbatim:**

> The LLM never invents structure. The **static-analysis graph is the source of truth, and
> the LLM's narrative is *validated against* that graph.** This is the antidote to the #1
> risk of SLM-on-code: hallucinated files, functions, and edges.

Our plan's §11.2 (regex symbol extraction) and §7.4 (cross-check paths against the `files`
table) are the same instinct but **weaker**. A regex parser can't produce a real call graph,
so an SLM "architecture diagram" built only on file summaries will be plausible fiction.
**Recommendation:** treat a real symbol/edge graph as the non-negotiable ground truth layer,
not a Phase-2 nicety (see §6).

**Why we don't just tell the user to run CodeBoarding:**
- It is **not Mac-native and not beautiful in Cribble's sense** — it's a CLI/CI/VS-Code dev
  tool, output is raw Mermaid in a repo folder, no calm reading surface, no idle second brain,
  no "ask about this project" over your *own* prose.
- It is **code-only.** Cribble's user mixes **project `.md` knowledge files** with code. The
  defensible product is the one that treats *prose notes + code + diffs* as one knowledge
  graph. CodeBoarding has no opinion about your notes.
- Licensing is **unspecified** in its README (no clear LICENSE) — risky to depend on or vendor.

### 1.2 Swark — the lightweight LLM-diagram baseline

[Swark](https://github.com/swark-io/swark) is a VS Code extension: point at a codebase, the
LLM emits a **Mermaid** architecture diagram. No static-analysis validation — "all the logic
is in the LLM," which is exactly the failure mode we must avoid. Useful as proof the
"one-click diagram" expectation exists; **not** a model to copy.

### 1.3 C4 / "architecture as code" frameworks

[C4 InterFlow](https://www.c4interflow.com/) and the broader C4 model represent the *other*
philosophy: humans author a structured model (YAML/C4) and diagrams generate from it. This is
the disciplined SDLC the user nostalgically describes ("requirements → diagrams → UML →
code"). It's rigorous but **high-friction and human-authored** — the opposite of "the AI
wrote it and I lost track." Worth knowing as the vocabulary (C4's
Context→Container→Component→Code levels map cleanly onto our artifact tiers), not as a tool to
adopt.

### 1.4 Khoj — the closest thing to the *second-brain* half

[Khoj](https://github.com/khoj-ai/khoj) (YC W24, AGPL-3.0) is the reference design for
"local AI second brain": RAG over your Markdown/PDF/docs, **Ollama for local models**,
scheduled automations, Obsidian plugin. It proves the demand and the shape (semantic search +
chat over a personal corpus, optionally offline).

But it is **a self-hosted server (Python/Docker), AGPL, and document-centric** — it does not
understand code structure, it isn't Mac-native, and AGPL is hostile to a shipped commercial
desktop app. **Cribble's opening:** the *native, no-server, no-Docker, code-aware* second
brain. Khoj is what Cribble's idle layer should feel like, minus the ops burden.

### 1.5 Verdict

| Need | Best existing OSS | Gap Cribble fills |
|------|-------------------|-------------------|
| Auto architecture diagram from code | **CodeBoarding** (static+LLM, Mermaid, Ollama, incremental) | Native, beautiful, prose+code unified, you-own-it |
| One-click LLM diagram | Swark | (validation; not a model to copy) |
| Human-authored model → diagram | C4 InterFlow | Friction; we want zero-authoring |
| Local AI second brain over notes | **Khoj** | Native, serverless, code-aware |

**Nobody ships the union: a calm, Mac-native reading surface where AI-generated code,
project notes, and diffs are continuously distilled into source-cited, always-current
explanations and diagrams — running quietly on-device.** That union is the product.

---

## 2. "Beautiful" — how to show a technical product's components

The user explicitly wants it to be *beautiful*. Two honest observations:

1. **Mermaid is correct for v1, but Mermaid alone is not "beautiful."** It's legible and
   already wired into Cribble (`MermaidWebDiagramView`). Ship it. But auto-generated Mermaid
   `graph TD` on a 200-file repo becomes hairball spaghetti fast. Beauty here is **less about
   the renderer and more about curation**: hierarchy, progressive disclosure, and never
   showing all nodes at once.
2. **The dead ends:** [Sourcetrail](https://github.com/CoatiSoftware/Sourcetrail) was the
   gold standard for interactive code graphs and is **archived/unmaintained** — instructive
   for *interaction design* (graph + condensed code + search, side by side) but not adoptable.
   [CodeSee](https://www.codesee.io/) (continuous code maps) is **commercial/SaaS**, not local,
   and has wound down — again, study the UX, don't depend on it.

### 2.1 Recommended visual ladder (maps onto plan §13)

| Tier | Tech | What makes it beautiful | When |
|------|------|------------------------|------|
| **0. Narrative-first** | Styled Markdown (`StructuredText`) | A *written* architecture overview reads better than any auto-graph. Prose + small inline diagrams. | Phase 1 |
| **1. Curated Mermaid** | existing `MermaidWebDiagramView` | C4 levels: one Context diagram, drill into Containers, then Components. **Cap nodes per view (~12).** | Phase 1–2 |
| **2. Clickable diagram → source** | Mermaid node click → open file at line | The "beauty" users feel is *navigation*, not gradients. Diagram becomes a map you travel. | Phase 2 |
| **3. Infinite canvas** | [tldraw](https://tldraw.dev/) or React Flow in `WKWebView` | Pan/zoom/annotate, persistent layout, hand-arranged. This is the "expensive-feeling" tier. | Phase 3 |

**Design principles for the visual layer (this is where "net UX" lives):**

- **The graph is a means, the explanation is the end.** Default to the written overview; the
  diagram is the index, not the payload.
- **Progressive disclosure via C4 levels.** Never render the whole repo. Context → Container →
  Component → Code. Each level fits on one screen.
- **Provenance on every node/claim.** Every box, every sentence links to `file:line`. (See §5.)
- **Stable layouts.** Auto-relayout on every change is disorienting; persist node positions and
  only animate deltas. This is the difference between "tool" and "trustworthy map."
- **Calm, not dashboard-y.** Cribble's whole brand is quiet and native. Resist the
  graph-IDE temptation; keep one beautiful diagram + one beautiful doc per screen.

> **UX recommendation:** do **not** make the interactive canvas a Phase-1 goal. A gorgeous
> *written* architecture page with a single curated diagram and click-to-source will feel more
> premium — and build more trust — than a draggable hairball. Earn the canvas later.

---

## 3. Local llama.cpp / runner integration — this is the easy part

Good news: this is nearly free and the plan slightly over-engineers it.

- **llama.cpp ships `llama-server`, an OpenAI-compatible HTTP server** exposing
  `/v1/chat/completions` **and `/v1/embeddings`** at `localhost:8080`. Apple Silicon is a
  first-class target (Metal on by default), and llama.cpp even publishes an **XCFramework** for
  direct in-process Swift embedding if we ever want to drop the HTTP hop.
  ([llama.cpp](https://github.com/ggml-org/llama.cpp),
  [server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md))
- **Ollama is the same shape** (OpenAI-compatible `/v1/...` + `/api/embeddings`).
- The existing `docs/ollama-integration-plan.md` already covers this surface.

### 3.1 Recommendation: one provider, not four

The plan proposes separate `OllamaIntelligenceProvider` and `LlamaCppIntelligenceProvider`
(`plan §6.3`). **Collapse them.** They speak the same OpenAI-compatible dialect. Ship a single:

```
OpenAICompatibleProvider(baseURL: URL, apiKey: String?, model: String, embedModel: String?)
```

- Point it at `http://localhost:11434/v1` (Ollama), `http://localhost:8080/v1`
  (llama-server), LM Studio, vLLM, or any future local runner — **zero new code per runner.**
- Auto-detect: probe common local ports on enable; if one answers `/v1/models`, offer it.
- Keep `MLXIntelligenceProvider` separate (it's in-process, no HTTP) — that's the true native
  fast path and Cribble's differentiator. Everything else is "bring your own OpenAI-compatible
  endpoint."

This shrinks the provider matrix from 4 classes to 2 (in-process MLX + one HTTP client) and
makes the local-runner story *"works with anything OpenAI-compatible on localhost"* — a
stronger open-source pitch than naming specific runners.

### 3.2 In-process vs. server

| Path | Pros | Cons | Use |
|------|------|------|-----|
| **MLX (in-process)** | Fastest cold start, no server to manage, fully sandboxed | Apple-only, MLX model formats | Default on-device path |
| **llama.cpp XCFramework (in-process)** | GGUF ecosystem, no HTTP, sandbox-friendly | More integration work | Future, if GGUF demand is high |
| **OpenAI-compatible HTTP (Ollama / llama-server)** | Zero coupling, power users already run these, trivial | Requires a running server, sandbox/network entitlement | "Advanced: point Cribble at my runner" |

> Sandbox note: the Mac App Store build needs the `com.apple.security.network.client`
> entitlement to reach `localhost`. The **MLX in-process path is the only one that's
> friction-free under App Store sandboxing** — another reason MLX stays the default and HTTP
> runners are the power-user opt-in (best surfaced in the DMG build).

---

## 4. The idle "continuous second brain" — the actual differentiator

This is where Cribble can be genuinely novel, and where the plan is thinnest on **UX** (it's
strong on the scheduler mechanics in §8 but quiet on *what the user experiences*).

The plan's idle scheduler (`§8`: thermal/battery/idle tiers, 1 concurrent SLM job) is solid
engineering. The missing half is: **when the machine has been quietly thinking for an hour,
what does the user wake up to, and why do they trust it?**

### 4.1 Reframe: from "background jobs" to "a digest you review"

The mental model should be a **diligent junior who read your repo overnight and left you
notes** — not a daemon mutating files. Concretely, idle time produces a **reviewable feed**,
never silent writes (consistent with Cribble's "preview before mutation" principle).

**Proposed idle outputs, in priority order:**

1. **"Since you last looked" digest.** Narrate what changed (working tree + commits) in plain
   language, each claim linked to the diff. This *directly* answers "I don't know what the AI
   wrote" — it's a running, human-readable changelog of your own codebase.
2. **Drift alerts.** "The architecture doc says X calls Y, but the code no longer does." This
   is the highest-value, lowest-hallucination signal because it's a **graph diff**, validated
   against static analysis, not a vibe. (Plan §12 has this — promote it; it's the killer
   feature, not a Phase-3 footnote.)
3. **Connection suggestions.** Khoj-style: "These two notes / this note and this module are
   about the same thing — want a `[[wiki link]]`?" Cribble already has wiki-link + diff-preview
   plumbing; this rides on it.
4. **Open questions / unknowns.** "I couldn't tell why `retryCount` is 3 here — is that
   intentional?" Surfacing the model's *uncertainty* builds trust far more than confident prose.
5. **Audits** (fallbacks, error boundaries, silent failures) — plan §7, surfaced as cards.

### 4.2 The trust contract (most important UX rule in the whole product)

> **Every generated statement carries its source. No claim without a `file:line` (or
> `commit`/`diff`) behind it, one click away.**

This is the entire answer to the user's transparency problem. The reason they re-ask Claude is
that the explanation isn't *anchored* to the code. An anchored, verifiable explanation they can
audit in one click is the difference between a toy and a second brain. **Bake provenance into
the artifact schema from day one** (see §5), not as a later polish.

### 4.3 Idle UX details

- **Glanceable, interruptible.** The sidebar indicator (plan §9) is right. Add a single
  "3 new insights" affordance; never a modal, never a notification storm.
- **Decay & dismiss.** Insights the user dismisses shouldn't come back. Track dismissals by
  content hash.
- **Cost honesty.** A tiny "thought for 4 min while idle, used 2% battery" line. Respect that
  it's *their* machine. This earns permission to keep running.
- **Opt-in depth.** Default to cheap Tier-1/2 (digests, drift). Deep audits only when the user
  asks or explicitly enables "think harder when idle."

---

## 5. Provenance & data model — the one change that matters most

To make §4.2 real, extend the plan's `artifacts` schema (§5.2) with **claim-level provenance**.
A summary that says "handles auth via JWT" is worthless if the user can't jump to the 6 lines
that prove it.

Add a table (or JSON sidecar) linking artifact spans to source:

```sql
CREATE TABLE artifact_provenance (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    artifact_id  TEXT NOT NULL REFERENCES artifacts(id) ON DELETE CASCADE,
    claim_anchor TEXT NOT NULL,   -- offset/heading within the artifact the claim sits at
    file_id      INTEGER REFERENCES files(id),
    start_line   INTEGER,
    end_line     INTEGER,
    symbol_id    INTEGER REFERENCES symbols(id),
    confidence   REAL             -- model-reported or validator-derived
);
```

In rendered Markdown, this becomes a clickable superscript / margin marker → opens the source
in the reader at that range. This is small to build and is the **defining UX of the product**.

> If only one thing from this document ships beyond the base plan, it should be
> **claim-level provenance**. It is the feature.

---

## 6. Where the plan should change (focused deltas)

The technical plan (`cribble-intelligence-plan.md`) is genuinely good. These are the targeted
adjustments this research implies — not a rewrite:

1. **Static graph is ground truth, not Phase 2.** Don't ship an "architecture diagram" built
   on regex + file summaries; it will hallucinate edges. Build a real symbol/import/call graph
   first (even a coarse one), then let the SLM *narrate validated edges only*. This is the
   CodeBoarding lesson (§1.1). For Swift, evaluate **SwiftSyntax/IndexStoreDB** sooner than
   plan §11.2/§15-Phase-3 suggests, at least for the graph (not necessarily for summaries).
2. **Collapse Ollama + llama.cpp into one `OpenAICompatibleProvider`** (§3.1). Keep MLX
   separate as the native default.
3. **Promote drift detection** from Phase 3 to a Phase-2 headline. It's the highest-trust,
   lowest-hallucination output and the visible proof that "the code follows the diagram" (§4.1).
4. **Add `artifact_provenance`** to the Phase-1 schema (§5). Provenance is foundational, not a
   finish.
5. **Reframe idle output as a reviewable digest feed** with a trust contract, not just a job
   queue (§4). The scheduler stays; the *surface* gets designed.
6. **De-scope the interactive canvas** to Phase 3 and lead with a beautiful *written*
   architecture page + curated, click-to-source Mermaid (§2). Lower risk, higher perceived
   quality.
7. **Defer "edit diagram → mutate code"** explicitly (it's already future-flagged in §12 —
   keep it there and resist pull-forward). See §8.

---

## 7. Native macOS — performance posture

The plan is already correct to be native-first (`MLX`, `CGEventSource` idle, `ProcessInfo`
thermal/battery). Reinforcing notes:

- **MLX + Apple NL embeddings is the right default**: in-process, Metal-accelerated, no server,
  sandbox-clean. Keep it the path of least resistance.
- **Serialize SLM work hard** (plan: max 1 concurrent) and keep the deterministic Tier-1 work
  (scan/hash/parse) off the main thread but always-on — that layer must feel instant and never
  needs a model.
- **Respect the laptop.** Battery/thermal gating (plan §8) plus the "cost honesty" UI (§4.3) is
  what makes an always-running on-device brain socially acceptable rather than the thing users
  rush to disable.
- **The XCFramework option** (llama.cpp in-process) is the escape hatch if GGUF model variety
  becomes a user demand — keeps everything in-process and sandbox-friendly.

---

## 8. The honest take on "edit the diagram, the code follows"

The user's most exciting idea is also the most dangerous, and clarity here is a kindness:

- **True round-tripping (diagram is the source, code is generated) does not work** for
  general-purpose code. It's the decades-old failed promise of model-driven / round-trip CASE
  tools. It only holds in narrow DSLs (UI builders, state-machine generators, infra-as-code).
  An SLM editing arbitrary Swift from a box-and-arrow edit will produce confident breakage.
- **What *is* achievable and still delivers the feeling** (plan §12 already nails this):
  1. Diagram and code are both *projections* of the same validated graph.
  2. User edits the diagram → Cribble computes the **intent delta** (add edge, split module).
  3. Cribble reports **implemented / missing / conflicting** against the real code graph.
  4. On request, the SLM proposes a **`UnifiedDiff`** → existing `DiffPreviewSheet` → user
     approves. **The human stays in the loop; nothing mutates silently.**

> Sell it as **"the diagram and the code stay honest with each other, and you can ask the
> diagram to draft a change"** — not "draw a box and code appears." The first is trustworthy
> and shippable; the second erodes the exact trust the whole product is trying to build.

---

## 9. Making this a real, lasting open-source project

The user asked for "exhaustive steps to make this product open source for the longer term and
very well organized." Below is a concrete program. **It opens with a blocker.**

### 9.1 The blocker: there is no license

The repo is public but **has no `LICENSE` file** (verified — no `LICENSE`/`COPYING` in root).
Legally, *"public on GitHub" ≠ "open source."* With no license, default copyright applies:
**all rights reserved.** Nobody may legally fork, modify, or redistribute. This must be fixed
before any "open-source" claim in the README is accurate.

The tension to resolve first: **Cribble is a paid app** (App Store IAP / DMG with Local AI
unlock). Pick a model deliberately:

| Model | What's open | What's paid | Fit |
|-------|------------|-------------|-----|
| **Open core** *(recommended)* | App shell, reader, Markdown engine, intelligence framework, provider protocol | Cloud sync, premium models, team features, or just "convenience binary" | Matches the existing IAP reality; community can build providers/plugins |
| **Source-available** (e.g. BSL, Elastic v2, FSL) | Everything readable & self-buildable | Commercial/competing use restricted, converts to OSI-OSS after N years | Protects the business while being transparent |
| **Permissive (MIT/Apache-2.0)** | Everything | Nothing (rely on goodwill/hosted) | Maximal community, weakest moat |
| **Copyleft (GPL/AGPL)** | Everything | — | **Avoid**: incompatible with App Store distribution & a paid binary |

**Recommendation:** **Apache-2.0 for the framework/engine modules** (provider protocol,
intelligence engine, diff/markdown libraries — the parts you *want* contributions to), and keep
the shipping app either Apache-2.0 (open core, monetize convenience + cloud) or a source-available
license if a moat is needed. Apache-2.0 (vs MIT) because its explicit patent grant matters once
LLM/codegen patents are in play. **Avoid AGPL** (Khoj's choice) — it's actively hostile to
shipping a sandboxed commercial Mac binary.

### 9.2 Repository hygiene (the "well organized" ask)

Add, in roughly this order:

1. **`LICENSE`** — per §9.1. *(blocker)*
2. **`CONTRIBUTING.md`** — build from source, run tests (`swift test`), branch/PR conventions,
   the "preview before mutation" / "reader-only" principles as non-negotiables, DCO or CLA
   choice.
3. **`CODE_OF_CONDUCT.md`** — Contributor Covenant; table stakes for outside contributors.
4. **`GOVERNANCE.md`** — even for a solo maintainer, state how decisions are made, what's in
   scope, and a **hand-off/archival plan** (the literature is blunt: ~70% of OSS is one person;
   say what happens if you step away).
   ([Turing Way](https://book.the-turing-way.org/collaboration/oss-sustainability/oss-sustainability-challenges/),
   [OpenSSF](https://openssf.org/blog/2025/09/23/open-infrastructure-is-not-free-a-joint-statement-on-sustainable-stewardship/))
5. **`SECURITY.md`** — already have a diagnostic/issue flow; add a disclosure address. Critical
   for a tool that reads people's whole codebases and runs models on them.
6. **`ROADMAP.md`** — public, honest, links to the two plan docs. The phasing in
   `cribble-intelligence-plan.md §15` is already roadmap-grade; surface it.
7. **`ARCHITECTURE.md`** — ironically, the project that builds architecture docs should ship a
   hand-written one. (Dogfood: generate the first draft with Cribble Intelligence itself once it
   exists — strong marketing.)
8. **Issue/PR templates & labels** — `good first issue`, `provider`, `intelligence`, `reader`.
9. **`CHANGELOG.md`** — already exists; keep it.

### 9.3 Modularize so the community can actually contribute

A monolithic macOS app is hard to contribute to. Split the SwiftPM package into libraries with
clean seams (the `Package.swift` already has the structure to grow into this):

- `CribbleMarkdown` — rendering/parsing (reusable, attractive standalone).
- `CribbleDiff` — unified-diff parse/preview/apply (genuinely reusable; could stand alone).
- `CribbleIntelligence` — engine, job queue, artifact store, **`IntelligenceProvider` protocol**.
- `CribbleProviders` — MLX + `OpenAICompatibleProvider`. **This is the contribution magnet:** a
  documented provider protocol means the community adds runners without touching the app.
- `Cribble` (app) — the macOS shell that composes the above.

> **The strategic move:** make the **provider protocol** and the **artifact/job model** the
> stable public API. Community PRs flow into providers and job types; the app and business stay
> yours. This is how open core stays healthy.

A stretch option worth noting: a **headless `cribble-intel` CLI** that runs the engine over a
folder and emits artifacts (à la CodeBoarding's CLI). It makes the engine testable in CI,
usable by non-Mac contributors, and gives the project a second on-ramp. Gate behind demand.

### 9.4 Sustainability & community

- **Funding:** keep the IAP/paid-binary as the primary engine (the research is unanimous that
  goodwill alone doesn't sustain maintainers). Add **GitHub Sponsors / Open Collective** for
  people who self-build and want to support — low effort, real signal.
- **Don't over-promise community.** A solo-maintained project should advertise *transparency and
  forkability*, not *"we'll review your PR in 24h."* Set response expectations in
  `CONTRIBUTING.md`.
- **Discoverability:** SwiftPM registry/`Package.swift` metadata, topics, a one-command build,
  and — once it exists — a self-generated `ARCHITECTURE.md` as the headline demo. The product
  *is* its own best onboarding doc.
- **Security posture as a feature:** "local-first, reads your code on-device, nothing leaves the
  machine, every claim is source-cited" is both the UX pitch (§4.2) and the open-source trust
  pitch. Make it loud.

### 9.5 Open-source rollout sequence

1. **Add `LICENSE`** (decide open core vs. source-available first). *Unblocks everything.*
2. Add `CONTRIBUTING`, `CoC`, `SECURITY`, issue/PR templates.
3. Land the **modular SwiftPM split** + document the **provider protocol** as the public API.
4. Publish `ARCHITECTURE.md` + `ROADMAP.md` (link both plan docs).
5. Add `GOVERNANCE.md` with an explicit scope + hand-off plan; open GitHub Sponsors.
6. *(Optional)* ship the headless CLI for CI + non-Mac contributors.
7. Announce as open source **only after step 1** — until then the README's "open source"
   framing is aspirational, not accurate.

---

## 10. Bottom line

- **The diagram problem is solved enough** (CodeBoarding) that we should **borrow its
  pattern — static graph as ground truth, LLM narrates validated edges — and not rebuild its
  engine or copy its dev-tool UX.**
- **The unsolved, defensible product** is the **native, serverless, calm, on-device second
  brain that unifies AI-generated code + project notes + diffs into source-cited, always-current
  explanations** — Khoj's value without Khoj's server, CodeBoarding's rigor without
  CodeBoarding's CLI-ness.
- **The feature that makes it real is claim-level provenance** (§5) plus a **trust contract**
  (§4.2): nothing is asserted that the user can't verify in one click. That is the literal answer
  to "I've lost the mental model of what the AI built."
- **Local runners are trivial** — one `OpenAICompatibleProvider` covers Ollama + llama.cpp +
  the rest; MLX stays the native default.
- **"Edit diagram → code" should ship as drift-detection + propose-a-diff**, never silent
  round-tripping.
- **Before calling it open source, add a `LICENSE`** and pick an open-core/source-available
  model that coexists with the paid app; then modularize so the **provider protocol** is the
  community's contribution surface.

---

### Sources

- [CodeBoarding (GitHub)](https://github.com/CodeBoarding/CodeBoarding) · [README](https://github.com/CodeBoarding/CodeBoarding/blob/main/README.md) · [Show HN](https://news.ycombinator.com/item?id=44737689)
- [Swark (GitHub)](https://github.com/swark-io/swark)
- [C4 InterFlow](https://www.c4interflow.com/)
- [Khoj (GitHub)](https://github.com/khoj-ai/khoj) · [Khoj + Ollama docs](https://github.com/khoj-ai/khoj/blob/master/documentation/docs/advanced/ollama.mdx)
- [llama.cpp (GitHub)](https://github.com/ggml-org/llama.cpp) · [llama-server README](https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md)
- [tldraw SDK](https://tldraw.dev/) · [CodeSee](https://www.codesee.io/) · [Sourcetrail (archived)](https://github.com/CoatiSoftware/Sourcetrail)
- [The Turing Way — OSS sustainability](https://book.the-turing-way.org/collaboration/oss-sustainability/oss-sustainability-challenges/) · [OpenSSF — sustainable stewardship](https://openssf.org/blog/2025/09/23/open-infrastructure-is-not-free-a-joint-statement-on-sustainable-stewardship/) · [OSI — sustaining open source](https://opensource.org/blog/sustaining-open-source-the-next-25-years-depend-on-what-we-do-together-now)
