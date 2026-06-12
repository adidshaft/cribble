# Intelligence Reliability & UX: Implementation Plan

| Field        | Value                                                  |
|--------------|--------------------------------------------------------|
| Status       | Ready to implement                                     |
| Version      | 1.0                                                    |
| Target       | 1.4.x (no schema migrations, no new artifact types)    |
| Last Updated | 2026-06-12                                             |
| Goal         | Make Cribble Intelligence trustworthy under failure    |

---

## /goal

> **Make Cribble Intelligence trustworthy under failure.** Implement
> `docs/intelligence-reliability-plan.md` end to end, phase by phase, in order.
> After every phase: `swift build` and `swift test` must be green, commit with
> the phase's suggested message, and update the Status Ledger at the bottom of
> the plan file. A user must always be able to answer three questions from the
> Intelligence HUD: *What is it doing right now? What failed and why? How do I
> fix it with one click?* No silent failures, no queue-burning when the
> provider is down, no stale artifacts without a path to freshness.

---

## 1. Problem statement

The intelligence pipeline is robust at *executing* jobs — it has retry/backoff,
bounded execution time, output validation, prose fallbacks, and an idle-aware
scheduler. But it is a **black box when things go wrong**:

- Jobs persist `error_message` and `attempt_count` in SQLite, and
  `IntelligenceDatabase.jobs(projectID:status:)` can already query them — yet
  the engine publishes only a `pendingJobs` count and a one-line
  `lastActivity`. **Failed jobs are invisible, unexplained, and unretryable
  from the UI.**
- `IntelligenceProvider.checkAvailability()` exists but is not used as a
  preflight gate. When the model isn't downloaded, the CLI is unauthenticated,
  or the local runner is offline, the drain loop dequeues model jobs anyway and
  each one throws `providerUnavailable` — **burning attempts and producing
  noise instead of one clear diagnosis**.
- During a drain the user sees only "Processing". **There is no per-job
  activity**, even though the runner knows exactly which file it is working on.
- "N artifacts may be stale" is a **dead-end label** — there is no way to see
  *which* artifacts or refresh one.
- Enabling intelligence with no model downloaded **looks like nothing is
  happening**: deterministic artifacts trickle in while model jobs wait
  silently.

Generation *quality* is mostly model-bound; **trust is product-bound**. Fixing
the feedback loop improves every persona and every future intelligence feature
without touching prompts or schemas.

## 2. Ground rules

- **Build/test loop:** `swift build` and `swift test` from the repo root. Both
  must be green at every commit. The app can be launched for manual checks with
  `bash script/build_and_run.sh` (`--verify` for a smoke test).
- **Commit cadence:** one commit per phase (plus fixups if needed), using the
  suggested message. Update the Status Ledger (§10) in the same commit.
- **No schema migrations.** The `jobs` table already has `status`,
  `attempt_count`, and `error_message`. Only additive *queries* are allowed.
- **No new artifact types, no prompt changes, no UI redesign.** Reuse the HUD's
  existing card styling (`Color.white.opacity(0.05–0.06)` backgrounds,
  `RoundedRectangle(cornerRadius: 10)`, 10–12 pt fonts) and the existing
  retry/backoff machinery.
- **Pure logic in pure types.** Anything mappable/explainable must be a pure
  function or value type with unit tests, following the codebase's pattern
  (e.g. `BackgroundScheduler.decision(for:)`, `OutputValidator`).

## 3. Files to read first

