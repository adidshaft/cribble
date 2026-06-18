# Cribble — Connected-Reading Upgrade (Obsidian-favorite features)

| Field         | Value                                                                 |
|---------------|-----------------------------------------------------------------------|
| Status        | Plan — not started                                                     |
| Version       | 2.0 (supersedes `linked-mentions-plan.md`; Track A folds it in)       |
| Target branch | Branch from the frontier (`night-shift`, or `main` once promoted) → `feature/connected-reading` |
| Scope         | Bring the most-loved Obsidian reading/navigation features to Cribble   |
| Guardrails    | Reader-only · local-first · native macOS · performant · calm           |
| Surface area  | `Services/`, `Stores/`, `Models/`, `Views/`, `Support/`, `Tests/`      |
| Last updated  | 2026-06-17                                                             |

> This document is the implementation plan only — what to build and how. Implement the
> tracks in the order given in §13 (Sequencing). Each phase is one DCO-signed commit
> (`git commit -s`, per `CONTRIBUTING.md`) that leaves `swift test` green. Keep the status
> ledger in §14 current. Markers labelled **VERIFY** must be confirmed against the live
> source before coding against them.

---

## 1. Context

Cribble is a calm, local-first macOS Markdown **reader** with rich rendering, wiki links,
on-device chat/intelligence, and (on `night-shift`) a global note-connections graph. The
gaps that keep Obsidian users from switching are mostly *reading and navigation* features —
not editing. This plan adds the highest-value, best-fitting ones as independent tracks.

Every track here is either pure read-side rendering/derivation or a native navigation
overlay. None introduces a Markdown editor, none writes user files (the one optional
"convert" affordance copies text to the clipboard), and none makes network calls.

## 2. Design constraints (apply to EVERY track)

1. **Reader-only.** No code path writes a user `.md` file. Clipboard-only for any "insert"
   affordance. Anything that could ever mutate goes through the existing diff-preview flow.
2. **Local-first.** No network, no cloud. "Intelligence" means the on-device embedding
   index / MLX models already in the app.
3. **Native macOS.** SwiftUI + AppKit interop, system controls, SF Symbols, system
   materials. Use Liquid Glass materials on macOS 26+ with the existing native fallback on
   15–25. No web views except where one already exists (Mermaid).
4. **Performance.** Build indexes once per scan and update incrementally; do work lazily
   for the visible note only; bound every traversal (hops, result counts, recursion depth);
   never block the main thread on vault-wide work.
5. **Calm UI.** No noisy chrome or always-on overlays. Respect Reduce Motion and the
   reader text-size presets (XXS–XXL). Empty states are quiet, not alarming.
6. **No new always-on single-key shortcuts** beyond the two palette accelerators in Track D
   (⌘O / ⌘P, which are standard and non-conflicting). Anything else goes through menus.

## 3. Tracks at a glance

| Track | Feature | Obsidian parallel | Writes files? | Local intelligence | Depends on |
|-------|---------|-------------------|---------------|--------------------|-----------|
| A | Linked Mentions (backlinks) | Linked/Unlinked mentions | No | — | `LinkIndex` |
| B | Transclusion / embeds | `![[note]]`, `![[note#h]]`, `^block` | No | — | render pipeline, `LinkIndex` |
| C | Callouts / admonitions | Callouts | No | — | render pipeline |
| D | Quick Switcher + Command Palette | ⌘O / ⌘P | No | optional ranking | `MarkdownLibraryStore`, command wiring |
| E | Tags (inline + pane) | Tag pane, `#tags` | No | — | `FrontMatterParser` |
| F | Related Notes (semantic) | Smart Connections | No | **Yes (core)** | `SemanticSearchIndex` / `VectorIndex` |
| G | Local Graph (neighborhood) | Local graph view | No | — | `NoteConnectionsGraph` (night-shift) |

---

## 4. Track A — Linked Mentions (backlinks)

