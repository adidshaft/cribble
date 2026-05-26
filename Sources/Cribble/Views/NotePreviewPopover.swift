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
            // Check if we already have it in library documents
            if let doc = await MainActor.run(body: { library.documents.first(where: { $0.url == url }) }) {
                title = doc.title
                previewText = cleanPreview(doc.rawMarkdown)
                isLoading = false
            } else {
                // Read from disk asynchronously
                do {
                    let doc = try DocumentLoader().load(url: url)
                    title = doc.title
                    previewText = cleanPreview(doc.rawMarkdown)
                } catch {
                    title = url.deletingPathExtension().lastPathComponent
                    previewText = "Could not load preview context."
                }
                isLoading = false
            }
        }
    }

    private func cleanPreview(_ markdown: String) -> String {
        let cleaned = MarkdownDisplayPreprocessor.prepare(markdown, documentTitle: "")
        // Basic Markdown syntax stripping
        let noSyntax = cleaned
            .replacingOccurrences(of: #"[#*`_\-\[\]\(\)]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return String(noSyntax.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
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
