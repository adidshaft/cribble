import Foundation

/// A one-tap prompt for the chat HUD — surfaced as empty-state chips and via the
/// `/` command palette in the input.
struct QuickAction: Identifiable, Hashable {
    enum Source: Hashable {
        case builtIn
        case `extension`(String)
    }

    let id: String
    let title: String
    let icon: String
    let prompt: String
    var aliases: [String] = []
    var source: Source = .builtIn
}

enum QuickActions {
    static var all: [QuickAction] {
        builtIns(todayTitle: dailyNoteTitle())
    }

    static func builtIns(todayTitle: String) -> [QuickAction] {
        [
            QuickAction(
                id: "summarize",
                title: "Summarize",
                icon: "text.alignleft",
                prompt: "Summarize the current note in 3–5 concise bullet points.",
                aliases: ["brief", "recap", "tl;dr", "overview"]
            ),
            QuickAction(
                id: "today-note",
                title: "Draft today",
                icon: "calendar.badge.plus",
                prompt: "Draft a useful daily note for \(todayTitle). Reply with a CREATE: Daily/\(todayTitle).md block only, with sections for Notes, Decisions, Tasks, and Follow-ups.",
                aliases: ["daily", "journal", "capture", "log", "standup"]
            ),
            QuickAction(
                id: "related",
                title: "Find related",
                icon: "doc.text.magnifyingglass",
                prompt: "Which other notes in my workspace relate to this one, and how? List them with a one-line reason each.",
                aliases: ["connections", "similar", "search", "graph"]
            ),
            QuickAction(
                id: "links",
                title: "Suggest links",
                icon: "link",
                prompt: "Suggest sparse, high-confidence [[wiki links]] connecting the notes in context. Reply with a unified diff only.",
                aliases: ["backlinks", "wiki", "connect"]
            ),
            QuickAction(
                id: "index",
                title: "Create index",
                icon: "list.bullet.rectangle",
                prompt: "Create a single index note that links and briefly describes the notes in context. Output it as a CREATE: index.md block.",
                aliases: ["map", "table of contents", "toc", "overview"]
            ),
            QuickAction(
                id: "simplify",
                title: "Explain simply",
                icon: "lightbulb",
                prompt: "Explain the current note in simple, plain language a beginner could follow.",
                aliases: ["eli5", "beginner", "plain", "teach"]
            )
        ]
    }

    static func matching(_ query: String, extensions: [QuickAction] = []) -> [QuickAction] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let actions = all + extensions
        guard !q.isEmpty else { return actions }
        return actions
            .compactMap { action -> (QuickAction, Int)? in
                guard let score = matchScore(action, query: q) else { return nil }
                return (action, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.title.localizedCaseInsensitiveCompare(rhs.0.title) == .orderedAscending
            }
            .map(\.0)
    }

    private static func matchScore(_ action: QuickAction, query: String) -> Int? {
        let title = action.title.lowercased()
        if title == query { return 0 }
        if action.id.lowercased() == query { return 0 }
        if title.hasPrefix(query) { return 1 }
        if action.id.lowercased().hasPrefix(query) { return 1 }
        if action.aliases.contains(where: { $0.lowercased() == query }) { return 2 }
        if action.aliases.contains(where: { $0.lowercased().hasPrefix(query) }) { return 3 }
        if title.contains(query) { return 4 }
        if action.id.lowercased().contains(query) { return 4 }
        if action.aliases.contains(where: { $0.lowercased().contains(query) }) { return 5 }
        if action.prompt.lowercased().contains(query) { return 6 }
        if case .extension(let name) = action.source,
           name.lowercased().contains(query) {
            return 7
        }
        return nil
    }

    private static func dailyNoteTitle(date: Date = Date(), calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}
