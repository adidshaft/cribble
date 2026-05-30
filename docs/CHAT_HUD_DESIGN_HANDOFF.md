# Antigravity Handoff — Cribble Local Chat HUD (1.2.0) Visual Layer

The **entire functional system is already built and compiling** (MLX on-device
engine, floating panel, `@file` tagging, streaming, StoreKit IAP gate, safe
diff/create routing, tests). Your job is **pure visual craft** — make the HUD
look like the mockup (thin borders, dark gradient, glassmorphism, 1:2 floating
profile) **without changing any behavior**.

## ✅ You may edit ONLY these 4 files (presentation only)

| File | What to restyle |
| --- | --- |
| `Sources/Cribble/Views/ChatHUD/ChatHUDView.swift` | Header bar, empty-state greeting, transcript layout |
| `Sources/Cribble/Views/ChatHUD/ChatBubbleView.swift` | User/assistant bubbles, file-attachment badges, streaming caret |
| `Sources/Cribble/Views/ChatHUD/ChatInputBar.swift` | Pill input, `+` button, model "Flash" chip, mic, autocomplete popover, attachment capsules, send/stop |
| `Sources/Cribble/Views/ChatHUD/LLMUnlockSheet.swift` | The `$6.99` unlock sheet |

## ⛔ DO NOT TOUCH (this is where "nothing breaks" lives)

- `ChatHUDViewModel.swift`, `CribbleChatPanel.swift`, anything in
  `Services/LocalLLM/`, and every other file in the repo.
- Do **not** add `@State` logic, networking, file IO, model calls, or change any
  method signature / published property name. Bind to the contract below as-is.
- Do **not** rename SF Symbols used as functional affordances without keeping the
  same action wired.

## The view-model contract (read/call these; invent nothing)

`@ObservedObject var viewModel: ChatHUDViewModel` exposes:

**Read (drive the UI):**
- `messages: [ChatMessage]` — each has `.role` (`.user`/`.assistant`), `.text`,
  `.attachments: [TaggedFileToken]`, `.isStreaming`
- `draft: String`, `attachments: [TaggedFileToken]`, `isGenerating: Bool`
- `autocomplete: FileAutocompleteState?` (`.matches: [TaggedFileToken]`)
- `selectedModel: LocalModel` (`.name`, `.speedLabel`, `.approximateSize`)
- `modelPhase` — `.idle / .downloading(Double) / .loading / .ready / .failed(String)`
- `statusMessage: String?`, `greetingName: String`, `hasConversation`, `canSend`
- `quickAttachFiles: [TaggedFileToken]`, `ModelCatalog.all`

**Call (on user actions):**
- `updateDraft(_:)` (bind the text field through this — it powers `@` detection)
- `send()`, `cancel()`, `newChat()`
- `applyAutocomplete(_:)`, `dismissAutocomplete()`
- `addAttachment(_:)`, `removeAttachment(_:)`, `selectModel(_:)`

`TaggedFileToken.displayName` is the label for chips/badges.

## Design goals (from the spec mockup)

- **Window**: 1:2 portrait, ~380×720 default. Backdrop is already a dark
  `.hudWindow` `NSVisualEffectView` with a 16pt corner radius (set in
  `CribbleChatPanel`, don't touch). Add SwiftUI gradient/stroke *inside* the
  views for the "thin border + dark gradient" feel.
- **Header**: traffic-light safe area is already padded (`.padding(.top, 18)`).
  Optional center segmented picker is a styling slot — keep `newChat()`/close
  wired.
- **Empty state**: "Hi {greetingName}, What's on your mind?" — soft, centered,
  large typographic styling.
- **Bubbles**: user = right-aligned tinted; assistant = left-aligned glass.
  Render `message.text` with the existing `AttributedString(markdown:)` (or wire
  the project's `Textual` renderer for code blocks — visual only). Show a caret
  while `isStreaming`.
- **Attachment tokens**: inline capsules (`.background(Capsule())`), removable.
- **Input pill**: `+` (attach menu), expanding editor, model chip showing
  `selectedModel.speedLabel` (e.g. "Flash"), mic, circular send/stop.
- Keep it **hardware-accelerated & lightweight**: prefer `.background`,
  `drawingGroup()` where useful, avoid per-token full-list re-renders.

## How to verify your work

```bash
swift build          # must stay green
swift test --filter ChatHUDLogicTests   # must stay green (you changed no logic)
```

Then run the app, open the HUD via the toolbar "Cribble AI" button or ⌥⌘C.

## Notes / open visual decisions you can make

- The center segmented picker in the header is currently omitted; add it as a
  styled, non-functional segment group or repurpose for future tabs.
- Dictation mic is a visual placeholder (no action yet) — style it disabled.
- Model chip menu copy/iconography is yours to refine.