| File | Why |
|---|---|
| `Sources/Cribble/Services/Intelligence/IntelligenceEngine.swift` | MainActor coordinator. Publishes `status`, `pendingJobs`, `lastActivity`, `resourceDecision`, `performanceMode`. Owns the tick loop (`scan → enqueueAggregateJobs → drain`). |
| `Sources/Cribble/Services/Intelligence/JobRunner.swift` | Executes jobs. `JobRunnerError` taxonomy exists (`providerUnavailable`, `missingInput`, `emptyOutput`, `validationFailed`, `unsupportedJobType`). `drain(limit:allowedTier:)` and `runNext` are the entry points. |
| `Sources/Cribble/Services/Intelligence/IntelligenceDatabase.swift` | SQLite actor. `jobs(projectID:status:)`, `pendingJobCount`, `staleArtifactCount` exist. |
| `Sources/Cribble/Services/Intelligence/IntelligenceProvider.swift` | `checkAvailability() -> ProviderAvailability` on every provider. |
| `Sources/Cribble/Services/Intelligence/OpenAICompatibleProvider.swift` | The local-runner provider; its availability check probes the endpoint. |
| `Sources/Cribble/Services/Intelligence/IntelligenceModels.swift` | `IntelligenceJob` (has `attemptCount`, `maxAttempts`, `errorMessage`), `IntelligenceJobType.requiresProvider`. |
| `Sources/Cribble/Views/IntelligenceHUD/IntelligenceHUDView.swift` | Feed tab, Project Pulse card, `metricTile`, `sectionHeader`, `emptyState`, model-picker overlay. |
| `Sources/Cribble/Views/IntelligenceHUD/ArtifactBodyView.swift` | Artifact reader (Phase 4 inline staleness bar). |
| `Tests/CribbleTests/IntelligenceEngineTests.swift`, `IntelligenceJobsTests.swift` | Existing patterns: `MockIntelligenceProvider`, in-memory DB fixtures. |

---

## 4. Phase 1 — Provider preflight gate (reliability)

**Problem.** With an unusable provider, the drain loop still dequeues model
jobs; each throws `providerUnavailable`, consuming `attempt_count` and filling
the log.

**Implement.**

1. **One availability check per tick.** In the engine's tick, before draining,
   call `provider.checkAvailability()` at most once and cache the result for
   that tick. Skip the call entirely when there are no pending provider jobs.
2. **Deterministic-only drain when unavailable.** `JobRunner.drain` /
   `runNext` already have a partial `providerUsable` mechanism — verify and
   complete it so that when the provider is unusable:
   - jobs with `requiresProvider == false` still run;
   - jobs with `requiresProvider == true` are **skipped, not failed** —
     `attempt_count` must not change, status stays `pending`.
