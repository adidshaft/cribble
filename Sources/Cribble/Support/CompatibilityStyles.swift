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

    func highlightModeCursor(_ isActive: Bool) -> some View {
        modifier(HighlightModeCursorModifier(isActive: isActive))
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

private struct HighlightModeCursorModifier: ViewModifier {
    let isActive: Bool
    @State private var isHovering = false
    @State private var didPushCursor = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                syncCursor()
            }
            .onChange(of: isActive) { _, _ in
                syncCursor()
            }
            .onDisappear {
                popCursorIfNeeded()
            }
    }

    private func syncCursor() {
        if isActive && isHovering {
            guard !didPushCursor else { return }
            NSCursor.cribbleHighlightLine.push()
            didPushCursor = true
        } else {
            popCursorIfNeeded()
        }
    }

    private func popCursorIfNeeded() {
        if didPushCursor {
            NSCursor.pop()
            didPushCursor = false
        }
    }
}

private extension NSCursor {
    @MainActor
    static let cribbleHighlightLine: NSCursor = {
        let size = NSSize(width: 9, height: 32)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let lineRect = NSRect(x: 4, y: 2, width: 1.5, height: 28)
        NSColor.labelColor.withAlphaComponent(0.92).setFill()
        lineRect.fill()

        NSColor.systemYellow.withAlphaComponent(0.7).setFill()
        NSRect(x: 3, y: 1, width: 3.5, height: 2).fill()
        NSRect(x: 3, y: 29, width: 3.5, height: 2).fill()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 4.5, y: 16))
    }()
}
