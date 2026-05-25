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
