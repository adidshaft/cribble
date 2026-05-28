#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
  import SwiftUI

  // MARK: - Overview
  //
  // `NSTextInteractionView` implements selection and link interaction on macOS.
  //
  // The view sits in an overlay above one or more rendered `Text` fragments. It uses
  // `TextSelectionModel` for hit testing and range manipulation, and it respects `exclusionRects`
  // so embedded scrollable regions continue to receive input events. Link taps are forwarded to
  // `openURL`.

  final class NSTextInteractionView: NSView {
    var model: TextSelectionModel
    var exclusionRects: [CGRect]
    var openURL: OpenURLAction
    // Closure that returns extra context-menu items to splice into the
    // selection menu (above the system Share/Copy items). Cribble uses this
    // to inject "Add/Edit Highlight Note" and friends — without it, Textual's
    // own NSMenu shadowed Cribble's SwiftUI `.contextMenu`.
    var additionalMenuItemsProvider: TextInteractionMenuItemProvider?
    var hoverHandler: TextInteractionHoverHandler?
    var hoverNoteRegions: [TextInteractionHoverNoteRegion] = []
    public var sectionAnchor: String?
    public var blockIndex: Int = 0
    public var blockSignature: String?

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    private var dragStart: TextPosition?
    private var selectionAnchor: TextPosition?
    private var hoverNotePopover: NSPopover?
    private var hoverNoteRegion: TextInteractionHoverNoteRegion?

    init(
      model: TextSelectionModel,
      exclusionRects: [CGRect],
      openURL: OpenURLAction,
      additionalMenuItemsProvider: TextInteractionMenuItemProvider? = nil,
      hoverHandler: TextInteractionHoverHandler? = nil,
      hoverNoteRegions: [TextInteractionHoverNoteRegion] = []
    ) {
      self.model = model
      self.exclusionRects = exclusionRects
      self.openURL = openURL
      self.additionalMenuItemsProvider = additionalMenuItemsProvider
      self.hoverHandler = hoverHandler
      self.hoverNoteRegions = hoverNoteRegions

      super.init(frame: .zero)
      self.wantsLayer = false
    }


    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      let localPoint = convert(point, from: superview)
      let isExcluded = exclusionRects.contains {
        $0.contains(localPoint)
      }

      if isExcluded {
        return nil
      } else {
        return super.hitTest(point)
      }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
      super.updateTrackingAreas()
      trackingAreas.forEach(removeTrackingArea)
      addTrackingArea(
        NSTrackingArea(
          rect: bounds,
          options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
          owner: self,
          userInfo: nil
        )
      )
    }

    override func mouseEntered(with event: NSEvent) {
      reportHover(event)
    }

    override func mouseMoved(with event: NSEvent) {
      reportHover(event)
    }

    override func mouseExited(with event: NSEvent) {
      hoverHandler?(nil)
      closeHoverNote()
    }

    override func mouseDown(with event: NSEvent) {
      window?.makeFirstResponder(self)
      let location = convert(event.locationInWindow, from: nil)

      switch event.clickCount {
      case 1:
        if let url = model.url(for: location) {
          openURL(url)
        } else {
          resetSelection()
        }
        dragStart = model.closestPosition(to: location)
      case 2:
        if let position = model.closestPosition(to: location) {
          model.selectedRange = model.wordRange(for: position)
        }
        dragStart = nil
      case 3:
        if let position = model.closestPosition(to: location) {
          model.selectedRange = model.blockRange(for: position)
        }
        dragStart = nil
      default:
        break
      }
    }

    override func mouseDragged(with event: NSEvent) {
      guard let dragStart else {
        return
      }

      let location = convert(event.locationInWindow, from: nil)

      guard let currentPosition = model.closestPosition(to: location) else {
        return
      }

      model.selectedRange = TextRange(from: dragStart, to: currentPosition)
      autoscroll(with: event)
    }

    override func mouseUp(with event: NSEvent) {
      dragStart = nil
    }

    override func rightMouseDown(with event: NSEvent) {
      let location = convert(event.locationInWindow, from: nil)
      updateSelectionForContextMenu(at: location)

      NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }

    private func reportHover(_ event: NSEvent) {
      let location = convert(event.locationInWindow, from: nil)
      if exclusionRects.contains(where: { $0.contains(location) }) {
        hoverHandler?(nil)
        closeHoverNote()
      } else {
        hoverHandler?(location)
        updateHoverNote(at: location)
      }
    }

    private func updateHoverNote(at location: CGPoint) {
      guard let region = hoverNoteRegions.first(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(location) }) else {
        closeHoverNote()
        return
      }

      if hoverNoteRegion == region, hoverNotePopover?.isShown == true {
        return
      }

      closeHoverNote()
      hoverNoteRegion = region

      let popover = NSPopover()
      popover.behavior = .semitransient
      popover.animates = true
      popover.contentSize = NSSize(width: 320, height: 112)
      popover.contentViewController = NSHostingController(
        rootView: TextInteractionHoverNoteCard(note: region.note)
      )
      popover.show(relativeTo: region.rect, of: self, preferredEdge: .maxY)
      hoverNotePopover = popover
    }

    private func closeHoverNote() {
      hoverNotePopover?.close()
      hoverNotePopover = nil
      hoverNoteRegion = nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
      let location = convert(event.locationInWindow, from: nil)
      updateSelectionForContextMenu(at: location)

      return makeContextMenu()
    }

    override func selectAll(_ sender: Any?) {
      model.selectedRange = TextRange(start: model.startPosition, end: model.endPosition)
    }

    override func keyDown(with event: NSEvent) {
      interpretKeyEvents([event])
    }

    override func moveRightAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.position(from: position, offset: 1)
      }
    }

    override func moveLeftAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.position(from: position, offset: -1)
      }
    }

    override func moveUpAndModifySelection(_ sender: Any?) {
      modifySelection { position, anchor in
        model.positionAbove(position, anchor: anchor)
      }
    }

    override func moveDownAndModifySelection(_ sender: Any?) {
      modifySelection { position, anchor in
        model.positionBelow(position, anchor: anchor)
      }
    }

    override func moveWordRightAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.nextWord(from: position)
      }
    }

    override func moveWordLeftAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.previousWord(from: position)
      }
    }

    override func moveParagraphBackwardAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.blockStart(for: position)
      }
    }

    override func moveParagraphForwardAndModifySelection(_ sender: Any?) {
      modifySelection { position, _ in
        model.blockEnd(for: position)
      }
    }

    private func updateSelectionForContextMenu(at location: CGPoint) {
      guard let position = model.closestPosition(to: location) else {
        resetSelection()
        return
      }

      if let selectedRange = model.selectedRange, selectedRange.contains(position) {
        // do nothing
        return
      }

      model.selectedRange = model.wordRange(for: position)
    }

    private func makeContextMenu() -> NSMenu {
      let contextMenu = NSMenu()

      guard let selectedRange = model.selectedRange, !selectedRange.isCollapsed else {
        return contextMenu
      }

      // Get the localized title for the share action
      let sharingPicker = NSSharingServicePicker(items: [])
      let shareActionTitle = sharingPicker.standardShareMenuItem.title

      // Get the localized title for the copy action
      let copyActionTitle =
        if let defaultMenu = NSTextView.defaultMenu,
          let copyAction = defaultMenu.items.first(where: { $0.action == #selector(copy(_:)) })
        {
          copyAction.title
        } else {
          NSLocalizedString("Copy", bundle: .main, comment: "")
        }

      // Host-provided items (e.g. Cribble's "Add/Edit Highlight Note")
      // appear first, then a separator, then the built-in Share / Copy
      // actions.
      if let provider = additionalMenuItemsProvider {
        let attributedText = model.attributedText(in: selectedRange)
        let selectedString = attributedText.string
        let selectionRects = model.selectionRects(for: selectedRange)
        // Bounds rect of the selection in our coord space — gives the host
        // a precise anchor for popovers.
        let anchorRect: NSRect = {
          guard let first = selectionRects.first?.rect else { return .zero }
          return selectionRects.dropFirst().reduce(first) { $0.union($1.rect) }
        }()
        let anchor = TextInteractionContextAnchor(
          view: self,
          selectionRect: anchorRect,
          selectionSnapshot: currentSelectionSnapshot()
        )
        let extras = provider(selectedString, anchor)
        if !extras.isEmpty {
          for extra in extras {
            contextMenu.addItem(TextInteractionMenuItem.makeNSMenuItem(extra))
          }
          contextMenu.addItem(.separator())
        }
      }

      contextMenu.addItem(
        .init(
          title: shareActionTitle,
          action: #selector(share(_:)),
          keyEquivalent: ""
        )
      )
      contextMenu.addItem(.separator())
      contextMenu.addItem(
        .init(
          title: copyActionTitle,
          action: #selector(copy(_:)),
          keyEquivalent: ""
        )
      )

      return contextMenu
    }

    private func modifySelection(
      _ transform: (_ position: TextPosition, _ anchor: TextPosition) -> TextPosition?
    ) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      // set anchor on first move
      selectionAnchor = selectionAnchor ?? selectedRange.start

      guard let selectionAnchor else {
        return
      }

      // modify the non-anchor end of the selection
      let position =
        selectionAnchor == selectedRange.start
        ? selectedRange.end
        : selectedRange.start

      guard let newPosition = transform(position, selectionAnchor) else {
        return
      }
      model.selectedRange = TextRange(from: selectionAnchor, to: newPosition)

      // scroll to make the new position visible
      let caretRect = model.caretRect(for: newPosition)
      scrollToVisible(caretRect)
    }

    private func resetSelection() {
      model.selectedRange = nil
      selectionAnchor = nil
    }

    @objc private func share(_ sender: Any?) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      let attributedText = model.attributedText(in: selectedRange)
      let transferableText = TransferableText(attributedString: attributedText)
      let itemProvider = NSItemProvider(object: transferableText)

      let sharingPicker = NSSharingServicePicker(items: [itemProvider])
      let rect =
        model.selectionRects(for: selectedRange)
        .last?.rect.integral ?? .zero

      sharingPicker.show(relativeTo: rect, of: self, preferredEdge: .maxY)
    }

    @objc private func copy(_ sender: Any?) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      let attributedText = model.attributedText(in: selectedRange)

      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()

      let formatter = Formatter(attributedText)
      pasteboard.setString(formatter.plainText(), forType: .string)
      pasteboard.setString(formatter.html(), forType: .html)
    }
  }

  extension NSTextInteractionView: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
      switch item.action {
      case #selector(selectAll(_:)):
        return model.hasText
      case #selector(copy(_:)):
        guard let selectedRange = model.selectedRange else {
          return false
        }
        return !selectedRange.isCollapsed
      case #selector(moveRightAndModifySelection(_:)),
        #selector(moveLeftAndModifySelection(_:)),
        #selector(moveUpAndModifySelection(_:)),
        #selector(moveDownAndModifySelection(_:)),
        #selector(moveWordRightAndModifySelection(_:)),
        #selector(moveWordLeftAndModifySelection(_:)),
        #selector(moveParagraphBackwardAndModifySelection(_:)),
        #selector(moveParagraphForwardAndModifySelection(_:)):
        return model.selectedRange != nil
      default:
        return true
      }
    }
  }

  private struct TextInteractionHoverNoteCard: View {
    let note: String

    var body: some View {
      VStack(alignment: .leading, spacing: 8) {
        Text("Highlight Note")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)

        Text(note)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.primary.opacity(0.86))
          .lineLimit(5)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(14)
      .frame(width: 320, alignment: .leading)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
          .strokeBorder(.white.opacity(0.18))
      }
      .shadow(color: .black.opacity(0.28), radius: 24, y: 14)
    }
  }

