# Local Runner Unification — Design

> Created: 2026-06-07
> Issue: [#3 — Extend local runner support beyond Intelligence to Chat HUD and all AI entry points](https://github.com/adidshaft/cribble/issues/3)
> Supersedes: `docs/ollama-integration-plan.md` (never implemented; replaced by the
> OpenAI-compatible runner path added in PR #2)

## Problem

PR #2 added OpenAI-compatible local runner support (Ollama, llama.cpp, LM Studio,
custom endpoints), but only the Intelligence engine uses it. The Chat HUD, quick
actions, attachment digestion, Pathfinder explanations, and the AI Link Notes /
README flows still use their older model paths (on-device MLX or claude/codex CLI
spawns). A user who configures Ollama for Intelligence reasonably expects chat and
other AI actions to use the same runner — today they don't.

## Current state (audit)

Two parallel AI stacks exist:

| Stack | Protocol | Used by | Runner support |
|---|---|---|---|
| `IntelligenceProvider` → `OpenAICompatibleProvider` (HTTP `/v1/chat/completions`, non-streaming) | Intelligence background jobs | Intelligence HUD only | Yes (PR #2) |
| `LocalChatEngine` → `MLXChatEngine` / `CLIChatEngine` (streaming, prepare/cancel lifecycle) | Chat HUD, quick actions, attachment digests, Pathfinder on-device | No |
| `AIService` (raw CLI spawn, fixed haiku / gpt-5.5 models) | AI Link Notes, README fill, Pathfinder cloud | No |

Key seam: Chat HUD, quick actions, digests, and Pathfinder all resolve models
through `ModelCatalog` (`LocalModel` / `ModelKind`) → `LocalLLM.shared.engine(for:)`.
Runner config lives in `IntelligenceSettings.localRunnerBaseURL`
(UserDefaults key `intelligence.runnerURL`).

## Approach

Make the local runner a first-class `LocalChatEngine` behind the existing
`ModelCatalog` seam, with a single shared config store. (Alternatives considered:
unifying everything on `IntelligenceProvider` — rejected because it lacks
streaming and prepare/cancel and would force a high-risk refactor of
just-hardened chat reliability code; a minimal `ChatHUDViewModel` patch —
rejected because it loses streaming, hides the runner from the picker, and
scatters provider resolution.)

## Design

### 1. Shared resolution layer: `LocalRunnerStore`

New `@MainActor` singleton in `Services/LocalLLM/`:

- Owns the existing `intelligence.runnerURL` UserDefaults key (same key, same
  format — no migration).
- Adds `localRunner.modelIDs` (cached `/v1/models` probe results) and
  `localRunner.displayName` (e.g. "Ollama") keys so pickers can list models
  without blocking on a probe.
- API: `baseURL: URL?`, `isConfigured: Bool`, `cachedModelIDs: [String]`,
  `displayName: String?`, `refreshModels() async` (probes via the existing
  `OpenAICompatibleProvider.availableModelIDs`).
- `IntelligenceSettings.localRunnerBaseURL` becomes a thin delegate to the store.
  Intelligence behavior is unchanged, but chat and Intelligence can never
  disagree about which runner is configured.

Configuration UI stays in the Intelligence HUD's runner panel — one config
surface for the whole app, per the issue's guidance.

### 2. Runner as a chat engine

- `ModelKind` gains `case localRunner` (`isCloud == false`).
- Runner models surface as dynamic `LocalModel`s: `id: "runner:<modelID>"`,
  `name` = runner model ID, `speedLabel: "Runner"`. `ModelCatalog.runnerModels`
  reads from `LocalRunnerStore`; `ModelCatalog.model(withID:)` resolves
  `runner:` ids.
- New `LocalRunnerChatEngine: LocalChatEngine` in `Services/LocalLLM/`:
  - `prepare(model:)` probes the endpoint (3 s timeout) and captures the runner
    model ID from `model.id`; throws a clear, actionable error when unreachable.
  - `generate(messages:maxTokens:onToken:)` sends
    `POST /v1/chat/completions` with `stream: true`, parses SSE `data:` chunks,
    and emits deltas through `onToken` — real streaming like MLX/CLI. Falls back
    to whole-body parsing when the response isn't SSE.
  - `cancelGeneration()` cancels the in-flight URLSession task.
- `LocalLLM.engine(for:)` (cached per `ModelKind`) works as-is because
  `prepare()` re-captures the endpoint + model on every selection.
- **No silent fallback.** When a runner model is selected and the runner is
  down, generation surfaces the error through the existing `.failed` model
  phase. Chat never quietly reverts to MLX/CLI defaults.

### 3. Entry-point wiring

| Entry point | Change | Status after this work |
|---|---|---|
| Chat HUD | Model picker gains a "LOCAL RUNNER" section (only when configured) listing probed models; selection persists to the existing `chatHUD.selectedModelID` as `runner:<id>`; input-bar chip shows the runner model with its own dot color | Supported |
| Quick actions / slash commands | None — they use chat's selected engine | Supported (inherited) |
| Attachment digestion / summarization | None — uses `currentEngine()` | Supported (inherited) |
| Pathfinder explanation | Model menu gains a "Local runner" section beside On-device / Cloud; same `LocalLLM` path | Supported |
| AI Link Notes / README fill | `AIProviderSheet` gains a "Local runner" provider (visible only when configured); `AIService` gains a runner path sending the same prompts via `OpenAICompatibleProvider` instead of spawning a CLI | Supported |
| EngineChoiceView (first run) | Gains a "Local runner" option when a runner is already configured | Supported |
| Intelligence jobs | None (already supported); config panel now writes through `LocalRunnerStore` | Supported (PR #2) |
| Semantic search / embeddings index | Intentionally unchanged — on-device embeddings, not a generative path | Intentionally unsupported |

### 4. Error handling

- Probe failures: actionable message ("Can't reach <host> — is the runner
  running?") in picker rows, `prepare()` errors, and the AI provider sheet.
- Mid-stream failures: partial text is kept, error surfaces in the existing
  chat error UI, generation marked failed.
- Removed/renamed runner models: stale `runner:<id>` selection still resolves
  to a `LocalModel` (id is self-describing); the runner's 404/400 error is
  surfaced verbatim with the model name.

### 5. Testing

Extending existing `ChatHUDLogicTests` patterns (`injectedEngine` hook) plus a
`URLProtocol` stub for HTTP:

1. Chat HUD resolves a persisted `runner:<id>` selection to
   `LocalRunnerChatEngine` — not the old default — when a runner is configured.
2. Chat HUD does **not** silently fall back to the default model when the
   configured runner errors; the failure is surfaced.
3. `LocalRunnerChatEngine` SSE parsing: streamed chunks assemble into the final
   text; non-SSE responses parse via the fallback.
4. `runner:` model ids round-trip through `ModelCatalog` resolution and
   UserDefaults persistence.
5. `AIService` routes to the runner path when the runner provider is selected
   (the issue's "at least one non-Intelligence AI action" criterion).

## Decisions log

- Shared runner **endpoint**, per-feature **model** choice (chat keeps
  `chatHUD.selectedModelID`; Intelligence keeps `intelligence.modelID`).
- AI Link Notes / README flows get a runner option rather than being documented
  as CLI-only (user decision during design).
- Approach A (runner as `LocalChatEngine`) chosen over protocol unification or
  a minimal view-model patch (user decision during design).
