import SwiftUI

struct NotePreviewPopover: View {
    let url: URL
    @EnvironmentObject private var library: MarkdownLibraryStore
    @State private var previewText: String = ""
    @State private var title: String = ""
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(previewText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear {
            loadPreview()
        }
    }

    private func loadPreview() {
        Task {
            let preview = await NotePreviewCache.shared.preview(for: url)
            title = preview.title
            previewText = preview.text
            isLoading = false
        }
    }
}

private struct NotePreviewContent {
    let title: String
    let text: String
}

@MainActor
private final class NotePreviewCache {
    static let shared = NotePreviewCache()

    private struct Entry {
        let modifiedAt: Date?
        let preview: NotePreviewContent
    }

    private var cache: [URL: Entry] = [:]
    private var order: [URL] = []
    private let limit = 80

    func preview(for rawURL: URL) async -> NotePreviewContent {
        let url = rawURL.standardizedFileURL
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if let entry = cache[url], entry.modifiedAt == modifiedAt {
            touch(url)
            return entry.preview
        }

        let preview = await Task.detached(priority: .userInitiated) {
            Self.loadPreview(url: url)
        }.value
        store(url: url, modifiedAt: modifiedAt, preview: preview)
        return preview
    }

    nonisolated private static func loadPreview(url: URL) -> NotePreviewContent {
        do {
            let doc = try DocumentLoader().load(url: url)
            return NotePreviewContent(title: doc.title, text: cleanPreview(doc.rawMarkdown))
        } catch {
            return NotePreviewContent(
                title: url.deletingPathExtension().lastPathComponent,
                text: "Could not load preview context."
            )
        }
    }

    nonisolated private static func cleanPreview(_ markdown: String) -> String {
        let cleaned = MarkdownDisplayPreprocessor.prepare(markdown, documentTitle: "")
        // Basic Markdown syntax stripping
        let noSyntax = cleaned
            .replacingOccurrences(of: #"[#*`_\-\[\]\(\)]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(noSyntax.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
    }

    private func store(url: URL, modifiedAt: Date?, preview: NotePreviewContent) {
        cache[url] = Entry(modifiedAt: modifiedAt, preview: preview)
        touch(url)
        while order.count > limit {
            cache.removeValue(forKey: order.removeFirst())
        }
    }

    private func touch(_ url: URL) {
        order.removeAll { $0 == url }
        order.append(url)
    }
}

struct NotePreviewPopoverModifier: ViewModifier {
    let url: URL?
    @State private var isHovering = false
    @State private var isPopoverPresented = false
    @State private var hoverTask: Task<Void, Never>? = nil

    func body(content: Content) -> some View {
        if let url = url, url.pathExtension.lowercased() == "md" {
            content
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        hoverTask?.cancel()
                        hoverTask = Task {
                            try? await Task.sleep(for: .milliseconds(500))
                            guard !Task.isCancelled && isHovering else { return }
                            isPopoverPresented = true
                        }
                    } else {
                        hoverTask?.cancel()
                        isPopoverPresented = false
                    }
                }
                .popover(isPresented: $isPopoverPresented, arrowEdge: .trailing) {
                    NotePreviewPopover(url: url)
                }
        } else {
            content
        }
    }
}

extension View {
    func notePreviewPopover(url: URL?) -> some View {
        self.modifier(NotePreviewPopoverModifier(url: url))
    }
}