**What:** under the current note, a collapsible "Linked Mentions" section listing every note
that wiki-links to it (grouped per source with a one-line context snippet and occurrence
count); optional "Unlinked Mentions" subsection with copy-to-clipboard `[[wiki link]]`.

**Why loved:** the #1 connected-notes feature; the inverse of the forward links Cribble
already shows.

**How**
- Add `Models/Backlink.swift` (`Backlink { sourceURL, sourceTitle, occurrences }`,
  `BacklinkOccurrence { linkLabel, snippet, headingContext }`).
- Add `Services/BacklinkIndex.swift`: iterate documents, parse each with `WikiLinkParser`
  (**VERIFY** it exposes a source `range`; add one if missing), resolve every link via
  `LinkIndex.resolve` (reuse so matching matches forward navigation exactly), key the
  reverse map by `targetURL.standardizedFileURL`, skip self-links, group by source.
  Compute snippets **lazily** for the displayed target only.
- Exclude wiki links inside fenced/inline code (**VERIFY** parser behavior; filter by range
  if needed).
- Add `Stores/MarkdownLibraryStore+Backlinks.swift`: build alongside `LinkIndex` in the
  scan/reload lifecycle; expose `backlinks(for: URL) -> [Backlink]`. Keep this out of the
  55 KB store body.
- Add `Views/LinkedMentionsSection.swift`: mirror the existing linked-files panel; sort by
  source title; hide when empty; row tap → existing in-app navigation; reuse
  `NotePreviewPopover` on hover; accessible rows; Reduce-Motion-aware expand.
- Mount it in `ReaderView.swift` next to the linked-files panel (composition only).

**Phases:** A1 index+store+tests · A2 reader panel · A3 snippets/preview/a11y ·
A4 (optional) unlinked mentions (copy-only) · A5 docs.

**Tests** (`Tests/CribbleTests/BacklinkIndexTests.swift`): simple resolve; alias/title/
heading parity; labeled link; multi-occurrence grouping+count; self-link excluded;
unresolved → none; links-in-code ignored; snippet stripped+truncated; sorted by title;
canonical relative-vs-absolute URL match.

---

## 5. Track B — Transclusion / embeds (`![[Note]]`, `![[Note#Heading]]`, `![[Note^block]]`)

**What:** render embedded note content inline in the reader. `![[Note]]` embeds the whole
note; `![[Note#Heading]]` embeds that section; `![[Note^blockid]]` embeds a single block.
Embeds show in a subtle inset card with a title chip that click-navigates to the source.

**Why loved:** lets one note compose many — the backbone of MOCs/indexes in Obsidian. It is
*pure rendering*, so it is the most natural Obsidian feature for a reader-only app.

**How**
- **Parser:** extend the wiki-link layer to recognize the leading `!` embed form and the
  `^blockid` suffix. Add `Models/EmbedReference.swift` (`{ target, heading?, blockID?, range }`).
  **VERIFY** where wiki links are tokenized (`WikiLinkParser` + the rich-block splitter the
  README calls "rich fenced-block splitting / Markdown display preparation") and add embeds
  as a new block kind there so they slot into the existing render pass.
- **Resolution:** reuse `LinkIndex.resolve` for the file; for `#Heading` slice the target's
  content between that heading and the next same-or-higher heading (reuse the heading model
  already parsed for `LinkIndex`); for `^blockid` find the trailing `^blockid` marker on a
  block (**VERIFY** none exists yet; define the standard Obsidian form).
- **Render:** a new `Views/EmbeddedNoteView.swift` that runs the embedded slice back through
  the **same** Textual/native render path (so tables, code, math, Mermaid render inside the
  embed). Wrap in a calm inset (system material, left accent rule) with a header chip
  (source title) that navigates on click.
- **Safety/perf:** depth-limit recursion (e.g. max 3) and detect cycles (A embeds B embeds A)
  → render a "↩ cyclic embed" stub instead of looping. Render embeds lazily as they scroll
  into view; cache resolved slices per render pass.
