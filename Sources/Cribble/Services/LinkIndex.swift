import Foundation

struct LinkIndex {
    private var targets: [String: URL] = [:]

    init(documents: [MarkdownDocument], rootURL: URL) {
        var entries: [(String, URL)] = []

        for document in documents.sorted(by: { $0.url.path < $1.url.path }) {
            let metadata = FrontMatterParser.parse(document.rawMarkdown)
            let stem = document.url.deletingPathExtension().lastPathComponent
            let relativePath = document.url.relativePath(from: rootURL)
            let title = document.title

            entries.append((stem, document.url))
            entries.append((title, document.url))
            entries.append((relativePath, document.url))
            entries.append((relativePath.replacingOccurrences(of: ".md", with: ""), document.url))

            for heading in document.headings {
                entries.append((heading.title, document.url))
                entries.append(("\(stem)#\(heading.anchor)", document.url))
                entries.append(("\(title)#\(heading.anchor)", document.url))
            }

            for alias in metadata.aliases + metadata.keywords + metadata.tags {
                entries.append((alias, document.url))
            }
        }

        for (key, url) in entries {
            let normalized = Self.normalize(key)
            guard !normalized.isEmpty, targets[normalized] == nil else {
                continue
            }
            targets[normalized] = url
        }
    }

    func resolve(_ link: WikiLink) -> ResolvedLink {
        let exactTarget = Self.normalize(link.target)
        let anchoredTarget: String?
        if let anchor = link.anchor {
            anchoredTarget = Self.normalize("\(link.target)#\(Slugger.slug(anchor))")
        } else {
            anchoredTarget = nil
        }

        let url = anchoredTarget.flatMap { targets[$0] } ?? targets[exactTarget]
        return ResolvedLink(link: link, targetURL: url, anchor: link.anchor.map(Slugger.slug))
    }

    static func normalize(_ value: String) -> String {
        let stripped = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        return stripped
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}
