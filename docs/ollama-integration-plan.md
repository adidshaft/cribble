# Ollama Local LLM Integration — Implementation Plan

> Created: 2026-05-27  
> Goal: Add Ollama as a first-class AI provider so users can run all AI features locally without needing a Claude or Codex account.

---

## New Files

### `Sources/Cribble/Services/OllamaClient.swift`
- `struct OllamaClient` — lightweight `URLSession`-based HTTP client for `http://127.0.0.1:11434`
- `func isRunning() async -> Bool` — `GET /api/tags` with 3s timeout; used for live status checks
- `func availableModels() async throws -> [String]` — returns installed model names from `/api/tags`
- `func generate(model:prompt:systemPrompt:) async throws -> String` — `POST /api/generate` with `stream: false`; decodes `{response: "..."}`
- `enum OllamaError: LocalizedError` — `.notRunning`, `.modelNotFound(String)`, `.httpError(Int, String)` with human-readable descriptions pointing to `ollama serve` / `ollama pull`

---

### `Sources/Cribble/Views/DocumentSummarySheet.swift`
- Presented as a sheet when user triggers "Summarize Note"
- On appear: immediately calls `OllamaClient.generate` with 2-3 sentence system prompt + first 8 000 chars of `document.rawContent`
- States: loading spinner → summary text → error message with retry button
- Footer: Copy button (writes to `NSPasteboard`) + Dismiss + Retry

---

## Modified Files

### `Sources/Cribble/Services/AIService.swift`
- Add `.ollama` to `AIProvider` enum; `lowestModelName` returns `"llama3.2:3b"` (unused for Ollama — model comes from `AppSettings`)
- Add `buildVaultContext(for:maxChars:) throws -> String` — enumerates `.md` files, sorts by size ascending, concatenates `=== relative/path.md ===\n<content>\n\n` until 32 000 char budget is exhausted
- New Ollama case in `generateLinkPatch`: pre-flight `isRunning()` check → build vault context → call `OllamaClient.generate` with file-context-injected prompt → parse output through existing `UnifiedDiffParser`
- Adapted prompts for `suggestLinks` and `updateReadme` that include `<vault>…</vault>` XML tags and explicit "output unified diff only" instruction

### `Sources/Cribble/Models/AppSettings.swift`
- `@Published var ollamaModel: String` — default `"llama3.2:3b"`, persisted to `UserDefaults`
- `@Published var ollamaBaseURL: String` — default `"http://127.0.0.1:11434"`, persisted — lets power users point to a remote instance

### `Sources/Cribble/Views/AIProviderSheet.swift`
- Add Ollama as third provider button alongside Codex / Claude
- On `.task`: fire `OllamaClient.isRunning()` + `availableModels()` and store in `@State var ollamaStatus: OllamaStatus` (enum: `.checking`, `.ready([String])`, `.offline`)
- Ollama button shows: green dot + model name if ready; gray dot + "Not running" if offline (button still tappable — error surfaces after they click)
- Small "?" help tooltip: "Run `ollama serve` in Terminal. Pull a model with `ollama pull llama3.2:3b`"

### `Sources/Cribble/Views/SettingsView.swift`
- New `Section("AI / Ollama")` containing:
  - `TextField("Server URL", text: $settings.ollamaBaseURL)`
  - `TextField("Model", text: $settings.ollamaModel)` with placeholder `"llama3.2:3b"`
  - Live status indicator that fires `OllamaClient.isRunning()` on appear
  - "Recommended models" inline help text listing Qwen2.5:3b / llama3.2:3b / phi4-mini

### `Sources/Cribble/Views/ContentView.swift`
- `@State private var showingSummarySheet = false`
- Wire `showingSummarySheet` to a `.sheet` presenting `DocumentSummarySheet`
- Add "Summarize" toolbar button (brain/sparkles icon) in `primaryToolbar`; disabled when `library.selectedDocument == nil`
- Add `focusedSceneValue(\.summarizeDocumentAction, { showingSummarySheet = true })`

### `Sources/Cribble/App/CribbleCommands.swift`
- Add `@FocusedValue(\.summarizeDocumentAction)`
- New button in `CommandMenu("Reading")`: "Summarize Note" with shortcut `⌘⇧S`
- Add `SummarizeDocumentActionKey` + `FocusedValues` extension (same boilerplate pattern as existing keys)

---

## Feature Summary

| Feature | Where | Requires Ollama Running |
|---|---|---|
| AI Link Notes (existing modes) | AI Provider Sheet → Ollama button | Yes |
| Summarize Note | Reader toolbar + ⌘⇧S | Yes |
| Live Ollama status | AI Provider Sheet + Settings | Yes |
| Model / URL config | Settings → AI section | No |

---

## Recommended Models

| Model | Size | Speed (M-series) | Best for |
|---|---|---|---|
| `qwen2.5:3b` | 1.9 GB | ~90 tok/s | Fastest; good at markdown/structured output |
| `llama3.2:3b` | 2.0 GB | ~80 tok/s | General reasoning, link suggestions |
| `phi4-mini` | 2.5 GB | ~70 tok/s | Instruction following, structured output |
| `gemma3:4b` | 2.5 GB | ~65 tok/s | Long context (128K), good for large vaults |

Default: `llama3.2:3b`

---

## Implementation Sequence

1. `OllamaClient.swift` — foundation everything else depends on
2. `AppSettings.swift` — add `ollamaModel` / `ollamaBaseURL` properties
3. `AIService.swift` — add `.ollama` case + vault context builder
4. `DocumentSummarySheet.swift` — self-contained, no dependencies except OllamaClient
5. `AIProviderSheet.swift` — update UI with status indicator
6. `SettingsView.swift` — add AI section
7. `CribbleCommands.swift` — add summarize keyboard shortcut
8. `ContentView.swift` — wire toolbar button + sheet presentation

---

## Future Ideas (Post-MVP)

- **Semantic vault search** — embed notes with `nomic-embed-text` via Ollama, store vectors in SQLite, answer "find notes about X" queries entirely offline
- **Smart orphan detection** — feed note titles + current doc to model; ask which notes this doc should link to but doesn't
- **Ask Vault** command — Q&A over the vault using stuffed context (RAG-lite, no embeddings needed for small vaults)
- **Inline writing assist** — suggest a continuation sentence or rephrase for selected text
