import AppKit

/// Transparent, click-through window pinned just below the menu bar around the
/// status item's x-position. Watches for file drags entering its bounds so the
/// drop zone panel can appear *before* the cursor reaches the tiny icon.
///
/// Click-through: the window does NOT intercept normal mouse events — only drag
/// sessions, via NSDraggingDestination. Regular cursor movement passes through
/// to whatever is underneath.
final class ProximityDropWindow: NSPanel {
    var onDragEntered: (([URL]) -> Void)?
    var onDragExited: (() -> Void)?
    var onFilesDropped: (([URL], NSEvent.ModifierFlags) -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel    = true
        level              = .statusBar
        backgroundColor    = .clear
        isOpaque           = false
        hasShadow          = false
        ignoresMouseEvents = true  // pass through normal clicks/movement
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable          = false

        let view = ProximityView(frame: NSRect(x: 0, y: 0, width: 320, height: 80))
        view.onDragEntered  = { [weak self] urls in self?.onDragEntered?(urls) }
        view.onDragExited   = { [weak self] in self?.onDragExited?() }
        view.onFilesDropped = { [weak self] urls, mods in self?.onFilesDropped?(urls, mods) }
        contentView = view
    }

    /// Position the proximity window centered horizontally on the status item.
    func reposition(relativeTo statusItemButton: NSStatusBarButton) {
        guard let window = statusItemButton.window,
              let screen = window.screen ?? NSScreen.main else { return }

        let buttonRect = window.convertToScreen(
            statusItemButton.convert(statusItemButton.bounds, to: nil)
        )

        let width: CGFloat  = 320
        let height: CGFloat = 80
        let x = buttonRect.midX - width / 2
        let y = buttonRect.minY - height + 2  // overlap menu bar by 2pt for seamless entry

        let clampedX = max(screen.visibleFrame.minX,
                           min(x, screen.visibleFrame.maxX - width))
        setFrame(NSRect(x: clampedX, y: y, width: width, height: height), display: false)
    }
}

private final class ProximityView: NSView {
    var onDragEntered: (([URL]) -> Void)?
    var onDragExited:  (() -> Void)?
    var onFilesDropped: (([URL], NSEvent.ModifierFlags) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = pasteboardURLs(from: sender)
        onDragEntered?(urls)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = pasteboardURLs(from: sender)
        guard !urls.isEmpty else { return false }
        let modifiers = NSEvent.modifierFlags
        onFilesDropped?(urls, modifiers)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onDragExited?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Hit-test only for drag sessions — the parent window ignores mouse
        // events, so this is effectively drag-only.
        self
    }

    private func pasteboardURLs(from info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
    }
}
