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
        .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 16))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    // No bar — just three floating controls, top-right, over the content.
    private var header: some View {
        headerControls
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
    }

    private var headerControls: some View {
        HStack(spacing: 14) {
            Spacer()

            HeaderIcon(
                systemName: viewModel.useProjectIntelligence ? "brain.fill" : "brain",
                help: viewModel.useProjectIntelligence ? "Project intelligence: ON (answers use this project's index)" : "Project intelligence: OFF"
            ) { viewModel.useProjectIntelligence.toggle() }

            HeaderIcon(
                systemName: "brain.head.profile",
                help: "Open Project Intelligence"
            ) { IntelligenceHUDController.shared.toggle() }

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
        .cribbleGlassContainer()
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
                            ChatBubbleView(message: message, viewModel: viewModel)
                                .equatable()
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)
                }
            }
            .onChange(of: viewModel.messages.last?.text) {
                guard let last = viewModel.messages.last else { return }
                // No animation while streaming: an animated scrollTo per token
                // floods the run loop with overlapping animations and forces a
                // full ScrollView content-frame recompute on every delta.
                proxy.scrollTo(last.id, anchor: .bottom)
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

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
        }
        .disabled(disabled)
        .cribbleGlassIconButton(size: 30)
        .opacity(disabled ? 0.42 : 1)
        .help(help)
        .pointingHandOnHover()
    }
}

/// Soft welcome shown before the first message — the Cribble mark over a gentle
/// glow, a light prompt, and a hint about the selected model so first-time users
/// know whether a download is coming.
struct ChatEmptyState: View {
    @ObservedObject var viewModel: ChatHUDViewModel

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 64, height: 64)

                // The actual Cribble app icon — always available, no bundle lookup.
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 56, height: 56)
            }

            Text("What can Cribble do for you?")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            quickActions

            modelHint
        }
    }

    private var quickActions: some View {
        VStack(spacing: 6) {
            ForEach(QuickActions.all.prefix(4)) { action in
                Button {
                    viewModel.runQuickAction(action)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: action.icon)
                            .font(.system(size: 11))
                            .frame(width: 16)
                        Text(action.title)
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: 200)
                }
                .cribbleGlassCapsuleButton()
                .pointingHandOnHover()
            }
        }
        .padding(.top, 4)
        .disabled(viewModel.isGenerating)
        .cribbleGlassContainer()
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
        .cribbleMaterialSurface(in: Capsule())
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }
}
