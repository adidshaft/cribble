import SwiftUI

/// Footer input area: model/status line, attachment chips, `@`-autocomplete,
/// the pill editor, attach (`+`), model picker, mic placeholder, and send/stop.
struct ChatInputBar: View {
    @ObservedObject var viewModel: ChatHUDViewModel
    @FocusState private var inputFocused: Bool

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
        Label(text, systemImage: system)
            .font(.system(size: 11))
            .foregroundStyle(tint.opacity(0.7))
            .lineLimit(2)
    }

    // MARK: Autocomplete

    @ViewBuilder
    private var autocompleteList: some View {
        if let autocomplete = viewModel.autocomplete, !autocomplete.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(autocomplete.matches) { token in
                    Button {
                        viewModel.applyAutocomplete(token)
                    } label: {
                        Label(token.displayName, systemImage: "doc.text")
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: Attachments

    @ViewBuilder
    private var attachmentChips: some View {
        if !viewModel.attachments.isEmpty {
            HStack(spacing: 6) {
                ForEach(viewModel.attachments) { token in
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                        Text(token.displayName)
                        Button {
                            viewModel.removeAttachment(token)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    // MARK: Pill

    private var pill: some View {
        HStack(alignment: .bottom, spacing: 8) {
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
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
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
                .font(.system(size: 14, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 22)
        .help("Attach a note")
    }

    private var modelChip: some View {
        Menu {
            ForEach(ModelCatalog.all) { model in
                Button {
                    viewModel.selectModel(model)
                } label: {
                    if model.id == viewModel.selectedModel.id {
                        Label("\(model.name) · \(model.approximateSize)", systemImage: "checkmark")
                    } else {
                        Text("\(model.name) · \(model.approximateSize)")
                    }
                }
            }
        } label: {
            Text(viewModel.selectedModel.speedLabel)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose model")
    }

    private var micButton: some View {
        Button {
            // Dictation placeholder — wired to NSSpeechRecognizer in a follow-up.
        } label: {
            Image(systemName: "mic")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
        }
        .buttonStyle(.plain)
        .help("Dictate (coming soon)")
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: viewModel.isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(sendTint)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isGenerating && !viewModel.canSend)
        .keyboardShortcut(.return, modifiers: [])
        .help(viewModel.isGenerating ? "Stop" : "Send")
    }

    private var sendTint: Color {
        if viewModel.isGenerating { return .white }
        return viewModel.canSend ? .accentColor : .white.opacity(0.3)
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
