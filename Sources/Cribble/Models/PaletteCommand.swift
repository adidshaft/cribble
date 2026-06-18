import Foundation

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let shortcut: String?
    let keywords: [String]
    let isEnabled: Bool
    let action: () -> Void
}

enum CommandPaletteModel {
    static func results(query: String, commands: [PaletteCommand], limit: Int = 12) -> [PaletteCommand] {
        let enabledCommands = commands.filter(\.isEnabled)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered: [PaletteCommand]

        if trimmed.isEmpty {
            ordered = enabledCommands
        } else {
            ordered = FuzzyMatch.ranked(query: trimmed, candidates: enabledCommands) { command in
                [command.title, command.subtitle, command.shortcut].compactMap(\.self) + command.keywords
            }
        }

        return Array(ordered.prefix(max(0, limit)))
    }
}
