import AppKit
import UniformTypeIdentifiers

/// Floating glass-style panel that appears below the menu bar icon when a file
/// is dragged near it. Also accepts drops directly so the user can release on
/// the panel itself instead of aiming for the small status icon.
final class DropZonePanel: NSPanel {
    /// Callback when files are dropped on the panel itself.
    var onFilesDropped: (([URL], NSEvent.ModifierFlags) -> Void)?

    static let preferredSize = NSSize(width: 300, height: 140)

    private let glass: NSVisualEffectView
    private let iconView: NSImageView
    private let primaryLabel: NSTextField
    private let secondaryLabel: NSTextField
    private let dropTarget: PanelDropTargetView

    init(contentRect: NSRect) {
        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: contentRect.size))
        glass.material      = .hudWindow
        glass.blendingMode  = .behindWindow
        glass.state         = .active
        glass.wantsLayer    = true
        glass.layer?.cornerRadius   = 20
        glass.layer?.cornerCurve    = .continuous
        glass.layer?.masksToBounds  = true

        // Soft inner highlight border — the "glass edge"
        let border = CALayer()
        border.frame = glass.bounds
        border.cornerRadius  = 20
        border.cornerCurve   = .continuous
        border.borderWidth   = 1
        border.borderColor   = NSColor.white.withAlphaComponent(0.18).cgColor
        border.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        glass.layer?.addSublayer(border)

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .controlAccentColor
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 28, weight: .semibold)
        iconView.image = NSImage(
            systemSymbolName: "arrow.down.to.line.compact",
            accessibilityDescription: "Drop here"
        )?.withSymbolConfiguration(iconConfig)

        let primaryLabel = NSTextField(labelWithString: "Drop to convert")
        primaryLabel.font      = .systemFont(ofSize: 15, weight: .semibold)
        primaryLabel.textColor = .labelColor
        primaryLabel.alignment = .center
        primaryLabel.translatesAutoresizingMaskIntoConstraints = false

        let secondaryLabel = NSTextField(labelWithString: "Drag a supported file here")
        secondaryLabel.font      = .systemFont(ofSize: 12, weight: .regular)
        secondaryLabel.textColor = .secondaryLabelColor
        secondaryLabel.alignment = .center
        secondaryLabel.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [iconView, primaryLabel, secondaryLabel])
        stack.orientation = .vertical
        stack.alignment   = .centerX
        stack.spacing     = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: glass.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: glass.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 36),
            iconView.heightAnchor.constraint(equalToConstant: 36),
        ])

        let dropTarget = PanelDropTargetView(frame: NSRect(origin: .zero, size: contentRect.size))
        dropTarget.autoresizingMask = [.width, .height]
        glass.addSubview(dropTarget)

        self.glass = glass
        self.iconView = iconView
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
        self.dropTarget = dropTarget

        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel    = true
        level              = .statusBar
        backgroundColor    = .clear
        isOpaque           = false
        hasShadow          = true
        isMovable          = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        contentView = glass

        dropTarget.onFilesDropped = { [weak self] urls, mods in
            self?.onFilesDropped?(urls, mods)
        }
    }

    // MARK: - Public API

    /// Configure the secondary label based on the file types being dragged.
    func updateForIncomingFiles(_ urls: [URL]) {
        secondaryLabel.stringValue = subtitleFor(urls: urls)
    }

    /// Reset to neutral state.
    func resetMessage() {
        secondaryLabel.stringValue = "Drag a supported file here"
    }

    /// Smoothly fade in at the given frame.
    func present(at frame: NSRect) {
        setFrame(frame, display: false)
        alphaValue = 0
        orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// Smoothly fade out and hide.
    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        })
    }

    // MARK: - Helpers

    private func subtitleFor(urls: [URL]) -> String {
        guard !urls.isEmpty else { return "Drag a supported file here" }

        let kinds = urls.map { FileTypeDetector.detect($0) }
        if urls.count > 1 {
            let supported = kinds.filter {
                if case .unsupported = $0 { return false } else { return true }
            }.count
            return "\(supported) of \(urls.count) files supported"
        }

        switch kinds[0] {
        case .pdf:                return "PDF → DOCX"
        case .word:               return "Word → PDF"
        case .office(let source): return "\(source.displayName) → choose format"
        case .image:              return "Image → choose format"
        case .unsupported:        return "Unsupported file type"
        }
    }
}

/// Sits inside the glass panel and accepts file drops on the panel itself.
private final class PanelDropTargetView: NSView {
    var onFilesDropped: (([URL], NSEvent.ModifierFlags) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        let modifiers = NSEvent.modifierFlags
        onFilesDropped?(urls, modifiers)
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { self }
}
