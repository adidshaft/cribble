import AppKit
import SwiftUI

struct UnresolvedTargetView: View {
    let target: UnresolvedTarget
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings
    @State private var copiedWikiLink = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                        .padding(.bottom, 8)

                    Text("Missing Note")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("The note **\(target.targetName)** does not exist yet.")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Located in \(target.folderURL.lastPathComponent)")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 40)

                HStack(spacing: 14) {
                    Button {
                        library.proposeDocument(named: target.targetName, in: target.folderURL)
                    } label: {
                        Label("Create Note", systemImage: "plus.circle")
                    }
                    .controlSize(.large)
                    .cribbleGlassButton(prominent: true)
                    .help("Review a new \(target.targetName).md proposal before writing it")

                    Button {
                        copyMissingWikiLink()
                    } label: {
                        Label(copiedWikiLink ? "Copied Link" : "Copy Wiki Link",
                              systemImage: copiedWikiLink ? "checkmark" : "link")
                    }
                    .controlSize(.large)
                    .cribbleGlassButton()
                    .help("Copy [[\(target.targetName)]] for chat, tasks, or another note")

                    Button {
                        library.selectedUnresolvedTarget = nil
                        if let last = library.history.last {
                            library.select(url: last)
                        }
                    } label: {
                        Text("Go Back")
                    }
                    .controlSize(.large)
                    .cribbleGlassButton()
                }

                let matches = library.fuzzyMatches(for: target.targetName)
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Suggested Notes")
                            .font(.title3)
                            .fontWeight(.semibold)

                        LazyVStack(spacing: 10) {
                            ForEach(matches, id: \.url) { match in
                                Button {
                                    library.select(url: match.url)
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.text")
                                            .foregroundStyle(.blue)
                                            .font(.title3)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(match.title)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.primary)
                                            Text(match.url.deletingLastPathComponent().lastPathComponent)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.right.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(12)
                                    .background {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(.primary.opacity(0.04))
                                    }
                                }
                                .buttonStyle(.plain)
                                .pointingHandOnHover()
                            }
                        }
                    }
                    .frame(maxWidth: 480, alignment: .leading)
                    .padding(.top, 20)
                }
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 24)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .cribbleBackgroundExtension()
    }

    private func copyMissingWikiLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("[[\(target.targetName)]]", forType: .string)
        copiedWikiLink = true
        library.statusMessage = "Copied [[\(target.targetName)]]"
    }
}
