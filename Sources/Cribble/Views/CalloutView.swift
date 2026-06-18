import SwiftUI
import Textual

struct CalloutView: View {
    let callout: CalloutBlock
    let baseURL: URL
    let fontScale: Double
    let primaryFontName: String?
    let monospaceFontName: String?

    private var style: CalloutStyle {
        CalloutStyle.style(for: callout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: style.symbolName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(style.accent)
                    .frame(width: 18)

                Text(style.title)
                    .font(ReaderTypography.primary(primaryFontName, size: 14 * fontScale))
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if !callout.bodyMarkdown.isEmpty {
                StructuredText(markdown: callout.bodyMarkdown)
                    .font(ReaderTypography.primary(primaryFontName, size: 16 * fontScale))
                    .textual.structuredTextStyle(.gitHub)
                    .textual.lineSpacing(.fontScaled(0.25))
                    .textual.inlineStyle(
                        InlineStyle()
                            .code(.font(ReaderTypography.monospace(monospaceFontName, size: 13 * fontScale)))
                            .strong(.fontWeight(.semibold))
                    )
                    .textual.imageAttachmentLoader(.image(relativeTo: baseURL))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(style.accent.opacity(0.65))
                .frame(width: 3)
                .padding(.vertical, 10)
        }
        .padding(.leading, 2)
        .cribbleMaterialSurface(in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Callout, \(callout.type): \(style.title)")
    }
}
