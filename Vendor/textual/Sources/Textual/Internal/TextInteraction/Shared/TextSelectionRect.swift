#if TEXTUAL_ENABLE_TEXT_SELECTION
  import SwiftUI

  public struct TextSelectionRect: Hashable, CustomStringConvertible {
    public var rect: CGRect

    public let layoutDirection: LayoutDirection
    public var containsStart: Bool
    public var containsEnd: Bool

    public var description: String {
      "(\(rect.logDescription), \(layoutDirection == .leftToRight ? "LTR" : "RTL"))"
    }

    public init(
      rect: CGRect,
      layoutDirection: LayoutDirection,
      containsStart: Bool = false,
      containsEnd: Bool = false
    ) {
      self.rect = rect
      self.layoutDirection = layoutDirection
      self.containsStart = containsStart
      self.containsEnd = containsEnd
    }

    public func offsetBy(dx: CGFloat, dy: CGFloat) -> TextSelectionRect {
      .init(
        rect: rect.offsetBy(dx: dx, dy: dy),
        layoutDirection: layoutDirection,
        containsStart: containsStart,
        containsEnd: containsEnd
      )
    }
  }
#endif
