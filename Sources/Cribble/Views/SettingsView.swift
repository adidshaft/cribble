import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: MarkdownLibraryStore
    @EnvironmentObject private var extensionRegistry: ExtensionRegistry
    @State private var extensionStatus: String?

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Fonts") {
                FontFamilyPicker(
                    title: "Primary Text",
                    selection: $settings.readerFontName,
                    families: SystemFonts.families
                )
                FontFamilyPicker(
                    title: "Monospace",
                    selection: $settings.monospaceFontName,
                    families: SystemFonts.monospaceFamilies
                )
                Text("Used for document text and code. Choose any font installed on your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Reading") {
                HStack {
                    Text("Text size")
                    Slider(value: $settings.readerFontScale, in: 0.55...1.3, step: 0.05)
                        .help("Fine-tune reader text size")
                    Text("\(Int(settings.readerFontScale * 100))%")
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }

                Picker("Text size preset", selection: Binding(
                    get: { ReaderFontSizePreset.closest(to: settings.readerFontScale) },
                    set: { settings.setFontSize($0) }
                )) {
                    ForEach(ReaderFontSizePreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }

                Picker("Sort files by", selection: $settings.fileSortMode) {
                    ForEach(FileSortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Toggle("Show linked file cards", isOn: $settings.showLinkedFileCards)
                    .help("Show a compact linked-files strip above each Markdown document")

                Toggle("Load remote images", isOn: $settings.loadRemoteImages)
                    .help("When off, http(s) images in notes appear as click-to-open links instead of loading automatically — keeping your reading private (no IP leak to remote hosts).")
            }

            Section("External Editor") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default editor")
                        Text(settings.editorApplicationURL?.lastPathComponent ?? "No editor selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose...", action: settings.chooseEditor)
                        .help("Choose the app Cribble uses for external Markdown editing")
                    Button("Clear", action: settings.resetEditor)
                        .disabled(settings.editorApplicationURL == nil)
                        .help("Clear the configured external editor")
                }
            }

            Section("Extensions") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Extension folders", systemImage: "puzzlepiece.extension")
                        Spacer()
                        Button("Reveal", action: extensionRegistry.revealUserExtensionsFolder)
                            .help("Open Cribble's user extension folder in Finder")
                        Button("Create Example") {
                            do {
                                let url = try extensionRegistry.writeExampleManifest()
                                extensionStatus = "Created \(url.deletingLastPathComponent().lastPathComponent)"
                                extensionRegistry.reload(projectRoots: library.rootURLs)
                            } catch {
                                extensionStatus = error.localizedDescription
                            }
                        }
                        .help("Write a starter cribble-extension.json manifest")
                    }

                    Text("Cribble discovers extension manifests in Application Support and each opened folder's .cribble/extensions directory. API v1 extensions are declarative: manifests are loaded and validated, but extension code is not executed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if extensionRegistry.installedExtensions.isEmpty {
                        ContentUnavailableView(
                            "No Extensions Installed",
                            systemImage: "puzzlepiece.extension",
                            description: Text("Create an example manifest to start designing one.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(extensionRegistry.installedExtensions) { installed in
                                ExtensionManifestRow(
                                    extension: installed,
                                    isEnabled: extensionRegistry.isEnabled(installed),
                                    onEnabledChange: { enabled in
                                        extensionRegistry.setEnabled(enabled, for: installed)
                                    }
                                )
                            }
                        }
                    }

                    if !extensionRegistry.loadWarnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(extensionRegistry.loadWarnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    if let extensionStatus {
                        Text(extensionStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 620)
        .onAppear {
            extensionRegistry.reload(projectRoots: library.rootURLs)
        }
        .onChange(of: library.rootURLs) { _, roots in
            extensionRegistry.reload(projectRoots: roots)
        }
    }
}

private struct ExtensionManifestRow: View {
    let `extension`: InstalledCribbleExtension
    let isEnabled: Bool
    let onEnabledChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(`extension`.manifest.name)
                        .font(.body.weight(.medium))
                    Text(`extension`.manifest.version)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(`extension`.manifest.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(`extension`.manifest.kind.title) • \(`extension`.manifest.runtime.title) • \(`extension`.location.title)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(`extension`.manifest.runtime.summary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if !`extension`.manifest.permissions.isEmpty {
                    Text(`extension`.manifest.permissions.map(\.title).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let contributionSummary {
                    Text(contributionSummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            Toggle("Enabled", isOn: Binding(
                get: { isEnabled },
                set: { enabled in onEnabledChange(enabled) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch `extension`.manifest.kind {
        case .quickAction: "bolt"
        case .intelligenceProvider: "brain.head.profile"
        case .renderer: "doc.richtext"
        case .importer: "square.and.arrow.down"
        }
    }

    private var contributionSummary: String? {
        let manifest = `extension`.manifest
        if !manifest.quickActions.isEmpty {
            return "Actions: " + manifest.quickActions.map(\.title).joined(separator: ", ")
        }
        if !manifest.intelligenceProviders.isEmpty {
            return "Providers: " + manifest.intelligenceProviders.map { "\($0.title) (\($0.modelID))" }.joined(separator: ", ")
        }
        if !manifest.renderers.isEmpty {
            return "Renderers: " + manifest.renderers.map { "\($0.title) [" + $0.languages.joined(separator: ", ") + "]" }.joined(separator: ", ")
        }
        if !manifest.importers.isEmpty {
            return "Importers: " + manifest.importers.map { "\($0.title) [" + $0.fileExtensions.joined(separator: ", ") + "]" }.joined(separator: ", ")
        }
        return nil
    }
}

private struct FontFamilyPicker: View {
    let title: String
    @Binding var selection: String?
    let families: [String]

    var body: some View {
        Picker(title, selection: $selection) {
            Text("System Default").tag(String?.none)
            Divider()
            ForEach(families, id: \.self) { family in
                Text(family).tag(String?.some(family))
            }
        }
    }
}

/// Cached lists of installed font families for the pickers.
private enum SystemFonts {
    static let families: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    static let monospaceFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { family in
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  let postScriptName = members.first?.first as? String,
                  let font = NSFont(name: postScriptName, size: 12)
            else { return false }
            return font.isFixedPitch
        }
        .sorted()
}
