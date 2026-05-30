import SwiftUI

/// Root of the Local Chat HUD. Three stacked regions: header, scrolling
/// transcript, and the footer input bar. Visuals are intentionally restrained —
/// this is the layer safe to restyle without touching `ChatHUDViewModel`.
struct ChatHUDView: View {
    @ObservedObject var viewModel: ChatHUDViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            transcript
            ChatInputBar(viewModel: viewModel)
        }
        .frame(minWidth: 320, minHeight: 480)
        .background(Color.black.opacity(0.18))
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.white.opacity(0.85))
            Text("Cribble AI")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button {
                viewModel.newChat()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGenerating || !viewModel.hasConversation)
            .help("New chat")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .padding(.top, 18) // clear the hidden titlebar / traffic-light region
        .contentShape(Rectangle())
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    ChatEmptyState(name: viewModel.greetingName)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(viewModel.messages) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
            }
            .onChange(of: viewModel.messages.last?.text) {
                guard let last = viewModel.messages.last else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Soft welcome shown before the first message.
struct ChatEmptyState: View {
    let name: String

    var body: some View {
        VStack(spacing: 8) {
            Text("Hi \(name),")
                .font(.system(size: 22, weight: .semibold))
            Text("What's on your mind?")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
        }
        .multilineTextAlignment(.center)
    }
}
