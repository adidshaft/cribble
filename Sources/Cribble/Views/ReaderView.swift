import SwiftUI
import Textual

struct ReaderView: View {
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if let document = library.selectedDocument {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(document.title)
                            .font(.custom("Roobert", size: 30 * settings.readerFontScale))
                            .fontWeight(.semibold)
                            .textSelection(.enabled)

                        if settings.showLinkedFileCards {
                            LinkedFilesStrip(links: library.linkedFilesForSelectedDocument()) { link in
                                library.select(url: link.url)
                            }
                        }

                        StructuredText(
                            markdown: library.renderedMarkdownForSelectedDocument(),
                            baseURL: document.url.deletingLastPathComponent(),
                            syntaxExtensions: [.math]
                        )
                            .font(.custom("Roobert", size: 17 * settings.readerFontScale))
                            .textual.structuredTextStyle(.gitHub)
                            .textual.inlineStyle(
                                InlineStyle()
                                    .code(.font(.custom("Monaco", size: 14 * settings.readerFontScale)))
                                    .strong(.fontWeight(.semibold))
                            )
                            .textual.codeBlockStyle(CribbleCodeBlockStyle(fontSize: 13 * settings.readerFontScale))
                            .textual.imageAttachmentLoader(.image(relativeTo: document.url.deletingLastPathComponent()))
                            .textual.textSelection(.enabled)
                    }
                    .frame(maxWidth: 840, alignment: .leading)
                    .padding(.horizontal, 42)
                    .padding(.vertical, 34)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .environment(\.openURL, OpenURLAction { url in
                    library.handleOpenURL(url)
                })
                .backgroundExtensionEffect()
                .navigationTitle(document.title)
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

private struct LinkedFilesStrip: View {
    let links: [LinkedFileSummary]
    let onSelect: (LinkedFileSummary) -> Void

    var body: some View {
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "text.book.closed")
                        .foregroundStyle(.secondary)
                    Text("Linked files")
                        .font(.custom("Roobert", size: 14))
                        .fontWeight(.semibold)
                    Rectangle()
                        .fill(.secondary.opacity(0.55))
                        .frame(width: 1, height: 14)
                }

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
            }
            .padding(12)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        }
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
