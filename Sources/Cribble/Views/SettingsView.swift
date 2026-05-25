import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Reading") {
                HStack {
                    Text("Text size")
                    Slider(value: $settings.readerFontScale, in: 0.85...1.35, step: 0.05)
                    Text("\(Int(settings.readerFontScale * 100))%")
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
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
                    Button("Clear", action: settings.resetEditor)
                        .disabled(settings.editorApplicationURL == nil)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 520)
    }
}
