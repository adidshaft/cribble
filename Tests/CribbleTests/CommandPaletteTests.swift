import Testing
@testable import Cribble

@Suite("Command palette")
struct CommandPaletteTests {
    @Test("filters commands by title, shortcut, and keywords")
    func filtersCommands() {
        let commands = [
            command(id: "copy-md", title: "Copy Markdown", shortcut: "⌘M", keywords: ["clipboard", "md"]),
            command(id: "open-today", title: "Open Today Note", shortcut: "⌘N", keywords: ["daily"]),
            command(id: "ai-link", title: "AI Link Notes", keywords: ["wikilink", "intelligence"])
        ]

        #expect(CommandPaletteModel.results(query: "md", commands: commands).map(\.id) == ["copy-md"])
        #expect(CommandPaletteModel.results(query: "⌘N", commands: commands).map(\.id) == ["open-today"])
        #expect(CommandPaletteModel.results(query: "wiki", commands: commands).map(\.id) == ["ai-link"])
    }

    @Test("keeps disabled commands out of the palette")
    func excludesDisabledCommands() {
        let commands = [
            command(id: "enabled", title: "Open Folder", isEnabled: true),
            command(id: "disabled", title: "Copy Wiki Link", isEnabled: false)
        ]

        #expect(CommandPaletteModel.results(query: "", commands: commands).map(\.id) == ["enabled"])
        #expect(CommandPaletteModel.results(query: "wiki", commands: commands).isEmpty)
    }

    @Test("empty query preserves registry order and shortcut metadata")
    func emptyQueryPreservesRegistryOrder() {
        let commands = [
            command(id: "quick", title: "Quick Switcher", shortcut: "⌘O"),
            command(id: "palette", title: "Command Palette", shortcut: "⌘P")
        ]

        let results = CommandPaletteModel.results(query: "  ", commands: commands)

        #expect(results.map(\.id) == ["quick", "palette"])
        #expect(results.map(\.shortcut) == ["⌘O", "⌘P"])
    }

    private func command(
        id: String,
        title: String,
        shortcut: String? = nil,
        keywords: [String] = [],
        isEnabled: Bool = true
    ) -> PaletteCommand {
        PaletteCommand(
            id: id,
            title: title,
            subtitle: nil,
            shortcut: shortcut,
            keywords: keywords,
            isEnabled: isEnabled,
            action: {}
        )
    }
}
