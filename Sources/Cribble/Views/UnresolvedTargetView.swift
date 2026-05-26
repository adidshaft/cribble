import SwiftUI

struct UnresolvedTargetView: View {
    let target: UnresolvedTarget
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var settings: AppSettings

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
                        library.createDocument(named: target.targetName, in: target.folderURL)
                    } label: {
                        Label("Create Note", systemImage: "plus.circle")
                    }
                    .controlSize(.large)
                    .cribbleGlassButton(prominent: true)
                    .help("Create \(target.targetName).md in \(target.folderURL.lastPathComponent)")

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
}
