import SwiftUI

struct CommandPaletteView: View {
    let commands: [PaletteCommand]
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusedValue(\.dropReadingBookmarkAction) private var dropReadingBookmark
    @FocusedValue(\.highlightSelectionAction) private var highlightSelection
    @FocusedValue(\.toggleReadingTrailAction) private var toggleReadingTrail
    @FocusedValue(\.copyReadingTrailSummaryAction) private var copyReadingTrailSummary
    @FocusState private var isSearchFocused: Bool
    @State private var query = ""
    @State private var selectedID: PaletteCommand.ID?

    private var allCommands: [PaletteCommand] {
        commands + readingCommands
    }

    private var results: [PaletteCommand] {
        CommandPaletteModel.results(query: query, commands: allCommands)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                TextField("Run command", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .onSubmit { runSelection() }
            }
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if results.isEmpty {
                Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No available commands" : "No matching commands")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 92)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(results) { command in
                            Button {
                                run(command)
                            } label: {
                                row(command)
                            }
                            .buttonStyle(.plain)
                            .background {
                                if command.id == selectedID {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(.quaternary)
                                }
                            }
                            .accessibilityLabel(accessibilityLabel(for: command))
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 360)
            }
        }
        .frame(width: 560)
        .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.24), radius: 24, y: 12)
        .onAppear {
            selectedID = results.first?.id
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: query) {
            selectedID = results.first?.id
        }
        .onMoveCommand { direction in
            switch direction {
            case .up:
                moveSelection(by: -1)
            case .down:
                moveSelection(by: 1)
            default:
                break
            }
        }
        .onExitCommand(perform: onDismiss)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.98).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command palette")
    }

    private func row(_ command: PaletteCommand) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "command")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(command.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let shortcut = command.shortcut {
                Text(shortcut)
                    .font(.caption.monospaced().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func accessibilityLabel(for command: PaletteCommand) -> String {
        if let shortcut = command.shortcut {
            return "\(command.title), shortcut \(shortcut)"
        }
        return command.title
    }

    private func runSelection() {
        guard let selectedID,
              let command = results.first(where: { $0.id == selectedID }) ?? results.first else {
            return
        }
        run(command)
    }

    private func run(_ command: PaletteCommand) {
        command.action()
        onDismiss()
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else {
            selectedID = nil
            return
        }

        let currentIndex = selectedID.flatMap { id in
            results.firstIndex(where: { $0.id == id })
        } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), results.count - 1)
        selectedID = results[nextIndex].id
    }

    private var readingCommands: [PaletteCommand] {
        [
            readingCommand(
                id: "drop-reading-bookmark",
                title: "Drop Reading Bookmark",
                subtitle: "Mark the current reading position",
                keywords: ["reading", "bookmark"],
                action: dropReadingBookmark
            ),
            readingCommand(
                id: "highlight-selection",
                title: "Highlight",
                subtitle: "Highlight the selected text",
                keywords: ["reading", "selection"],
                action: highlightSelection
            ),
            readingCommand(
                id: "toggle-reading-trail",
                title: "Toggle Reading Trail",
                subtitle: "Show or hide the reading trail",
                keywords: ["reading", "trail"],
                action: toggleReadingTrail
            ),
            readingCommand(
                id: "copy-reading-trail-summary",
                title: "Copy Reading Trail Summary",
                subtitle: "Copy a handoff summary for the trail",
                keywords: ["reading", "trail", "clipboard"],
                action: copyReadingTrailSummary
            )
        ]
    }

    private func readingCommand(
        id: String,
        title: String,
        subtitle: String,
        keywords: [String],
        action: (() -> Void)?
    ) -> PaletteCommand {
        PaletteCommand(
            id: id,
            title: title,
            subtitle: subtitle,
            shortcut: nil,
            keywords: keywords,
            isEnabled: action != nil,
            action: action ?? {}
        )
    }
}
