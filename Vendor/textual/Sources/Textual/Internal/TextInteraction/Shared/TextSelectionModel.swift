#if TEXTUAL_ENABLE_TEXT_SELECTION
  import SwiftUI

  // MARK: - Overview
  //
  // `TextSelectionModel` is the shared state object that backs selection and interaction.
  //
  // Platform views (AppKit/UIKit) mutate `selectedRange` in response to gestures and editing
  // commands. The model delegates layout-specific work to a `TextLayoutCollection`, which can be
  // rebuilt at any time as SwiftUI resolves new `Text.Layout` values. When the layout collection
  // changes, the model attempts to reconcile the current selection into the new layout so the
  // selection stays stable across updates.

  @Observable
  public final class TextSelectionModel {
    public var selectedRange: TextRange? {
      willSet {
        selectionWillChange?()
      }
      didSet {
        if selectedRange != nil {
          coordinator?.modelDidSelectText(self)
        }
        selectionDidChange?()
      }
    }

    @ObservationIgnored
    var selectionWillChange: (() -> Void)?

    @ObservationIgnored
    var selectionDidChange: (() -> Void)?

    @ObservationIgnored
    private var layoutCollection: any TextLayoutCollection

    @ObservationIgnored
    private weak var coordinator: TextSelectionCoordinator?

    public convenience init() {
      self.init(layoutCollection: EmptyTextLayoutCollection(), coordinator: nil)
    }

    init(
      layoutCollection: any TextLayoutCollection = EmptyTextLayoutCollection(),
      coordinator: TextSelectionCoordinator? = nil
    ) {
      self.layoutCollection = layoutCollection
      setCoordinator(coordinator)
    }

    func setLayoutCollection(_ layoutCollection: any TextLayoutCollection) {
      guard !layoutCollection.isEqual(to: self.layoutCollection) else {
        return
      }

      let oldLayoutCollection = self.layoutCollection
      self.layoutCollection = layoutCollection

      guard
        let selectedRange,
        layoutCollection.needsPositionReconciliation(with: oldLayoutCollection)
      else {
        return
      }

      // Try to reconcile the selected text range
      self.selectedRange = layoutCollection.reconcileRange(
        selectedRange,
        from: oldLayoutCollection
      )
    }

    func setCoordinator(_ coordinator: TextSelectionCoordinator?) {
      if self.coordinator === coordinator {
        return
      }

      self.coordinator = coordinator
      coordinator?.register(self)
    }

    func url(for point: CGPoint) -> URL? {
      layoutCollection.url(for: point)
    }

    func layoutIndex(of layout: Text.Layout) -> Int? {
      layoutCollection.index(of: layout)
    }
  }

  extension TextSelectionModel {
    public var hasText: Bool {
      layoutCollection.stringLength > 0
    }

    public var startPosition: TextPosition {
      layoutCollection.startPosition
    }

    public var endPosition: TextPosition {
      layoutCollection.endPosition
    }

    public func attributedText(in range: TextRange) -> NSAttributedString {
      layoutCollection.attributedText(in: range)
    }

    public func text(in range: TextRange) -> String {
      attributedText(in: range).string
    }

    public func position(from position: TextPosition, offset: Int) -> TextPosition? {
      layoutCollection.position(from: position, offset: offset)
    }

    public func offset(from: TextPosition, to: TextPosition) -> Int {
      layoutCollection.characterIndex(at: to) - layoutCollection.characterIndex(at: from)
    }

    func firstRect(for range: TextRange) -> CGRect {
      layoutCollection.firstRect(for: range)
    }

    func caretRect(for position: TextPosition) -> CGRect {
      layoutCollection.caretRect(for: position)
    }

    public func selectionRects(for range: TextRange) -> [TextSelectionRect] {
      layoutCollection.selectionRects(for: range)
    }

    public func selectionRects(for range: TextRange, layout: Text.Layout) -> [TextSelectionRect] {
      layoutCollection.selectionRects(for: range, layout: layout)
    }

    public func closestPosition(to point: CGPoint) -> TextPosition? {
      layoutCollection.closestPosition(to: point)
    }

    func closestPosition(to point: CGPoint, within range: TextRange) -> TextPosition? {
      guard let position = closestPosition(to: point) else { return nil }
      if position <= range.start { return range.start }
      if position >= range.end { return range.end }
      return position
    }

    func isPositionAtBlockBoundary(_ position: TextPosition) -> Bool {
      layoutCollection.isPositionAtBlockBoundary(position)
    }

    func positionAbove(_ position: TextPosition, anchor: TextPosition) -> TextPosition? {
      layoutCollection.positionAbove(position, anchor: anchor)
    }

    func positionBelow(_ position: TextPosition, anchor: TextPosition) -> TextPosition? {
      layoutCollection.positionBelow(position, anchor: anchor)
    }

    func characterRange(at point: CGPoint) -> TextRange? {
      layoutCollection.characterRange(at: point)
    }

    func blockStart(for position: TextPosition) -> TextPosition? {
      layoutCollection.blockStart(for: position)
    }

    func blockEnd(for position: TextPosition) -> TextPosition? {
      layoutCollection.blockEnd(for: position)
    }

    func blockRange(for position: TextPosition) -> TextRange? {
      layoutCollection.blockRange(for: position)
    }

    @available(macOS 10.0, *)
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    func wordRange(for position: TextPosition) -> TextRange? {
      layoutCollection.wordRange(for: position)
    }

    @available(macOS 10.0, *)
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    func nextWord(from position: TextPosition) -> TextPosition? {
      layoutCollection.nextWord(from: position)
    }

    @available(macOS 10.0, *)
    @available(iOS, unavailable)
    @available(visionOS, unavailable)
    func previousWord(from position: TextPosition) -> TextPosition? {
      layoutCollection.previousWord(from: position)
    }
  }

  extension TextSelectionModel: Equatable {
    public static func == (lhs: TextSelectionModel, rhs: TextSelectionModel) -> Bool {
      lhs === rhs
    }
  }
#endif
