import AppKit
import SwiftUI

enum HighlightNotePopoverResult {
    case cancelled
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

        let coordinator = NotePopoverCoordinator(completion: completion)

        let hosting = NSHostingController(
            rootView: HighlightNoteEditor(
                quote: quote,
                initialNote: initialNote,
                onSave: { [weak popover] note in
                    coordinator.finalize(.saved(note))
                    popover?.performClose(nil)
                },
                onCancel: { [weak popover] in
                    coordinator.finalize(.cancelled)
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

    init(completion: @escaping (HighlightNotePopoverResult) -> Void) {
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
        // If the popover was dismissed by clicking outside (no save/cancel
        // tapped), treat it as a cancel so the caller sees a deterministic
        // result.
        finalize(.cancelled)
        retainedPopover = nil
    }

    private static var associationKey: UInt8 = 0
}

private struct HighlightNoteEditor: View {
    let quote: String
    let initialNote: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var note: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\u{201C}\(quote.prefix(120))\u{201D}")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)

            TextField("Add a note", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
                .focused($fieldFocused)
                .onSubmit { onSave(note) }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button(initialNote.isEmpty ? "Save" : "Update") {
                    onSave(note)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear {
            note = initialNote
            fieldFocused = true
        }
    }
}
