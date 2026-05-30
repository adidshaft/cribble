import AppKit
import SwiftUI

/// Root of the Local Chat HUD. Three stacked regions: header, scrolling
/// transcript, and the footer input bar. Visuals are intentionally restrained —
/// this is the layer safe to restyle without touching `ChatHUDViewModel`.
struct ChatHUDView: View {
    @ObservedObject var viewModel: ChatHUDViewModel
    var presentation: ChatHUDPresentation = .floating
    let onClose: () -> Void
    var onToggleMode: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
            ChatInputBar(viewModel: viewModel)
        }
        .frame(minWidth: 320, minHeight: 460)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.25), Color.black.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
        .foregroundStyle(.white)
    }

    // No bar — just three floating controls, top-right, over the content.
    private var header: some View {
        HStack(spacing: 14) {
            Spacer()

            HeaderIcon(
                systemName: "square.and.pencil",
                help: "New chat",
                disabled: viewModel.isGenerating || !viewModel.hasConversation
            ) { viewModel.newChat() }

            HeaderIcon(
                systemName: presentation == .floating ? "chevron.up" : "chevron.down",
                help: presentation == .floating ? "Send to menu bar" : "Pop out to window"
            ) { onToggleMode() }

            HeaderIcon(systemName: "xmark", help: "Close") { onClose() }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
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

/// A small, hover-responsive header control.
private struct HeaderIcon: View {
    let systemName: String
    let help: String
    var disabled: Bool = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(hovered ? 1.0 : 0.5))
                .scaleEffect(hovered ? 1.08 : 1.0)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .onHover { hovered = $0 }
        .pointingHandOnHover()
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
                return ("cloud", "\(model.name) utilizes the sessions logged in your Terminal already.")
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
