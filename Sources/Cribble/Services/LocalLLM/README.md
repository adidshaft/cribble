# LocalLLM

The Cribble AI chat backend. Answers run **on-device** via MLX, or through a
locally installed Claude / Codex CLI — never a hosted Cribble service.

| File | Responsibility |
| --- | --- |
| `LocalChatEngine.swift` | Protocol + coordinator the chat UI talks to. |
| `MLXChatEngine.swift` | On-device inference using MLX models. |
| `CLIChatEngine.swift` | Streams answers from a local Claude/Codex CLI. |
| `ChatOutputParser.swift` | Parses streamed tokens (UTF-8 chunk-safe). |
| `ContextAssembler.swift` | Builds vault-aware context from the current notes. |
| `ChatModels.swift` | Chat message / session value types. |
| `QuickAction.swift` | Predefined prompts (summarize, explain, link…). |
| `ModelCatalog.swift` | Known downloadable models + metadata. |
| `ModelInventory.swift` | Tracks installed models and download progress. |
| `LLMEntitlementStore.swift` | Local AI unlock state (DMG unlocked; App Store IAP). |
| `LocalLLM.swift` | Shared entry points and configuration. |

See [`Views/ChatHUD`](../../Views/ChatHUD) for the UI and the
[Chat HUD design handoff](../../../../docs/CHAT_HUD_DESIGN_HANDOFF.md).

## Local runner support (issue #3)

`LocalRunnerStore` is the app-wide source of truth for the OpenAI-compatible
runner (Ollama, llama.cpp, LM Studio, …). Configure it once from the
Intelligence HUD's model menu; every eligible AI feature resolves it from the
store.

| AI entry point | Runner support | Path |
|---|---|---|
| Chat HUD | Supported | `ModelKind.localRunner` → `LocalRunnerChatEngine` (streaming SSE) |
| Quick actions (slash commands) | Supported | inherits chat's selected engine |
| Attachment digestion | Supported | inherits chat's selected engine |
| Pathfinder explanation | Supported | runner section in the model menu |
| AI Link Notes / README fill | Supported | `AIProvider.localRunner` → `OpenAICompatibleProvider` with inlined vault context |
| First-run engine chooser | Supported | runner card shown when configured |
| Intelligence jobs | Supported (PR #2) | `OpenAICompatibleProvider` |
| Semantic search / embeddings | Intentionally unsupported | on-device embedding index, not a generative path |
