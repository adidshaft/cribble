import SwiftUI

/// A single chat turn. User turns are right-aligned tinted bubbles with file
/// badges; assistant turns are left-aligned with Markdown rendering and a
/// streaming caret.
struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user { Spacer(minLength: 32) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                if !message.attachments.isEmpty {
                    attachmentBadges
                }
                bubble
            }

            if message.role == .assistant { Spacer(minLength: 32) }
        }
    }

    private var bubble: some View {
        Group {
            if message.text.isEmpty && message.isStreaming {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                Text(renderedText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .foregroundStyle(.white.opacity(message.role == .user ? 1 : 0.92))
    }

    /// Lightweight Markdown rendering for inline emphasis / code / links. Falls
    /// back to the raw string when the Markdown can't be parsed.
    private var renderedText: AttributedString {
        (try? AttributedString(
            markdown: message.text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.text)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if message.role == .user {
            Color.accentColor.opacity(0.85)
        } else {
            Color.white.opacity(0.08)
        }
    }

    private var attachmentBadges: some View {
        HStack(spacing: 6) {
            ForEach(message.attachments) { token in
                Label(token.displayName, systemImage: "doc.text")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
        }
    }
}