- **Fallback:** unresolved embed renders a muted "Cannot resolve ![[…]]" inline, never an
  error.

**Phases:** B1 parse embed syntax + model + tests · B2 resolve note/heading/block slices +
cycle/depth guard + tests · B3 `EmbeddedNoteView` recursive render + calm styling ·
B4 lazy/caching perf pass + a11y (embed is an a11y group labelled "Embedded note: <title>").

**Tests:** embed-syntax parsing (`!`, `#`, `^` forms); heading-slice boundaries; block-id
slice; cycle detection; depth cap; unresolved fallback; nested embed renders.

---

## 6. Track C — Callouts / admonitions (`> [!note]`, `[!warning]`, `[!tip]`, …)

**What:** render blockquotes that start with `[!type]` as styled callout cards (icon +
title + body), with `+`/`-` foldable variants (`> [!faq]-` collapsed by default).

**Why loved:** the most-used Obsidian reading-polish feature; turns plain quotes into
scannable, color-coded admonitions. Pure rendering, calm, native.

**How**
- In the blockquote rendering step (**VERIFY** location in the Textual/native block pass),
  detect a first line matching `^\[!(?<type>[\w-]+)\](?<fold>[+-]?)\s*(?<title>.*)$`.
- Add `Support/CalloutStyle.swift`: map known types → SF Symbol + accent color using
  **system/semantic colors** (note/info, tip/success, warning, danger/error, quote,
  question, example, abstract…). Unknown types fall back to a default note style (never
  break). Default title = type capitalized; custom title overrides.
- Render `Views/CalloutView.swift`: icon + title header + rendered body (body runs through
  the normal Markdown path so nested lists/code/math work). Foldable when `+`/`-` present;
  default-collapsed for `-`. Liquid Glass material on 26+, native material fallback.
