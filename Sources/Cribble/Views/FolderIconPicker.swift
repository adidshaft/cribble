import SwiftUI

/// A sheet for choosing a native SF Symbol to use as a folder's sidebar icon.
struct FolderIconPicker: View {
    let folderName: String
    let currentSymbol: String?
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 46), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: currentSymbol ?? "folder")
                    .foregroundStyle(.tint)
                Text("Icon for “\(folderName)”")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    iconCell(symbol: "folder", isSelected: currentSymbol == nil, isDefault: true) {
                        onSelect(nil)
                        dismiss()
                    }
                    ForEach(Self.symbols, id: \.self) { symbol in
                        iconCell(symbol: symbol, isSelected: currentSymbol == symbol, isDefault: false) {
                            onSelect(symbol)
                            dismiss()
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 380, height: 440)
    }

    @ViewBuilder
    private func iconCell(symbol: String, isSelected: Bool, isDefault: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: 44, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05))
                )
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .help(isDefault ? "Default folder" : symbol)
    }

    // A curated set of native SF Symbols that read well at sidebar size.
    static let symbols: [String] = [
        "folder.fill", "folder.badge.gearshape", "tray.full", "archivebox", "shippingbox",
        "doc.text", "doc.richtext", "note.text", "text.book.closed", "book", "books.vertical",
        "newspaper", "bookmark", "tag", "list.bullet.rectangle", "checklist",
        "star", "heart", "flag", "bolt", "sparkles", "lightbulb", "flame", "leaf",
        "briefcase", "graduationcap", "backpack", "paintpalette", "pencil.and.ruler",
        "hammer", "wrench.and.screwdriver", "gearshape", "terminal", "curlybraces",
        "chevron.left.forwardslash.chevron.right", "cpu", "server.rack", "externaldrive",
        "photo", "photo.stack", "film", "music.note", "mic", "gamecontroller",
        "globe", "map", "mappin.and.ellipse", "calendar", "clock",
        "person", "person.2", "building.2", "house", "cup.and.saucer", "fork.knife",
        "airplane", "car", "figure.run", "dumbbell", "cross.case", "pills",
        "dollarsign.circle", "chart.bar", "chart.pie", "function", "brain", "atom"
    ]
}
