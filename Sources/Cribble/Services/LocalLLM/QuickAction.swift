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
    var source: Source = .builtIn
}

enum QuickActions {
    static let all: [QuickAction] = [
        QuickAction(
            id: "summarize",
            title: "Summarize",
            icon: "text.alignleft",
            prompt: "Summarize the current note in 3–5 concise bullet points."
        ),
        QuickAction(
            id: "related",
            title: "Find related",
            icon: "doc.text.magnifyingglass",
            prompt: "Which other notes in my workspace relate to this one, and how? List them with a one-line reason each."
        ),
        QuickAction(
            id: "links",
            title: "Suggest links",
            icon: "link",
            prompt: "Suggest sparse, high-confidence [[wiki links]] connecting the notes in context. Reply with a unified diff only."
        ),
        QuickAction(
            id: "index",
            title: "Create index",
            icon: "list.bullet.rectangle",
            prompt: "Create a single index note that links and briefly describes the notes in context. Output it as a CREATE: index.md block."
        ),
        QuickAction(
            id: "simplify",
            title: "Explain simply",
            icon: "lightbulb",
            prompt: "Explain the current note in simple, plain language a beginner could follow."
        )
    ]

    static func matching(_ query: String, extensions: [QuickAction] = []) -> [QuickAction] {
        let q = query.lowercased()
        let actions = all + extensions
        guard !q.isEmpty else { return actions }
        return actions.filter {
            $0.title.lowercased().contains(q)
                || $0.id.lowercased().contains(q)
                || $0.prompt.lowercased().contains(q)
        }
    }
}
