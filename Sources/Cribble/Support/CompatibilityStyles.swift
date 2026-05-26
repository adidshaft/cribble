import AppKit
import SwiftUI

extension View {
    @ViewBuilder
    func cribbleGlass<S: InsettableShape>(in shape: S) -> some View {
        #if compiler(>=6.1)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            fallbackGlass(in: shape)
        }
        #else
        fallbackGlass(in: shape)
        #endif
    }

    private func fallbackGlass<S: InsettableShape>(in shape: S) -> some View {
        self.background(.regularMaterial, in: shape)
            .overlay {
                shape.strokeBorder(.primary.opacity(0.08), lineWidth: 0.75)
            }
    }

    @ViewBuilder
    func cribbleGlassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.1)
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            fallbackGlassButton(prominent: prominent)
        }
        #else
        fallbackGlassButton(prominent: prominent)
        #endif
    }

    @ViewBuilder
    private func fallbackGlassButton(prominent: Bool) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func cribbleBackgroundExtension() -> some View {
        #if compiler(>=6.1)
        if #available(macOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self.background(.background)
        }
        #else
        self.background(.background)
        #endif
    }

    func pointingHandOnHover() -> some View {
        modifier(PointingHandOnHoverModifier())
    }
}

struct PointingHandOnHoverModifier: ViewModifier {
    @State private var didPushCursor = false

    func body(content: Content) -> some View {
        content.onHover { isHovering in
            if isHovering, !didPushCursor {
                NSCursor.pointingHand.push()
                didPushCursor = true
            } else if !isHovering, didPushCursor {
                NSCursor.pop()
                didPushCursor = false
            }
        }
        .onDisappear {
            if didPushCursor {
                NSCursor.pop()
                didPushCursor = false
            }
        }
    }
}
