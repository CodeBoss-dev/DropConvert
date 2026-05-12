import AppKit

/// Transparent NSView overlaid on the status bar button to intercept file drags.
final class DropTargetView: NSView {
    var onDragEntered: (() -> Void)?
    var onDragExited:  (() -> Void)?
    /// Called synchronously on drop; `modifierFlags` is captured at that exact moment.
    var onFilesDropped: (([URL], NSEvent.ModifierFlags) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        // Capture modifier state here — synchronously, before any async work begins.
        let modifiers = NSEvent.modifierFlags
        onFilesDropped?(urls, modifiers)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    // Allow the view to be hit-tested even though it's transparent.
    override func hitTest(_ point: NSPoint) -> NSView? { self }
}