public struct TextInteractionSelectionSnapshot {
  public let plainText: String              // exact rendered text — no bullet injection
  public let attributed: AttributedString
  public let characterRange: NSRange        // UTF-16 offset within this view's full text
  public let blockPlainText: String         // full plain text of this view's content
  public let blockSignature: String         // SHA-256/FNV-1a hash of blockPlainText
  public let view: NSView                   // the NSTextInteractionView (use NSView to keep type internal-friendly)
  public let unionRect: NSRect              // bounds of the selection in `view` coords
  public let sectionAnchor: String?
  public let blockIndex: Int
}

extension NSTextInteractionView {
  @MainActor public func currentSelectionSnapshot() -> TextInteractionSelectionSnapshot? {
    guard let range = model.selectedRange, !range.isCollapsed else { return nil }
    let attributed = AttributedString(model.attributedText(in: range))
    let plainText = attributed.characters.reduce(into: "") { $0.append($1) }
    let fullRange = TextRange(start: model.startPosition, end: model.endPosition)
    let blockPlain = model.text(in: fullRange)
    let startUTF16 = model.offset(from: model.startPosition, to: range.start)
    let lengthUTF16 = model.offset(from: range.start, to: range.end)
    let signature = blockSignature ?? TextInteractionSelectionSnapshot.signature(for: blockPlain)
    let union = model.selectionRects(for: range)
      .map(\.rect)
      .reduce(NSRect.null) { $0.union($1) }
    return TextInteractionSelectionSnapshot(
      plainText: plainText,
      attributed: attributed,
      characterRange: NSRange(location: startUTF16, length: lengthUTF16),
      blockPlainText: blockPlain,
      blockSignature: signature,
      view: self,
      unionRect: union.isNull ? .zero : union,
      sectionAnchor: self.sectionAnchor,
      blockIndex: self.blockIndex
    )
  }
}

