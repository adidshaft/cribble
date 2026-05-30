import AppKit
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

    // Minimal floating controls — no title bar. Just New Chat + Close, top-right.
    private var header: some View {
        HStack(spacing: 12) {
            Spacer()

            Button {
                viewModel.newChat()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(isNewChatHovered ? 1.0 : 0.55))
                    .scaleEffect(isNewChatHovered ? 1.06 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isGenerating || !viewModel.hasConversation)
            .help("New chat")
            .onHover { isNewChatHovered = $0 }
            .pointingHandOnHover()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(isCloseHovered ? 1.0 : 0.55))
                    .scaleEffect(isCloseHovered ? 1.06 : 1.0)
            }
            .buttonStyle(.plain)
            .help("Close")
            .onHover { isCloseHovered = $0 }
            .pointingHandOnHover()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    ChatEmptyState(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
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

/// Soft welcome shown before the first message — the Cribble mark over a gentle
/// glow, a light prompt, and a hint about the selected model so first-time users
/// know whether a download is coming.
struct ChatEmptyState: View {
    @ObservedObject var viewModel: ChatHUDViewModel
    @State private var glowing = false

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 72, height: 72)
                    .blur(radius: 14)
                    .scaleEffect(glowing ? 1.1 : 0.92)

                // The actual Cribble app icon — always available, no bundle lookup.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    glowing = true
                }
            }

            Text("What can Cribble do for you?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            modelHint
        }
    }

    private var modelHint: some View {
        let model = viewModel.selectedModel
        let availability = viewModel.availability(of: model)
        let (icon, text): (String, String) = {
            switch availability {
            case .cloud:
                return ("cloud", "\(model.name) runs in the cloud — ready when you are.")
            case .downloaded:
                return ("checkmark.circle", "\(model.name) is on your Mac — ready to chat.")
            case .notDownloaded:
                return ("arrow.down.circle", "\(model.name) (\(model.approximateSize)) downloads the first time you send.")
            }
        }()

        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.55))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5) }
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }
}
