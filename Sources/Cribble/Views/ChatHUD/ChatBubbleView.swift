import SwiftUI
import Textual

/// A single chat turn. User turns are right-aligned tinted bubbles with file
/// badges; assistant turns are left-aligned with Markdown rendering and a
/// streaming caret.
struct ChatBubbleView: View, Equatable {
    let message: ChatMessage
    var viewModel: ChatHUDViewModel?

    /// Diff on the message alone. `viewModel` is identity-stable for the panel's
    /// lifetime, so excluding it lets `.equatable()` skip re-rendering every
    /// settled bubble when only the streaming turn's text changes.
    nonisolated static func == (lhs: ChatBubbleView, rhs: ChatBubbleView) -> Bool {
        lhs.message == rhs.message
    }

    private var showActions: Bool {
        message.role == .assistant && !message.isStreaming && !message.text.isEmpty && viewModel != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if !message.attachments.isEmpty {
                    attachmentBadges
                }
                bubble
                if showActions { actions }
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            BubbleAction(icon: "doc.on.doc", help: "Copy") {
                viewModel?.copyMessage(message)
            }
            BubbleAction(icon: "doc.badge.plus", help: "Save as new note") {
                viewModel?.saveMessageAsNote(message)
            }
            if viewModel?.canInsertIntoCurrentNote == true {
                BubbleAction(icon: "text.insert", help: "Insert into current note") {
                    viewModel?.insertMessageIntoCurrentNote(message)
                }
            }
        }
        .padding(.leading, 2)
        .padding(.top, 1)
    }

    private var bubble: some View {
        Group {
            if message.text.isEmpty && message.isStreaming {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Thinking…")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else if message.role == .assistant && !message.isStreaming {
                // Settled assistant turns get full GitHub-flavored block Markdown
                // (headings, lists, tables, fenced code) via the same Textual
                // pipeline the reader uses. Forced to the dark scheme so GitHub's
                // adaptive colors resolve to their light-on-dark variants — the
                // HUD bubble is always dark regardless of system appearance.
                StructuredText(markdown: message.text)
                    .font(.system(size: 13))
                    .textual.structuredTextStyle(.gitHub)
                    .textual.textSelection(.enabled)
                    .environment(\.colorScheme, .dark)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // User turns, and assistant turns still streaming: fast inline
                // text (no block parse) with the streaming caret.
                let textContent = Text(renderedText)
                let styled = Group {
                    if message.isStreaming {
                        textContent + Text(" ▍")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.accentColor)
                    } else {
                        textContent
                    }
                }
                .font(.system(size: 13))
                selectableWhenSettled(styled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleBackground)
        .foregroundStyle(message.role == .user ? .white : .white.opacity(0.95))
    }

    /// Text selection rebuilds an expensive layout collection for the whole
    /// transcript; only enable it once a turn has settled so it doesn't run on
    /// every streamed token. (A ternary won't work here — `.enabled`/`.disabled`
    /// are different concrete `TextSelectability` types.)
    @ViewBuilder
    private func selectableWhenSettled<V: View>(_ view: V) -> some View {
        if message.isStreaming {
            view
        } else {
            view.textSelection(.enabled)
        }
    }

    /// Lightweight Markdown rendering for inline emphasis / code / links. Falls
    /// back to the raw string when the Markdown can't be parsed.
    ///
    /// While a turn is streaming we render the raw string with no Markdown parse:
    /// the text changes on every token, so parsing here would re-run the parser
    /// hundreds of times per answer (and mid-stream Markdown is often malformed
    /// anyway). The parse — memoized by text — runs once the turn settles.
    private var renderedText: AttributedString {
        if message.isStreaming {
            return AttributedString(message.text)
        }
        return Self.renderMarkdown(message.text)
    }

    /// Process-wide cache of parsed Markdown, keyed by the exact source string,
    /// so a settled bubble parses once no matter how often its `body` re-runs.
    private static let markdownCache = NSCache<NSString, NSAttributedStringBox>()

    private static func renderMarkdown(_ text: String) -> AttributedString {
        let key = text as NSString
        if let cached = markdownCache.object(forKey: key) {
            return cached.value
        }
        let rendered = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        markdownCache.setObject(NSAttributedStringBox(rendered), forKey: key)
        return rendered
    }

    /// Boxes an `AttributedString` (a value type) so it can live in `NSCache`.
    private final class NSAttributedStringBox {
        let value: AttributedString
        init(_ value: AttributedString) { self.value = value }
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: 16,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 4,
                topTrailingRadius: 16
            )
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.95), Color.accentColor],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                }
        } else {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: 4,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: 16
            )
            shape
                .fill(Color.white.opacity(0.06))
                .overlay {
                    shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                }
        }
    }

    private struct BubbleAction: View {
        let icon: String
        let help: String
        let action: () -> Void
        @State private var hovered = false

        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(hovered ? 0.95 : 0.45))
                    .frame(width: 22, height: 20)
                    .background(Color.white.opacity(hovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(help)
            .onHover { hovered = $0 }
            .pointingHandOnHover()
        }
    }

    private var attachmentBadges: some View {
        HStack(spacing: 6) {
            ForEach(message.attachments) { token in
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue.opacity(0.9))
                    Text(token.displayName)
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .overlay {
                    Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.75)
                }
                .clipShape(Capsule())
                .pointingHandOnHover()
            }
        }
    }
}
