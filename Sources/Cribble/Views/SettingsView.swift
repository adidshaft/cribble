import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Reading") {
                HStack {
                    Text("Text size")
                    Slider(value: $settings.readerFontScale, in: 0.65...1.65, step: 0.05)
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
        .frame(width: 520)
    }
}
