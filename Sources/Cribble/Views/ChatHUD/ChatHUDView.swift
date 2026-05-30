import SwiftUI

/// Root of the Local Chat HUD. Three stacked regions: header, scrolling
/// transcript, and the footer input bar. Visuals are intentionally restrained —
/// this is the layer safe to restyle without touching `ChatHUDViewModel`.
struct ChatHUDView: View {
    @ObservedObject var viewModel: ChatHUDViewModel
    let onClose: () -> Void

    @State private var isNewChatHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
            transcript
            ChatInputBar(viewModel: viewModel)
        }
        .frame(minWidth: 320, minHeight: 480)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.25), Color.black.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .foregroundStyle(.white)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.5), radius: 2)
                Text("Cribble AI")
                    .font(.system(size: 13, weight: .semibold))
            }

            Spacer()

            // Center Segmented Picker (styling slot, non-functional)
            HStack(spacing: 0) {
                Text("Local LLM")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
                Text("Cloud")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.3))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .padding(2)
            .background(Color.black.opacity(0.2), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            }

            Spacer()

            Button {
                viewModel.newChat()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isNewChatHovered ? 1.0 : 0.6))
                    .scaleEffect(isNewChatHovered ? 1.05 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGenerating || !viewModel.hasConversation)
            .help("New chat")
            .onHover { hovering in
                isNewChatHovered = hovering
            }
            .pointingHandOnHover()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(isCloseHovered ? 1.0 : 0.6))
                    .scaleEffect(isCloseHovered ? 1.05 : 1.0)
            }
            .buttonStyle(.plain)
            .help("Close")
            .onHover { hovering in
                isCloseHovered = hovering
            }
            .pointingHandOnHover()
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
    @State private var logoAnimating = false

    var body: some View {
        VStack(spacing: 16) {
            // Glowing brand logo
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 64, height: 64)
                    .blur(radius: 12)

                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.4), radius: 6)
                    .scaleEffect(logoAnimating ? 1.08 : 0.98)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    logoAnimating = true
                }
            }
            .padding(.bottom, 8)

            VStack(spacing: 6) {
                Text("Hi \(name),")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text("What's on your mind?")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(0.2)
            }
            .multilineTextAlignment(.center)
        }
    }
}
