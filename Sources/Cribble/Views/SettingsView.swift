import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

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
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 540)
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
