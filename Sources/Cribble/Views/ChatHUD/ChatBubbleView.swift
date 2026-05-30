import SwiftUI

/// A single chat turn. User turns are right-aligned tinted bubbles with file
/// badges; assistant turns are left-aligned with Markdown rendering and a
/// streaming caret.
struct ChatBubbleView: View {
    let message: ChatMessage
    var viewModel: ChatHUDViewModel?
    @State private var caretVisible = true

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
            } else {
                let textContent = Text(renderedText)
                Group {
                    if message.role == .assistant && message.isStreaming {
                        textContent + Text(" ▍")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color.accentColor.opacity(caretVisible ? 1.0 : 0.15))
                    } else {
                        textContent
                    }
                }
                .font(.system(size: 13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(bubbleBackground)
        .foregroundStyle(message.role == .user ? .white : .white.opacity(0.95))
        .onAppear {
            if message.role == .assistant && message.isStreaming {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    caretVisible = false
                }
            }
        }
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
                .cribbleGlass(in: shape)
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
