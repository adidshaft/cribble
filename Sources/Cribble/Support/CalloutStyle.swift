import SwiftUI

struct CalloutStyle {
    let title: String
    let symbolName: String
    let accent: Color

    static func style(for callout: CalloutBlock) -> CalloutStyle {
        let key = callout.type.lowercased()
        let mapped = mapping[key] ?? mapping[aliases[key] ?? ""] ?? defaultMapping
        return CalloutStyle(
            title: callout.title,
            symbolName: mapped.symbolName,
            accent: mapped.accent
        )
    }

    private static let defaultMapping = (symbolName: "info.circle", accent: Color.accentColor)

    private static let aliases: [String: String] = [
        "hint": "tip",
        "success": "tip",
        "check": "tip",
        "done": "tip",
        "failure": "danger",
        "fail": "danger",
        "error": "danger",
        "bug": "danger",
        "faq": "question",
        "help": "question",
        "summary": "abstract",
        "tldr": "abstract",
        "cite": "quote"
    ]

    private static let mapping: [String: (symbolName: String, accent: Color)] = [
        "note": ("note.text", .accentColor),
        "info": ("info.circle", .blue),
        "tip": ("lightbulb", .green),
        "warning": ("exclamationmark.triangle", .orange),
        "danger": ("xmark.octagon", .red),
        "quote": ("quote.opening", .secondary),
        "question": ("questionmark.circle", .purple),
        "example": ("list.bullet.rectangle", .indigo),
        "abstract": ("text.alignleft", .teal)
    ]
}
