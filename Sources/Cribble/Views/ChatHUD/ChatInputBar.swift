import SwiftUI

/// Footer input area: model/status line, attachment chips, `@`-autocomplete,
/// the pill editor, attach (`+`), model picker, mic placeholder, and send/stop.
struct ChatInputBar: View {
    @ObservedObject var viewModel: ChatHUDViewModel
    @FocusState private var inputFocused: Bool
    @State private var isPlusHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusLine
            autocompleteList
            attachmentChips
            pill
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    // MARK: Status / model phase

    @ViewBuilder
    private var statusLine: some View {
        switch viewModel.modelPhase {
        case .downloading(let fraction):
            phaseLabel("Downloading \(viewModel.selectedModel.name) — \(Int(fraction * 100))%", system: "arrow.down.circle")
        case .loading:
            phaseLabel("Loading \(viewModel.selectedModel.name)…", system: "cpu")
        case .failed(let message):
            phaseLabel(message, system: "exclamationmark.triangle", tint: .orange)
        case .idle, .ready:
            if let status = viewModel.statusMessage {
                phaseLabel(status, system: "info.circle")
            }
        }
    }

    private func phaseLabel(_ text: String, system: String, tint: Color = .white) -> some View {
        HStack(spacing: 6) {
            if system == "cpu" || system.contains("arrow.down") {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                    .frame(width: 12, height: 12)
            } else {
                Image(systemName: system)
                    .font(.system(size: 10))
                    .foregroundStyle(tint.opacity(0.8))
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(tint.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        }
    }

    // MARK: Autocomplete

    @ViewBuilder
    private var autocompleteList: some View {
        if let autocomplete = viewModel.autocomplete, !autocomplete.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text("SUGGESTED NOTES")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                ForEach(autocomplete.matches) { token in
                    AutocompleteRow(token: token) {
                        viewModel.applyAutocomplete(token)
                    }
                }
            }
            .background(Color.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
            .cribbleGlass(in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.25), radius: 10, y: 5)
            .padding(.horizontal, 2)
        }
    }

    // MARK: Attachments

    @ViewBuilder
    private var attachmentChips: some View {
        if !viewModel.attachments.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.attachments) { token in
                        AttachmentChipRow(token: token) {
                            viewModel.removeAttachment(token)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Pill

    private var pill: some View {
        HStack(alignment: .center, spacing: 8) {
            attachMenu

            TextField("Ask anything, @ to tag a note…", text: draftBinding, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit(submit)

            modelChip
            micButton
            sendButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.3))
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .cribbleGlass(in: RoundedRectangle(cornerRadius: 22))
        .onAppear { inputFocused = true }
    }

    private var attachMenu: some View {
        Menu {
            if viewModel.quickAttachFiles.isEmpty {
                Text("Open a folder to tag notes")
            } else {
                ForEach(viewModel.quickAttachFiles) { token in
                    Button(token.displayName) { viewModel.addAttachment(token) }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white.opacity(isPlusHovered ? 1.0 : 0.7))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(isPlusHovered ? 0.12 : 0.06), in: Circle())
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 26)
        .help("Attach a note")
        .onHover { hovering in
            isPlusHovered = hovering
        }
        .pointingHandOnHover()
    }

    private var modelChip: some View {
        Menu {
            ForEach(ModelCatalog.all) { model in
                Button {
                    viewModel.selectModel(model)
                } label: {
                    let isFlash = model.speedLabel.lowercased().contains("flash")
                    let isSelected = model.id == viewModel.selectedModel.id
                    Label(
                        "\(model.name) · \(model.approximateSize)",
                        systemImage: isSelected ? "checkmark" : (isFlash ? "bolt.fill" : "cpu")
                    )
                }
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(viewModel.selectedModel.speedLabel.lowercased().contains("flash") ? Color.green : Color.blue)
                    .frame(width: 5, height: 5)
                    .shadow(color: (viewModel.selectedModel.speedLabel.lowercased().contains("flash") ? Color.green : Color.blue).opacity(0.6), radius: 2)
                Text(viewModel.selectedModel.speedLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose model")
        .pointingHandOnHover()
    }

    private var micButton: some View {
        Button {} label: {
            Image(systemName: "mic")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.2))
                .frame(width: 26, height: 26)
                .background(Color.white.opacity(0.02), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(true)
        .help("Dictation (coming soon)")
    }

    private var sendButton: some View {
        Button(action: submit) {
            ZStack {
                Circle()
                    .fill(sendBackgroundStyle)
                    .frame(width: 26, height: 26)
                    .shadow(color: sendShadowColor, radius: 4)

                if viewModel.isGenerating {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 8, height: 8)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isGenerating && !viewModel.canSend)
        .keyboardShortcut(.return, modifiers: [])
        .help(viewModel.isGenerating ? "Stop" : "Send")
        .pointingHandOnHover()
    }

    private var sendBackgroundStyle: AnyShapeStyle {
        if viewModel.isGenerating {
            return AnyShapeStyle(Color.red)
        }
        if viewModel.canSend {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(0.06))
    }

    private var sendShadowColor: Color {
        if viewModel.isGenerating { return .red.opacity(0.3) }
        if viewModel.canSend { return Color.accentColor.opacity(0.3) }
        return .clear
    }

    private var draftBinding: Binding<String> {
        Binding(
            get: { viewModel.draft },
            set: { viewModel.updateDraft($0) }
        )
    }

    private func submit() {
        if viewModel.isGenerating {
            viewModel.cancel()
        } else {
            viewModel.send()
        }
    }
}

struct AutocompleteRow: View {
    let token: TaggedFileToken
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundStyle(isHovered ? .blue : .white.opacity(0.7))
                Text(token.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isHovered ? .white : .white.opacity(0.9))
                Spacer()
                Image(systemName: "return")
                    .font(.system(size: 9))
                    .foregroundStyle(isHovered ? .white.opacity(0.5) : .white.opacity(0.2))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHovered ? Color.white.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .pointingHandOnHover()
    }
}

struct AttachmentChipRow: View {
    let token: TaggedFileToken
    let onRemove: () -> Void
    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 10))
                .foregroundStyle(.blue.opacity(0.85))
            Text(token.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(isCloseHovered ? .white : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isCloseHovered = hovering
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 0.75)
        }
        .clipShape(Capsule())
        .pointingHandOnHover()
    }
}