- Respect Reduce Motion on fold animation; callout is one a11y group ("Callout, <type>:
  <title>").

**Phases:** C1 detect + type/title/fold parsing + tests · C2 `CalloutView` + `CalloutStyle`
+ nested body render · C3 foldable behavior + a11y + theme/contrast check (light/dark).

**Tests:** type/title/fold parsing incl. unknown-type fallback; nested content renders;
collapsed-by-default for `-`; quote without `[!]` still renders as a normal quote (no
regression).

---

## 7. Track D — Quick Switcher (⌘O) + Command Palette (⌘P)

**What:** two native fuzzy overlays. ⌘O jumps to any note in the open libraries by fuzzy
name/title/alias. ⌘P runs any app command (every menu action) by fuzzy name, showing its
shortcut. Arrow keys + Enter; Esc closes; recent items first.

**Why loved:** the fastest way to move around a vault; power users barely touch the sidebar.
Complements Cribble's single-key shortcuts by making the full surface discoverable.

**How**
- Add `Support/FuzzyMatch.swift`: a small subsequence scorer (contiguous-run + word-boundary
  + acronym bonuses, recency tiebreak). Pure, fully unit-tested.
- **Quick Switcher** `Views/QuickSwitcherView.swift`: source items from
  `MarkdownLibraryStore.documents` (title, alias from frontmatter, relative path); on pick,
  use existing navigation. Maintain a small recent-notes list (in-memory + `AppSettings`).
  Optional Track-F tie-in: a "Related" toggle re-ranks by semantic similarity to the current
  note (still local).
- **Command Palette** `Views/CommandPaletteView.swift`: build a `[PaletteCommand]` registry
  from the app's existing commands. **VERIFY** the command source (the consolidated menu
  wiring in `ContentView.swift` / the `App/` command definitions); expose each as
  `{ id, title, shortcut?, action }` so palette and menus stay in sync (single source of
  truth — don't duplicate action closures).
- Present both as centered overlays using system materials (not full sheets); width-capped;
  keyboard-first; VoiceOver-labelled rows; Reduce-Motion-aware appearance.
- Register ⌘O / ⌘P in the existing command/menu system; verify no conflict with the new
  ⌘-letter copy shortcuts (⌘M/⌘L/⌘W/⌘I/⌘N) from 1.4.0.

**Phases:** D1 `FuzzyMatch` + tests · D2 Quick Switcher (notes) + recents · D3 Command
Palette over the command registry · D4 a11y + focus-management (must not trap keyboard — the
1.4.0 notes already flag focus fragility).

**Tests:** fuzzy ranking (exact > prefix > acronym > scattered; recency tiebreak); switcher
filters titles+aliases+paths; palette lists commands with correct shortcuts; empty query
shows recents.

---

## 8. Track E — Tags (inline `#tags` + tag pane)

**What:** render inline `#tag` / `#nested/tag` in note bodies as clickable chips; a Tags
pane (sidebar section or overlay) lists all tags with counts; selecting a tag shows the
notes carrying it. Frontmatter `tags:` and inline tags are unified.

**Why loved:** tags are a primary Obsidian organization axis; the tag pane + click-to-filter
is daily-driver behavior. Read-only and mostly a surfacing of data already parsed.

**How**
- Add `Services/TagIndex.swift` (parallels `LinkIndex`): collect tags from
  `FrontMatterParser` (already extracts `tags`) **and** a new inline-body scan
  (`#[\w/-]+`, excluding `#` inside code spans and `#` heading lines). Map
  `normalizedTag -> [URL]` with counts; support nested `a/b` (selecting `a` includes `a/b`).
- Build it in `MarkdownLibraryStore` alongside the other indexes; expose `allTags()` and
  `notes(forTag:)`.
- Render: extend the inline render pass to turn `#tag` into a chip button (**VERIFY** inline
  token hook). Clicking sets a tag filter.
- `Views/TagPaneView.swift`: a quiet sidebar section (or ⌘-less overlay) listing tags by
  frequency/alpha; selection drives a filtered note list (reuse existing list UI). No new
  global shortcut; reachable from the sidebar + View menu.

**Phases:** E1 `TagIndex` (frontmatter + inline scan, nested, code-exclusion) + tests ·
E2 clickable inline tag chips · E3 Tag pane + filtered results + a11y.

**Tests:** frontmatter+inline unification; nested-tag containment; `#` in code/headings
ignored; counts correct; case/diacritic normalization consistent with the app's existing
normalize.

---

## 9. Track F — Related Notes (on-device semantic) — *the local-intelligence headline*

**What:** a "Related Notes" section under the current note showing the most semantically
similar notes (title + similarity + one-line why), computed entirely on-device. A
Smart-Connections-style experience with zero cloud.

**Why loved:** surfaces non-obvious connections the user never linked — the single most
popular Obsidian community plugin category — and it leans directly into Cribble's on-device
embedding stack.

**How**
- Reuse the existing embedding index: `Services/SemanticSearchIndex.swift` (on `main`) and
  the `VectorIndex` / `SQLiteVectorIndex` on `night-shift` (brute-force cosine over stored
  embeddings — already shipped). **VERIFY** the query API; add
  `relatedNotes(to: URL, limit: Int) -> [(URL, score)]` that embeds the current note (or
  reuses its stored vector) and returns top-K excluding itself and near-duplicates.
- Add `Stores/MarkdownLibraryStore+Related.swift` to expose it to the reader.
- `Views/RelatedNotesSection.swift`: a calm collapsible section beneath Linked Mentions;
  rows reuse `NotePreviewPopover` + existing navigation; show a subtle score bar. Compute
  **lazily** for the visible note and **debounce** on note change; never block scrolling.
- Optional (local, gated): a one-line "why related" generated by the on-device model via the
  existing `LocalLLM` path, behind the same entitlement as other AI — off by default to keep
  it instant. Strictly local; no network.
- Perf: cap K (e.g. 5), cache per note, reuse precomputed embeddings, run similarity off the
  main actor.

**Phases:** F1 `relatedNotes` over the existing vector index + tests (with a stub embedder)
· F2 `RelatedNotesSection` UI (lazy, debounced) · F3 (optional) on-device "why related"
one-liner behind the AI entitlement · F4 a11y + perf pass.

**Tests:** ranking returns nearest by cosine; excludes self; respects K; stable ordering;
empty/!indexed vault degrades gracefully (section hidden, no spinner trap).

---

## 10. Track G — Local Graph (neighborhood view) — *optional / heavier*

**What:** a small graph of the current note's neighborhood (1–2 hops of wiki links +
backlinks), rendered natively, nodes click-to-navigate. The reader-scoped complement to the
existing global note-connections graph.

