import SwiftUI
import Textual

struct ReaderView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if let document = library.selectedDocument {
                ReaderDocumentView(
                    document: document,
                    rendered: library.selectedRenderedMarkdown,
                    linkedFiles: library.selectedLinkedFiles,
                    showLinkedFileCards: settings.showLinkedFileCards,
                    fontScale: settings.readerFontScale,
                    isRunningAI: library.isRunningAI,
                    onSelectLink: { library.select(url: $0.url) },
                    onOpenURL: { library.handleOpenURL($0) },
                    onFillReadme: { provider in
                        library.runAILinking(provider: provider, mode: .updateReadme)
                    }
                )
                .id(document.url)
            } else {
                WelcomeView()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = library.statusMessage {
                HStack {
                    if library.isRunningAI {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
        }
    }
}

private struct ReaderDocumentView: View {
    let document: MarkdownDocument
    let rendered: String
    let linkedFiles: [LinkedFileSummary]
    let showLinkedFileCards: Bool
    let fontScale: Double
    let isRunningAI: Bool
    let onSelectLink: (LinkedFileSummary) -> Void
    let onOpenURL: (URL) -> OpenURLAction.Result
    let onFillReadme: (AIProvider) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(document.title)
                    .font(.custom("Roobert", size: 30 * fontScale))
                    .fontWeight(.semibold)
                    .textSelection(.enabled)

                if showLinkedFileCards, !linkedFiles.isEmpty {
                    LinkedFilesCardPanel(links: linkedFiles, onSelect: onSelectLink)
                }

                if document.isEssentiallyEmptyReadme {
                    EmptyReadmePanel(
                        folderName: document.url.deletingLastPathComponent().lastPathComponent,
                        isRunningAI: isRunningAI,
                        onFillReadme: onFillReadme
                    )
                } else if rendered.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.top, 8)
                } else {
                    StructuredText(
                        markdown: rendered,
                        baseURL: document.url.deletingLastPathComponent(),
                        syntaxExtensions: [.math]
                    )
                    .font(.custom("Roobert", size: 17 * fontScale))
                    .textual.structuredTextStyle(.gitHub)
                    .textual.inlineStyle(
                        InlineStyle()
                            .code(.font(.custom("Monaco", size: 14 * fontScale)))
                            .strong(.fontWeight(.semibold))
                    )
                    .textual.codeBlockStyle(CribbleCodeBlockStyle(fontSize: 13 * fontScale))
                    .textual.imageAttachmentLoader(.image(relativeTo: document.url.deletingLastPathComponent()))
                    .textual.textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 840, alignment: .leading)
            .padding(.horizontal, 42)
            .padding(.vertical, 34)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .environment(\.openURL, OpenURLAction { url in
            onOpenURL(url)
        })
        .backgroundExtensionEffect()
        .navigationTitle(document.title)
    }
}

private struct EmptyReadmePanel: View {
    let folderName: String
    let isRunningAI: Bool
    let onFillReadme: (AIProvider) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("This README is empty")
                        .font(.custom("Roobert", size: 17))
                        .fontWeight(.semibold)

                    Text("Generate a folder overview, contents list, and useful links from the Markdown files in \(folderName).")
                        .font(.custom("Roobert", size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                ForEach(AIProvider.allCases) { provider in
                    Button {
                        onFillReadme(provider)
                    } label: {
                        Label("Fill + Link with \(provider.rawValue)", systemImage: provider == .codex ? "terminal" : "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isRunningAI)
                    .help("Use \(provider.rawValue) \(provider.lowestModelName) to draft this README, then review the patch before applying")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LinkedFilesCardPanel: View {
    let links: [LinkedFileSummary]
    let onSelect: (LinkedFileSummary) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)

                    Image(systemName: "text.book.closed")
                        .foregroundStyle(.secondary)

                    Text("Linked files")
                        .font(.custom("Roobert", size: 14))
                        .fontWeight(.semibold)

                    Text("\(links.count)")
                        .font(.custom("Monaco", size: 10))
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .glassEffect(.regular, in: Capsule())

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse linked files" : "Expand linked files")

            if isExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(links) { link in
                        Button {
                            onSelect(link)
                        } label: {
                            LinkedFileCard(link: link)
                        }
                        .buttonStyle(.plain)
                        .help("Open \(link.title)")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct LinkedFileCard: View {
    let link: LinkedFileSummary

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.text")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(link.title)
                    .font(.custom("Roobert", size: 13))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(link.subtitle)
                    .font(.custom("Monaco", size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Text("MD")
                .font(.custom("Monaco", size: 10))
                .fontWeight(.bold)
                .foregroundStyle(.pink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.primary.opacity(0.045))
        }
    }
}

private struct CribbleCodeBlockStyle: StructuredText.CodeBlockStyle {
    let fontSize: Double

    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .font(.custom("Monaco", size: fontSize))
                .textual.lineSpacing(.fontScaled(0.25))
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        .textual.blockSpacing(.init(top: 8, bottom: 18))
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ContentUnavailableView {
            Label("Open a Markdown Folder", systemImage: "text.book.closed")
        } description: {
            Text("Cribble reads folders in place and keeps Markdown editing in your editor.")
        } actions: {
            Button("Open Folder") {
                library.chooseFolder(sortMode: settings.fileSortMode)
            }
            .controlSize(.large)
            .buttonStyle(.glassProminent)
            .help("Open a Markdown folder and keep it in the sidebar")
        }
    }
}
