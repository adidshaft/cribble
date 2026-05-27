import AppKit
import SwiftUI

enum HighlightNotePopoverResult {
    case saved(String)
}

/// Small NSPopover-based note editor anchored to a selection rect. Replaces
/// the previous full-modal NSAlert with a tighter inline UI that appears
/// right next to the text the user just right-clicked.
enum HighlightNotePopover {
    @MainActor
    static func present(
        quote: String,
        initialNote: String,
        anchorView: NSView,
        anchorRect: NSRect,
        completion: @escaping (HighlightNotePopoverResult) -> Void
    ) {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let coordinator = NotePopoverCoordinator(initialNote: initialNote, completion: completion)

        let hosting = NSHostingController(
            rootView: HighlightNoteEditor(
                initialNote: initialNote,
                onChange: { [weak coordinator] note in
                    coordinator?.currentNote = note
                },
                onSave: { [weak popover] note in
                    coordinator.finalize(.saved(note))
                    popover?.performClose(nil)
                }
            )
        )
        popover.contentViewController = hosting
        popover.delegate = coordinator

        // Anchor to selection rect when we have one; otherwise to the
        // host view's bounds centroid. Either way the popover is small
        // and inline rather than a center-of-screen modal.
        let displayRect = anchorRect.isEmpty
            ? NSRect(x: anchorView.bounds.midX, y: anchorView.bounds.midY, width: 1, height: 1)
            : anchorRect
        popover.show(
            relativeTo: displayRect,
            of: anchorView,
            preferredEdge: .maxY
        )
        coordinator.retain(popover: popover)
    }
}

/// Holds the popover alive until it closes, and routes the close/cancel
/// path through one call to the host's completion handler.
@MainActor
private final class NotePopoverCoordinator: NSObject, NSPopoverDelegate {
    private var completion: ((HighlightNotePopoverResult) -> Void)?
    private var retainedPopover: NSPopover?
    var currentNote: String

    init(initialNote: String, completion: @escaping (HighlightNotePopoverResult) -> Void) {
        self.currentNote = initialNote
        self.completion = completion
    }

    func retain(popover: NSPopover) {
        retainedPopover = popover
        // Keep the coordinator alive as long as the popover is open by
        // associating it with the popover itself via objc associated
        // objects.
        objc_setAssociatedObject(
            popover,
            &Self.associationKey,
            self,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    func finalize(_ result: HighlightNotePopoverResult) {
        guard let completion else { return }
        self.completion = nil
        completion(result)
    }

    func popoverDidClose(_ notification: Notification) {
        finalize(.saved(currentNote))
        retainedPopover = nil
    }

    private static var associationKey: UInt8 = 0
}

private struct HighlightNoteEditor: View {
    let initialNote: String
    let onChange: (String) -> Void
    let onSave: (String) -> Void

    @State private var note: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add Note to highlight")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            ZStack(alignment: .bottomTrailing) {
                TextField("Write a note", text: $note, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(4...5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: 106, alignment: .topLeading)
                    .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.28), lineWidth: 0.75)
                    }
                    .focused($fieldFocused)
                    .onSubmit { onSave(note) }
                    .onChange(of: note) { _, newValue in
                        onChange(newValue)
                    }

                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 8)
                    .padding(.bottom, 7)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear {
            note = initialNote
            onChange(initialNote)
            fieldFocused = true
        }
    }
}