**Why loved:** the local graph is the part of Obsidian's graph view people actually use day
to day (the global graph is mostly admired, rarely navigated).

**How**
- Reuse `Services/Intelligence/NoteConnectionsGraph.swift` (night-shift) but add a
  `neighborhood(of: URL, hops: Int)` that returns a bounded subgraph from `LinkIndex`
  (forward) + `BacklinkIndex` (Track A, reverse). Model-free, so it works without any AI.
- Render `Views/LocalGraphView.swift` with a lightweight **native** force-directed layout
  (SwiftUI `Canvas` + a tiny spring simulation, or reuse the bundled Mermaid path if cheaper
  — **VERIFY** which gives a more native feel at 60fps). Cap node count (e.g. ≤ 40) and stop
  the simulation when settled (battery/calm). Reduce-Motion → static layout.
- Nodes are buttons (navigate on click), VoiceOver-labelled; current note is centered/emphasized.

**Phases:** G1 `neighborhood()` over forward+reverse indexes + tests · G2 native render +
bounded layout · G3 interaction + a11y + Reduce-Motion static mode.

**Tests:** neighborhood respects hop limit and node cap; includes both forward links and
backlinks; excludes unrelated notes; deterministic node set.

> Track G depends on Track A (reverse index) and the night-shift connections-graph code.
> Treat it as a stretch track; ship A–F first.

---

## 11. Considered but excluded / deferred (on the record)

- **Canvas / infinite spatial board** — a creation/editing surface; heavy, hard to keep
  native + 60fps, and off-mission for a reader. Deferred indefinitely.
- **Live preview / WYSIWYG editing** — directly violates the reader-only principle; editing
  stays in the user's chosen editor via "Open in".
- **Properties *editing*** — read-only frontmatter *display* is fine (could be a tiny add to
  Track E or its own micro-track), but editing is out.
- **Sync / publish** — out of scope (local-first); distribution stays maintainer-owned.
- **Arbitrary community plugins** — covered by the separate declarative extensions track, not
  here.

A read-only **Properties header** (render frontmatter as a tidy metadata strip atop a note)
is a low-effort optional add if desired — flag it during Track E.

## 12. Cross-cutting tests & quality gates

- Every track: `swift test` green per phase; new logic in pure, injectable types
  (mirror the existing mock/temp-dir test style).
- No track adds a file-write, network, or non-local code path (grep the diff for
  `URLSession`, `FileManager` write APIs, etc. in review).
- Light snapshot/contrast check of new views in light + dark and at XXS/XXL reader sizes.
- Performance smoke on a large synthetic vault (e.g. 5–10k notes): index build time and
  related-notes/embeds stay off the main thread and within a stated budget.

## 13. Sequencing & milestones

Ship in this order (value × safety × reuse):

1. **A — Linked Mentions** (anchor; unlocks G later).
2. **C — Callouts** (pure render, fast win, high delight).
3. **B — Transclusion** (pure render, high value, builds on the render pass touched in C).
4. **D — Quick Switcher + Command Palette** (navigation; independent).
5. **E — Tags** (surfacing; independent).
6. **F — Related Notes** (the local-intelligence headline; reuses the vector index).
7. **G — Local Graph** (stretch; needs A).

