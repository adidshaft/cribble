import Foundation

/// Normalizes the many ways an image can appear in real-world Markdown notes
/// into the single `![alt](file:///absolute/path)` form that the Textual
/// renderer can actually display.
///
/// The reader previously only handled standard `![alt](relative.png)` resolved
/// against the note's own directory. That missed three common cases, all fixed
/// here:
///
/// 1. **Obsidian/Logseq embeds** — `![[image.png]]` (and `![[image.png|300]]`).
///    These were worse than unrendered: the wiki-link pass turned them into a
///    broken `![↗ image.png](cribble://…)`. We resolve them before that pass.
/// 2. **Raw HTML images** — `<img src="…">`, common in notes pasted from the
///    web. Textual is a CommonMark renderer and drops these.
/// 3. **Vault-level attachment folders** — `attachments/`, `assets/`, `images/`
///    next to the note or at the vault root, where many vaults keep media.
///
/// Remote `http(s)` images are, by default, *not* auto-loaded — fetching them
/// would leak the reader's IP to arbitrary hosts, at odds with Cribble's
/// local-first promise. They are rewritten to a plain link the user can click
/// to open in a browser. A per-app toggle (`loadRemoteImages`) restores
/// inline loading for users who want it.
///
/// This runs in the off-main render task (it touches the filesystem to probe
/// candidate paths) and must run *before* `WikiLinkParser.renderForMarkdown`.
enum MarkdownImageRewriter {
    /// Image file extensions Textual can decode and we should render inline.
    /// PDFs and other embeds fall through to wiki-link handling.
    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "bmp",
        "heic", "heif", "tif", "tiff", "avif", "ico"
    ]

    static func rewrite(
        _ markdown: String,
        noteDirectory: URL,
        rootURL: URL?,
        loadRemoteImages: Bool
    ) -> String {
        var result = markdown
        result = rewriteHTMLImages(result)
        result = rewriteEmbeds(result, noteDirectory: noteDirectory, rootURL: rootURL, loadRemoteImages: loadRemoteImages)
        result = rewriteStandardImages(result, noteDirectory: noteDirectory, rootURL: rootURL, loadRemoteImages: loadRemoteImages)
        return result
    }

    // MARK: - HTML <img>

    private static let htmlImageRegex = try? NSRegularExpression(
        pattern: #"<img\b[^>]*?>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )
    private static let htmlAttrRegex = try? NSRegularExpression(
        pattern: #"(\w+)\s*=\s*"([^"]*)"|(\w+)\s*=\s*'([^']*)'"#,
        options: [.caseInsensitive]
    )

    private static func rewriteHTMLImages(_ markdown: String) -> String {
        guard let htmlImageRegex else { return markdown }
        let ns = markdown as NSString
        var result = markdown
        let matches = htmlImageRegex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            let tag = ns.substring(with: match.range)
            let attrs = parseHTMLAttributes(tag)
            guard let src = attrs["src"], !src.isEmpty else { continue }
            let alt = attrs["alt"] ?? ""
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: "![\(alt)](\(src))")
        }
        return result
    }

    private static func parseHTMLAttributes(_ tag: String) -> [String: String] {
        guard let htmlAttrRegex else { return [:] }
        let ns = tag as NSString
        var attrs: [String: String] = [:]
        for match in htmlAttrRegex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let nameRange = match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 3)
            let valueRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 4)
            guard nameRange.location != NSNotFound, valueRange.location != NSNotFound else { continue }
            attrs[ns.substring(with: nameRange).lowercased()] = ns.substring(with: valueRange)
        }
        return attrs
    }

    // MARK: - Wiki embeds ![[...]]

    private static let embedRegex = try? NSRegularExpression(pattern: #"!\[\[([^\]\n]+)\]\]"#)

    private static func rewriteEmbeds(
        _ markdown: String,
        noteDirectory: URL,
        rootURL: URL?,
        loadRemoteImages: Bool
    ) -> String {
        guard let embedRegex else { return markdown }
        let ns = markdown as NSString
        var result = markdown
        let matches = embedRegex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard let innerRange = Range(match.range(at: 1), in: result),
                  let outerRange = Range(match.range(at: 0), in: result) else { continue }
            let inner = String(result[innerRange])
            // `target|size` — drop the size hint, keep the target.
            let target = inner.components(separatedBy: "|").first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? inner
            let ext = (target as NSString).pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                let alt = (target as NSString).lastPathComponent
                let dest = resolvedDestination(
                    for: target,
                    noteDirectory: noteDirectory,
                    rootURL: rootURL,
                    loadRemoteImages: loadRemoteImages
                )
                result.replaceSubrange(outerRange, with: imageOrLink(alt: alt, destination: dest))
            } else {
                // Non-image embed (note transclusion) — downgrade to a normal
                // wiki link so the wiki-link pass renders a clickable link
                // instead of a broken image.
                result.replaceSubrange(outerRange, with: "[[\(inner)]]")
            }
        }
        return result
    }

    // MARK: - Standard ![alt](path)

    private static let standardImageRegex = try? NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\(\s*(<[^>]+>|[^)\s]+)(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)"#
    )

    private static func rewriteStandardImages(
        _ markdown: String,
        noteDirectory: URL,
        rootURL: URL?,
        loadRemoteImages: Bool
    ) -> String {
        guard let standardImageRegex else { return markdown }
        let ns = markdown as NSString
        var result = markdown
        let matches = standardImageRegex.matches(in: markdown, range: NSRange(location: 0, length: ns.length))
        for match in matches.reversed() {
            guard let altRange = Range(match.range(at: 1), in: result),
                  let pathRange = Range(match.range(at: 2), in: result),
                  let outerRange = Range(match.range(at: 0), in: result) else { continue }
            let alt = String(result[altRange])
            var rawPath = String(result[pathRange])
            if rawPath.hasPrefix("<"), rawPath.hasSuffix(">") {
                rawPath = String(rawPath.dropFirst().dropLast())
            }
            let dest = resolvedDestination(
                for: rawPath,
                noteDirectory: noteDirectory,
                rootURL: rootURL,
                loadRemoteImages: loadRemoteImages
            )
            // Leave already-correct refs untouched to minimize churn.
            if dest.value == rawPath, !dest.isRemoteLink { continue }
            result.replaceSubrange(outerRange, with: imageOrLink(alt: alt, destination: dest))
        }
        return result
    }

    // MARK: - Resolution

    /// A resolution result: either an inline image destination, or a remote URL
    /// to be rendered as a click-to-open link.
    private struct Destination: Equatable {
        let value: String
        let isRemoteLink: Bool
    }

    private static func resolvedDestination(
        for rawTarget: String,
        noteDirectory: URL,
        rootURL: URL?,
        loadRemoteImages: Bool
    ) -> Destination {
        let target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return Destination(value: rawTarget, isRemoteLink: false) }

        if isRemote(target) {
            return Destination(value: target, isRemoteLink: !loadRemoteImages)
        }
        if target.hasPrefix("data:") || target.hasPrefix("file:") {
            return Destination(value: target, isRemoteLink: false)
        }

        if let resolved = locateOnDisk(target, noteDirectory: noteDirectory, rootURL: rootURL) {
            return Destination(value: resolved.absoluteString, isRemoteLink: false)
        }
        return Destination(value: rawTarget, isRemoteLink: false)
    }

    private static func imageOrLink(alt: String, destination: Destination) -> String {
        if destination.isRemoteLink {
            let label = alt.isEmpty ? "Open remote image" : alt
            return "[🖼 \(label)](\(destination.value))"
        }
        return "![\(alt)](\(destination.value))"
    }

    private static func isRemote(_ target: String) -> Bool {
        let lower = target.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// Probes a bounded set of conventional attachment locations. Cheap
    /// `fileExists` checks rather than a full vault walk, which keeps large
    /// vaults responsive.
    private static func locateOnDisk(_ target: String, noteDirectory: URL, rootURL: URL?) -> URL? {
        let decoded = target.removingPercentEncoding ?? target
        let fileManager = FileManager.default
        let filename = (decoded as NSString).lastPathComponent
        let attachmentDirs = ["", "attachments", "assets", "images", "media", "Files", "_attachments"]

        var candidates: [URL] = []
        // The path as written, relative to the note and the vault root.
        candidates.append(noteDirectory.appendingPathComponent(decoded))
        if let rootURL { candidates.append(rootURL.appendingPathComponent(decoded)) }
        // Bare filename inside conventional attachment folders.
        for dir in attachmentDirs {
            let base = dir.isEmpty ? noteDirectory : noteDirectory.appendingPathComponent(dir)
            candidates.append(base.appendingPathComponent(filename))
            if let rootURL {
                let rootBase = dir.isEmpty ? rootURL : rootURL.appendingPathComponent(dir)
                candidates.append(rootBase.appendingPathComponent(filename))
            }
        }

        for candidate in candidates {
            let standardized = candidate.standardizedFileURL
            if fileManager.fileExists(atPath: standardized.path) {
                return standardized
            }
        }
        return nil
    }
}
