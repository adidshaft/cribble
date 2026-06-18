import SwiftUI
import Textual

struct CalloutView: View {
    let callout: CalloutBlock
    let baseURL: URL
    let fontScale: Double
    let primaryFontName: String?
    let monospaceFontName: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool

    init(
        callout: CalloutBlock,
        baseURL: URL,
        fontScale: Double,
        primaryFontName: String?,
        monospaceFontName: String?
    ) {
        self.callout = callout
        self.baseURL = baseURL
        self.fontScale = fontScale
        self.primaryFontName = primaryFontName
        self.monospaceFontName = monospaceFontName
        _isExpanded = State(initialValue: callout.isInitiallyExpanded)
    }

    private var style: CalloutStyle {
        CalloutStyle.style(for: callout)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isExpanded, !callout.bodyMarkdown.isEmpty {
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
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var header: some View {
        if callout.isFoldable {
            Button {
                let toggle = { isExpanded.toggle() }
                if reduceMotion {
                    toggle()
                } else {
                    withAnimation(.snappy(duration: 0.18)) {
                        toggle()
                    }
                }
            } label: {
                headerContent
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse callout" : "Expand callout")
        } else {
            headerContent
        }
    }

    private var headerContent: some View {
        HStack(spacing: 8) {
            if callout.isFoldable {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }

            Image(systemName: style.symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(style.accent)
                .frame(width: 18)

            Text(style.title)
                .font(ReaderTypography.primary(primaryFontName, size: 14 * fontScale))
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var accessibilityLabel: String {
        if callout.isFoldable {
            return "Callout, \(callout.type): \(style.title), \(isExpanded ? "expanded" : "collapsed")"
        }
        return "Callout, \(callout.type): \(style.title)"
    }
}