Suggested release framing: A+C+B as a "Connected Reading" minor; D+E as a "Navigate" minor;
F (+optional G) as a "Local Intelligence" minor. Update `CHANGELOG.md (## Unreleased)` and
the per-directory READMEs as each track lands.

## 14. Status ledger (implementing agent updates this)

| Track | Phase | Status | Commit | Tests | Notes |
|-------|-------|--------|--------|-------|-------|
| A Linked Mentions | A1 index+store | ☑ | `Add backlink index foundation for linked mentions` | `swift test` | parser ranges verified; code links ignored |
| A | A2 panel | ☑ | `Show linked mentions in the reader` | `swift test` | hidden when empty; row opens source |
| A | A3 snippets/preview/a11y | ☑ | `Polish linked mention context and accessibility` | `swift test` | heading context; previews; VO labels |
| A | A4 unlinked (opt) | ☐ | | | confirm w/ maintainer |
| B Transclusion | B1 parse | ☑ | `Parse Obsidian embed references` | `swift test` | VERIFY: `WikiLinkParser` + `RichMarkdownBlock` |
| B | B2 resolve+guards | ☑ | `Resolve Obsidian embed slices` | `swift test` | heading/block slices; cycle/depth guards |
| B | B3 render | ☑ | `Render embedded note cards` | `swift test` | native card; recursive rich render; source chip |
| B | B4 perf/a11y | ☑ | `Cache embedded note resolution` | `swift test` | bounded cache; lazy section render; stateful a11y labels |
| C Callouts | C1 parse | ☑ | `Parse Obsidian callout blocks` | `swift test` | render hook verified in `RichMarkdownBlock` |
| C | C2 view+style | ☑ | `Render native callout cards` | `swift test` | semantic styles; nested body render |
| C | C3 fold/a11y | ☑ | `Add foldable callout behavior` | `swift test` | Reduce Motion-aware; a11y state labels |
| D Palettes | D1 fuzzy | ☑ | `Add fuzzy match scoring` | `swift test` | exact/prefix/acronym/scattered; recency tiebreak |
| D | D2 switcher | ☑ | `Add quick switcher overlay` | `swift test` | notes by title/alias/path; recents first; ⌘O |
| D | D3 command palette | ☑ | `Add command palette overlay` | `swift test` | command registry; visible shortcuts; ⌘P |
| D | D4 a11y/focus | ☑ | `Polish palette keyboard focus` | `swift test` | arrow movement; Return/Esc; no keyboard trap |
| E Tags | E1 index | ☑ | `Add read-only tag index` | `swift test` | frontmatter+inline; nested; code/headings ignored |
| E | E2 inline chips | ☐ | | | |
| E | E3 pane | ☐ | | | |
| F Related | F1 query | ☐ | | | |
| F | F2 UI | ☐ | | | |
| F | F3 why (opt) | ☐ | | | |
| F | F4 a11y/perf | ☐ | | | |
| G Local Graph | G1 neighborhood | ☐ | | | stretch |
| G | G2 render | ☐ | | | |
| G | G3 interact/a11y | ☐ | | | |

**Open questions for the maintainer**
1. Block-reference (`^blockid`) support in Track B now, or note-/heading-embeds first?
2. Track F "why related" on-device one-liner: ship behind the AI entitlement, or omit in v1?
3. Track G: native `Canvas` simulation vs reuse the bundled Mermaid renderer?
4. Include the optional read-only Properties header (with Track E)?

## 15. Definition of done (per track)

- [ ] Phases complete; each a DCO-signed commit; `swift test` green.
- [ ] New logic unit-tested (parsing, resolution, ranking) with injected stubs.
- [ ] No file-write / network / cloud path added (verified in review).
- [ ] Native materials; Reduce Motion + Dynamic Type honored; light/dark verified.
- [ ] Per-directory READMEs + `CHANGELOG.md (## Unreleased)` updated.
- [ ] PR links this plan and answers the relevant §14 open questions.
