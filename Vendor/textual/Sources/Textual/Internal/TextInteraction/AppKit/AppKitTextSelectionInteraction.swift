#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
  import SwiftUI

  // MARK: - Overview
  //
  // `AppKitTextSelectionInteraction` presents the platform-specific text selection overlay for macOS.
  //
  // The modifier receives a `TextSelectionModel` and places it in the environment so selection highlights
  // and attachment dimming can access it. An overlay hosts `AppKitTextInteractionOverlay`, which wraps an
  // `NSView` that handles selection gestures and context menus. The modifier also manages cursor updates,
  // switching between I-beam and pointing hand based on hover position over text or links.

  typealias PlatformTextSelectionInteraction = AppKitTextSelectionInteraction

  struct AppKitTextSelectionInteraction: ViewModifier {
    @State private var cursorPushed = false
    // Honored when set: replaces the default I-beam/pointing-hand selection
    // cursor with a host-supplied cursor (e.g. Cribble's highlight-mode
    // marker). Without this override, the host's outer NSCursor.push() was
    // immediately stomped by `cursor.set()` on every continuous-hover
    // sample, so any custom cursor never appeared over actual text.
    @Environment(\.textInteractionCursorOverride) private var cursorOverride
    @Environment(\.textInteractionCursorRegions) private var cursorRegions

    private let model: TextSelectionModel

    init(model: TextSelectionModel) {
      self.model = model
    }

    func body(content: Content) -> some View {
      content
        // We need the selection model at text fragment level for the
        // text selection background and selected attachment dimming
        .environment(model)
        .overlayPreferenceValue(OverflowFrameKey.self) { frames in
          AppKitTextInteractionOverlay(model: model, overflowFrames: frames)
            .onContinuousHover { phase in
              updateCursor(for: phase, model: model)
            }
        }
    }

    private func updateCursor(for phase: HoverPhase, model: TextSelectionModel) {
      switch phase {
      case .active(let location):
        let cursor: NSCursor
        if let regionCursor = cursorRegions.first(where: { $0.rect.contains(location) })?.cursor {
          cursor = regionCursor
        } else if let override = cursorOverride {
          cursor = override
        } else {
          cursor =
            model.url(for: location) != nil
            ? NSCursor.pointingHand
            : NSCursor.iBeam
        }
        if !cursorPushed {
          cursor.push()
          cursorPushed = true
        } else {
          cursor.set()
        }
      case .ended:
        if cursorPushed {
          NSCursor.pop()
          cursorPushed = false
        }
      }
    }
  }

  private struct TextInteractionCursorOverrideKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: NSCursor? = nil
  }

  extension EnvironmentValues {
    /// When non-nil, AppKitTextSelectionInteraction uses this cursor over
    /// text instead of the default I-beam/pointing-hand pair. Public to the
    /// Textual module so host apps can drive highlight-mode cursors etc.
    public var textInteractionCursorOverride: NSCursor? {
      get { self[TextInteractionCursorOverrideKey.self] }
      set { self[TextInteractionCursorOverrideKey.self] = newValue }
    }
  }

  public struct TextInteractionCursorRegion {
    public let rect: NSRect       // in the AppKitTextInteractionOverlay's coord space
    public let cursor: NSCursor
    public init(rect: NSRect, cursor: NSCursor) { self.rect = rect; self.cursor = cursor }
  }

  private struct TextInteractionCursorRegionsKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: [TextInteractionCursorRegion] = []
  }

  private struct TextInteractionSectionAnchorKey: EnvironmentKey {
    static let defaultValue: String? = nil
  }

  private struct TextInteractionBlockIndexKey: EnvironmentKey {
    static let defaultValue: Int = 0
  }

  extension EnvironmentValues {
    public var textInteractionCursorRegions: [TextInteractionCursorRegion] {
      get { self[TextInteractionCursorRegionsKey.self] }
      set { self[TextInteractionCursorRegionsKey.self] = newValue }
    }
    public var textInteractionSectionAnchor: String? {
      get { self[TextInteractionSectionAnchorKey.self] }
      set { self[TextInteractionSectionAnchorKey.self] = newValue }
    }
    public var textInteractionBlockIndex: Int {
      get { self[TextInteractionBlockIndexKey.self] }
      set { self[TextInteractionBlockIndexKey.self] = newValue }
    }
  }

  public struct TextSelectionModelPreferenceKey: PreferenceKey {
    nonisolated(unsafe) public static let defaultValue: TextSelectionModel? = nil
    public static func reduce(value: inout TextSelectionModel?, nextValue: () -> TextSelectionModel?) {
      value = value ?? nextValue()
    }
  }

  /// A single context-menu entry contributed by the host application.
  /// Textual builds the underlying `NSMenuItem` so host code stays free of
  /// AppKit menu-target plumbing; the closure is invoked on the main actor
  /// when the user selects the item.
  public struct TextInteractionMenuItem {
    public let title: String
    public let handler: @MainActor () -> Void

    public init(title: String, handler: @escaping @MainActor () -> Void) {
      self.title = title
      self.handler = handler
    }

    static func makeNSMenuItem(_ item: TextInteractionMenuItem) -> NSMenuItem {
      let menuItem = ClosureMenuItem(title: item.title, handler: item.handler)
      return menuItem
    }
  }

  /// Anchor information passed to the menu-item provider so the host can
  /// position a popover (or similar UI) at the exact location of the
  /// right-click that triggered the menu.
  public struct TextInteractionContextAnchor {
    public let view: NSView
    /// Bounding rect of the current selection in `view`'s coordinate space.
    /// Falls back to a 1x1 rect at the click point when nothing is selected.
    public let selectionRect: NSRect

    public init(view: NSView, selectionRect: NSRect) {
      self.view = view
      self.selectionRect = selectionRect
    }
  }

  private final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
      self.handler = handler
      super.init(title: title, action: nil, keyEquivalent: "")
      self.target = self
      self.action = #selector(invoke)
    }

    required init(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    @MainActor @objc private func invoke() {
      handler()
    }
  }

  public typealias TextInteractionMenuItemProvider =
    @MainActor (_ selection: String, _ anchor: TextInteractionContextAnchor) -> [TextInteractionMenuItem]

  private struct TextInteractionAdditionalMenuItemsKey: EnvironmentKey {
    static let defaultValue: TextInteractionMenuItemProvider? = nil
  }

  extension EnvironmentValues {
    /// When set, Textual splices the items returned by this closure into
    /// the selection context menu (above Share / Copy). The closure receives
    /// the currently selected plain text and an anchor describing where
    /// the menu was invoked so hosts can present popovers, etc.
    public var textInteractionAdditionalMenuItems: TextInteractionMenuItemProvider? {
      get { self[TextInteractionAdditionalMenuItemsKey.self] }
      set { self[TextInteractionAdditionalMenuItemsKey.self] = newValue }
    }
  }

#endif