extension TextInteractionSelectionSnapshot {
  public static func characterRange(in text: String, startUTF16: Int, lengthUTF16: Int) -> NSRange? {
    guard startUTF16 >= 0, lengthUTF16 >= 0,
          let lowerUTF16 = text.utf16.index(text.utf16.startIndex, offsetBy: startUTF16, limitedBy: text.utf16.endIndex),
          let upperUTF16 = text.utf16.index(lowerUTF16, offsetBy: lengthUTF16, limitedBy: text.utf16.endIndex),
          let lower = String.Index(lowerUTF16, within: text),
          let upper = String.Index(upperUTF16, within: text)
    else {
      return nil
    }

    let start = text.distance(from: text.startIndex, to: lower)
    let length = text.distance(from: lower, to: upper)
    return NSRange(location: start, length: length)
  }

  public static func signature(for text: String) -> String {
    // Stable hash of the first 64 UTF-8 bytes of normalized text
    let normalized = text.normalizedSelectionText
    var slice = ArraySlice(normalized.utf8)
    if slice.count > 64 { slice = slice.prefix(64) }
    var hash: UInt64 = 1469598103934665603 // FNV-1a
    for byte in slice { hash ^= UInt64(byte); hash &*= 1099511628211 }
    return String(hash, radix: 16)
  }
}

@MainActor
public func currentlyFocusedTextInteractionSnapshot() -> TextInteractionSelectionSnapshot? {
  guard let window = NSApp.keyWindow else { return nil }
  var responder: NSResponder? = window.firstResponder
  while let current = responder {
    if let view = current as? NSTextInteractionView { return view.currentSelectionSnapshot() }
    responder = current.nextResponder
  }
  // Fallback: walk content view subtree looking for any NSTextInteractionView
  // with a non-empty selection.
  if let root = window.contentView {
    return firstSelectedSnapshot(in: root)
  }
  return nil
}

@MainActor
private func firstSelectedSnapshot(in view: NSView) -> TextInteractionSelectionSnapshot? {
  if let candidate = view as? NSTextInteractionView,
     let snapshot = candidate.currentSelectionSnapshot() {
    return snapshot
  }
  for sub in view.subviews {
    if let snapshot = firstSelectedSnapshot(in: sub) { return snapshot }
  }
  return nil
}

private extension String {
  var normalizedSelectionText: String {
    lowercased()
      .map { character in
        if character.isLetter || character.isNumber || character.isWhitespace {
          return character
        }
        return " "
      }
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)
      .joined(separator: " ")
  }
}

#endif