3. **Published health.** Add to `IntelligenceEngine`:

   ```swift
   enum ProviderFix: Equatable {
       case downloadModel(LocalModel)
       case openModelPicker
       case startLocalRunner(name: String, url: String)
       case authenticateCLI(name: String, command: String)   // e.g. "claude login"
   }
   enum ProviderHealth: Equatable {
       case ready
       case unavailable(reason: String, fix: ProviderFix)
   }
   @Published private(set) var providerHealth: ProviderHealth = .ready
   ```

   Derive `fix` from the provider kind + the `ProviderAvailability` reason:
   MLX model not on disk → `.downloadModel` (or `.openModelPicker` if the
   selected model id can't be resolved); local runner unreachable →
   `.startLocalRunner` with its display name and base URL; CLI engines →
   `.authenticateCLI`.
4. **Re-check on configuration change.** `setModel` / `setLocalRunner` already
   call `rebuildRunner()` — refresh `providerHealth` there and nudge the loop.

**Tests** (extend `IntelligenceJobsTests` / `IntelligenceEngineTests`):
- Unavailable provider + mixed queue → deterministic jobs complete; provider
  jobs remain `pending` with unchanged `attemptCount`.
- Availability flips to available → the next tick drains the held jobs.
- `ProviderFix` derivation per provider kind (pure-function tests).

**Commit:** `Gate intelligence drains on provider health`

---

## 5. Phase 2 — Failure ledger + one-click recovery (UX core)

**Problem.** Failed jobs are stored but invisible; the only user-facing signal
is a stale-artifact count.

**Implement.**

1. **Database** (`IntelligenceDatabase`, additive queries only):

   ```swift
   func failedJobs(projectID: String) -> [IntelligenceJob]   // status == .failed, newest first; reuse jobs(projectID:status:)
   func retryJob(id: String)        // status -> pending, attempt_count -> 0, error_message -> NULL
   func dismissJob(id: String)      // status -> cancelled
   ```

2. **Engine:**

   ```swift
   @Published private(set) var failedJobs: [IntelligenceJob] = []
   func retryFailedJob(id: String) async
   func retryAllFailed() async
   func dismissFailedJob(id: String) async
   ```

   Refresh `failedJobs` everywhere `pendingJobs` is refreshed. Retry methods
   update the DB then nudge the loop (same pattern as `runNow`).
3. **Failure explainer** — new file
   `Sources/Cribble/Services/Intelligence/JobFailureExplainer.swift`, a pure
   mapper:

   ```swift
   struct JobFailureExplanation: Equatable {
       let summary: String          // one user-readable sentence
       let suggestion: Suggestion   // .retry, .providerFix, .skipFile(String)
   }
   enum JobFailureExplainer {
       static func explain(type: IntelligenceJobType, errorMessage: String?) -> JobFailureExplanation
   }
   ```

   Mappings (match on the stable substrings produced by `JobRunnerError`):
   - `validationFailed` → "The model's output didn't pass Cribble's checks." → `.retry`
   - `providerUnavailable` → "The AI engine wasn't reachable." → `.providerFix`
   - timeout / bounded-execution text → "This took too long — the file may be very large." → `.retry`
   - `emptyOutput` → "The model returned nothing for this file." → `.retry`
   - `missingInput` → "The source file moved or was deleted." → `.skipFile(path)`
   - unknown → generic sentence → `.retry`
4. **HUD — "Needs attention" section** in the feed tab, directly below the
   Project Pulse card, visible only when `failedJobs` is non-empty:
   - Header: `sectionHeader("NEEDS ATTENTION")` + a small "Retry all" button.
   - One row per failed job (cap visible rows at 8, "…and N more" beneath):
     type icon (reuse `IntelligenceArtifactType.icon` mapping where sensible,
     else a per-jobtype SF Symbol), the first `inputPaths` entry's last path
     component, the explainer sentence, and two inline buttons **Retry** /
     **Dismiss**.
   - Project Pulse: add an orange chip `"<N> need attention"` (reuse
     `pulseChip`) when N > 0.

**Tests:**
- Mock provider that always fails → after `maxAttempts` the job appears in
  `failedJobs`; `retryFailedJob` resets it and a now-succeeding provider
  completes it; `dismissFailedJob` removes it.
- `JobFailureExplainer` mapping table (pure unit tests, one per case).

**Commit:** `Surface failed intelligence jobs with one-click retry`

---

## 6. Phase 3 — Live activity: what is it doing right now

**Problem.** During a drain the status pill says only "Processing".

**Implement.**

1. **Runner → engine callback.** Give `JobRunner` an optional
   `onJobStart: (@MainActor @Sendable (IntelligenceJob) -> Void)?` invoked when
   a job transitions to `running` (an `AsyncStream` is also acceptable; pick
   whichever fits the actor isolation more cleanly).
2. **Engine publishes:**

   ```swift
   @Published private(set) var currentJobDescription: String?
   ```

   Set from a pure verb mapper (put it next to the explainer or as an extension
   on `IntelligenceJobType`): `analyzeFile`/`summarizeFile` → "Summarizing
   <file>", `buildGlossary` → "Building glossary (<n> documents)",
   `detectContradictions` → "Checking for contradictions", `summarizeCommit` →
   "Summarizing commit <short-sha>", etc. Clear it when the drain returns.
3. **HUD:**
   - Status pill: when `status == .working` and `currentJobDescription != nil`,
     show the description instead of generic text.
   - Project Pulse: "X queued" becomes "X queued · <description>" while running.
4. **Provider-health banner.** When `providerHealth != .ready`, show one banner
   row at the top of the feed tab: warning icon + reason + a single action
   button that executes the `ProviderFix`:
   - `.downloadModel` → trigger the existing model-download affordance;
   - `.openModelPicker` → `showModelPicker = true`;
   - `.startLocalRunner` → open the existing local-runner config inline;
   - `.authenticateCLI` → show the command with a **Copy** button
     (`NSPasteboard`), no terminal automation.
   Everything inline in the HUD — no new windows or sheets.

**Tests:**
- Slow mock provider → `currentJobDescription` is non-nil while generating and
  nil after the drain.
- Verb-mapper unit tests per job type.

**Commit:** `Show live per-job intelligence activity and provider-health banner`

---

## 7. Phase 4 — Stale artifacts become actionable

**Problem.** "N artifacts may be stale" has no detail and no remedy.

**Implement.**

1. **Database:** `staleArtifacts(projectID:) -> [IntelligenceArtifact]` —
   mirror the existing `staleArtifactCount` query, returning the rows whose
   `sourceHashes` no longer match current file hashes.
2. **Engine:** `func refreshArtifact(id: String) async`:
   - per-file artifact types (`fileSummary`, `fallbackAudit`, `ioBehavior`) →
     re-enqueue the producing job (`analyzeFile` for code, `summarizeFile` for
     prose) for the artifact's source path with fresh input hash;
   - aggregate types (`projectIndex`, `glossary`, `timeline`,
     `contradictionReport`, diagrams, `connectionsGraph`) → clear that type's
     entry in `lastAggregateJobSignatures` and call `enqueueAggregateJobs()`;
   - then nudge the loop. Also add `refreshAllStale()`.
3. **HUD:**
   - The existing stale-warning row becomes expandable: clicking it reveals the
     stale artifacts, each with **Refresh**; header gets **Refresh all**.
   - `ArtifactBodyView`: when the displayed artifact is in the stale set, show
     a slim inline bar — "Built from an older version of the source" with a
     **Refresh** button.

**Tests:**
- Mutate a tracked file's hash in the DB → artifact appears in
  `staleArtifacts`; `refreshArtifact` enqueues the correct job type; completing
  it clears staleness.

**Commit:** `Make stale artifacts visible and refreshable`

---

## 8. Phase 5 — First-run experience polish

**Problem.** Enabling intelligence with no model downloaded looks inert.

**Implement.**

1. On enable, immediately run the Phase-1 availability check so
   `providerHealth` (and its banner with the fix) shows *before* the user
   wonders why nothing is happening.
2. Progressive empty-state copy for the Artifacts tab, derived from published
   state via a pure helper (unit-testable):
   - scanning → "Reading your folder — <filesIndexed> files so far";
   - summarizing → "Analyzing <done> of <filesIndexed> files" (done = count of
     `fileSummary` artifacts, already computed for Project Pulse);
   - provider blocked → defer to the provider-health banner copy;
   - complete → existing empty-state/default behavior.
   Reuse the existing `emptyState(icon:title:detail:)` helper.

**Tests:**
- Engine with unavailable provider sets `providerHealth` on enable.
- Empty-state copy helper unit tests across the four states.

**Commit:** `Guide the first intelligence run with live progress copy`

---

## 9. Manual acceptance checklist

Run `bash script/build_and_run.sh`, open a folder, enable intelligence:

- [ ] Select a non-downloaded on-device model (or stop Ollama) → banner
      explains the problem and offers the fix; deterministic artifacts still
      build; pending model jobs do not accumulate attempts.
- [ ] Force failures (e.g. unauthenticated CLI) → "Needs attention" rows with
      readable reasons; **Retry** works after fixing auth; **Dismiss** clears.
- [ ] During a run, the status pill names the current file/aggregate.
- [ ] Edit a summarized file externally → stale list appears; **Refresh**
      rebuilds that artifact; the artifact reader shows the inline stale bar.
- [ ] Fresh enable with no model → progressive copy, never a silent blank tab.
- [ ] `bash script/build_and_run.sh --verify` exits 0.

## 10. Status Ledger (update per phase, same commit)

| Phase | Description | Status | Commit |
|-------|-------------|--------|--------|
| 1 | Provider preflight gate | ☑ | `Gate intelligence drains on provider health` |
| 2 | Failure ledger + retry | ☐ | — |
| 3 | Live activity + health banner | ☐ | — |
| 4 | Actionable stale artifacts | ☐ | — |
| 5 | First-run polish | ☐ | — |

## 11. Non-goals

- No new artifact types, prompts, or schema migrations.
- No redesign of the Intelligence HUD; reuse existing styling and components.
- No background daemons, notifications, or terminal automation (CLI auth is
  copy-the-command only).
- No changes to the retry/backoff or scheduler policy beyond the preflight
  gate and attempt-preserving skip.
