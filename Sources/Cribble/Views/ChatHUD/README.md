# ChatHUD

The Cribble AI chat panel — a floating HUD (press **Command J**) for asking questions
about the notes you're reading. Backed by [`Services/LocalLLM`](../../Services/LocalLLM).

| File | Responsibility |
| --- | --- |
| `CribbleChatPanel.swift` | The floating panel window + presentation. |
| `ChatHUDView.swift` | Main chat layout. |
| `ChatHUDViewModel.swift` | State, streaming, quick actions, slash commands. |
| `ChatBubbleView.swift` | Renders a single message (with Markdown). |
| `ChatInputBar.swift` | Composer, attachments, `@`-file search. |
| `ChatModelPicker.swift` | Switch between on-device / CLI models. |
| `LLMUnlockSheet.swift` | Local AI unlock flow (App Store IAP). |

Design reference: [docs/CHAT_HUD_DESIGN_HANDOFF.md](../../../../docs/CHAT_HUD_DESIGN_HANDOFF.md).
