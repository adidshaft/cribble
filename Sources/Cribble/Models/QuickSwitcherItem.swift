import Foundation

struct QuickSwitcherItem: Identifiable, Equatable, Sendable {
    let url: URL
    let title: String
    let subtitle: String
    let aliases: [String]
    let recencyRank: Int?

    var id: URL { url }
}

enum QuickSwitcherModel {
    static func items(
        documents: [MarkdownDocumentMeta],
        recentURLs: [URL],
        relativePath: (URL) -> String?
    ) -> [QuickSwitcherItem] {
        let recency = Dictionary(uniqueKeysWithValues: recentURLs.reversed().enumerated().map { rank, url in
            (url.standardizedFileURL, rank)
        })

        return documents.map { document in
            let url = document.url.standardizedFileURL
            return QuickSwitcherItem(
                url: url,
                title: document.title,
                subtitle: relativePath(url) ?? url.lastPathComponent,
                aliases: document.linkAliases,
                recencyRank: recency[url]
            )
        }
    }

    static func results(query: String, items: [QuickSwitcherItem], limit: Int = 10) -> [QuickSwitcherItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ordered: [QuickSwitcherItem]
        if trimmed.isEmpty {
            ordered = items.sorted { lhs, rhs in
                switch (lhs.recencyRank, rhs.recencyRank) {
                case let (l?, r?) where l != r:
                    return l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
        } else {
            ordered = FuzzyMatch.ranked(
                query: trimmed,
                candidates: items,
                recencyRank: { $0.recencyRank },
                text: { item in
                    [item.title, item.subtitle, item.url.deletingPathExtension().lastPathComponent] + item.aliases
                }
            )
        }
        return Array(ordered.prefix(max(0, limit)))
    }
}
