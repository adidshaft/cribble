import SwiftUI

extension View {
    @ViewBuilder
    func cribbleGlass<S: InsettableShape>(in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.75)
                }
        }
    }

    @ViewBuilder
    func cribbleGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    func cribbleBackgroundExtension() -> some View {
        if #available(macOS 26.0, *) {
            backgroundExtensionEffect()
        } else {
            background(.background)
        }
    }
}
