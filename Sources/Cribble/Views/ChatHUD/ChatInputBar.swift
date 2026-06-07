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
            slashCommandList
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
        case .downloading(let progress):
            let percent = Int(progress.fraction * 100)
            let speed = ChatHUDViewModel.formatTransferSpeed(progress.bytesPerSecond)
            if let speed {
                phaseLabel("Downloading \(viewModel.selectedModel.name) — \(percent)% at \(speed)", system: "arrow.down.circle")
            } else if progress.fraction > 0 {
                phaseLabel("Downloading \(viewModel.selectedModel.name) — \(percent)%", system: "arrow.down.circle")
            } else {
                phaseLabel("Downloading \(viewModel.selectedModel.name) (\(viewModel.selectedModel.approximateSize))…", system: "arrow.down.circle")
            }
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

    // MARK: Slash commands

    @ViewBuilder
    private var slashCommandList: some View {
        if viewModel.isSlashCommandQuery {
            VStack(alignment: .leading, spacing: 1) {
                Text("COMMANDS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                if viewModel.slashCommands.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("No command matches")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                            Text("Try /summarize, /index, or an installed extension action.")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Spacer(minLength: 0)
                        Button("Clear") {
                            viewModel.clearSlashCommandQuery()
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .pointingHandOnHover()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                } else {
                    ForEach(viewModel.slashCommands) { action in
                        Button {
                            viewModel.runQuickAction(action)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: action.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .frame(width: 16)
                                Text(action.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.9))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .pointingHandOnHover()
                    }
                }
            }
            .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 12), strokeOpacity: 0.10)
            .padding(.horizontal, 2)
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
            .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 12), strokeOpacity: 0.10)
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

            ModelPickerButton(viewModel: viewModel)
            sendButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .cribbleInteractiveGlass(in: RoundedRectangle(cornerRadius: 22))
        .cribbleGlassContainer()
        .onAppear { inputFocused = true }
    }

    private var attachMenu: some View {
        Menu {
            Button("Choose File…", systemImage: "folder") {
                viewModel.chooseFileToAttach()
            }
            if viewModel.allNotesCount > 0 {
                Button("Attach All Notes (\(viewModel.allNotesCount))", systemImage: "doc.on.doc") {
                    viewModel.attachAllNotes()
                }
            }
            if !viewModel.quickAttachFiles.isEmpty {
                Divider()
                Section("Recent notes") {
                    ForEach(viewModel.quickAttachFiles) { token in
                        Button(token.pathLabel) { viewModel.addAttachment(token) }
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(isPlusHovered ? 1.0 : 0.7))
                .frame(width: 26, height: 26)
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

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: viewModel.isGenerating ? "stop.fill" : "arrow.up")
                .font(.system(size: 11, weight: .bold))
        }
        .cribbleGlassIconButton(prominent: viewModel.isGenerating || viewModel.canSend, size: 26)
        .disabled(!viewModel.isGenerating && !viewModel.canSend)
        .keyboardShortcut(.return, modifiers: [])
        .help(viewModel.isGenerating ? "Stop" : "Send")
        .pointingHandOnHover()
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(token.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isHovered ? .white : .white.opacity(0.9))
                    if let rel = token.relativePath, rel != token.filename {
                        Text(rel)
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
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
        .cribbleMaterialSurface(in: Capsule(), strokeOpacity: 0.10)
        .pointingHandOnHover()
    }
}
