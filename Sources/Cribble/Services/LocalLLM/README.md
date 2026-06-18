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

Reader-side related-note explanations use this stack only when the entitlement
is unlocked and a local MLX model is already downloaded; cloud CLI models are
not used for that inline reader feature.

See [`Views/ChatHUD`](../../Views/ChatHUD) for the UI and the
[Chat HUD design handoff](../../../../docs/CHAT_HUD_DESIGN_HANDOFF.md).
