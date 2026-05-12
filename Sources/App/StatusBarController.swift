import AppKit
import UniformTypeIdentifiers
import UserNotifications
import os

private let log = Logger(subsystem: "com.converterapp", category: "StatusBarController")

// Notification category/action identifiers
enum NotificationID {
    static let revealCategory = "CONVERSION_COMPLETE"
    static let revealAction   = "REVEAL_IN_FINDER"
    // userInfo key that carries the output file path
    static let outputPathKey  = "outputPath"
}

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private var dropZonePanel: DropZonePanel?
    private var proximityWindow: ProximityDropWindow?

    // Engine setup
    private var engineSetupWindow: EngineSetupWindow?
    private var pendingDrops: [(urls: [URL], modifiers: NSEvent.ModifierFlags)] = []

    // First-launch onboarding
    private let welcomeController = WelcomeWindowController()

    // Tracks how many conversions are in-flight to drive icon animation
    private var activeConversions = 0 {
        didSet { updateIcon() }
    }
    private var animationTimer: Timer?
    private var animationFrame = 0

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        configure()
        registerNotificationCategory()
        installProximityWindow()
        showWelcomeOnFirstLaunch()
    }

    private func showWelcomeOnFirstLaunch() {
        guard !WelcomeWindowController.hasSeenWelcome else { return }
        // Defer one runloop tick so the menu bar finishes setup before a
        // modal-feeling window pops over it.
        DispatchQueue.main.async { [weak self] in
            self?.welcomeController.show()
        }
    }

    private func configure() {
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Converter")
        button.image?.isTemplate = true
        button.action = #selector(statusBarButtonClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        button.registerForDraggedTypes([.fileURL])
        button.wantsLayer = true

        let dropView = DropTargetView(frame: button.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.onDragEntered  = { [weak self] in self?.showDropZone() }
        dropView.onDragExited   = { [weak self] in self?.hideDropZone() }
        dropView.onFilesDropped = { [weak self] urls, modifiers in
            self?.handleDroppedFiles(urls, modifiers: modifiers)
        }
        button.addSubview(dropView)
    }

    // MARK: - Notification category registration

    private func registerNotificationCategory() {
        let revealAction = UNNotificationAction(
            identifier: NotificationID.revealAction,
            title: "Reveal in Finder",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: NotificationID.revealCategory,
            actions: [revealAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Icon state

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        if activeConversions > 0 {
            startSpinAnimation(button: button)
        } else {
            stopSpinAnimation(button: button)
        }
    }

    private static let spinFrames: [String] = [
        "arrow.clockwise",
        "arrow.clockwise",
        "arrow.clockwise",
        "arrow.clockwise"
    ]

    // Uses a rotation transform on the button's layer for a smooth spin.
    private func startSpinAnimation(button: NSStatusBarButton) {
        guard animationTimer == nil else { return }
        button.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Converting…")
        button.image?.isTemplate = true

        // Animate via a CABasicAnimation on the button's layer.
        guard let layer = button.layer else { return }

        // AppKit layers default to anchorPoint (0, 0) — the bottom-left corner —
        // which makes rotation orbit the corner instead of spinning in place.
        // Re-anchor to the center and shift position by the same amount so the
        // layer's visible frame doesn't jump.
        if layer.anchorPoint != CGPoint(x: 0.5, y: 0.5) {
            let bounds = layer.bounds
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = -2 * Double.pi  // counter-clockwise feels natural for a spinner
        rotation.duration = 1.0
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        layer.add(rotation, forKey: "spinAnimation")
    }

    private func stopSpinAnimation(button: NSStatusBarButton) {
        button.layer?.removeAnimation(forKey: "spinAnimation")
        animationTimer?.invalidate()
        animationTimer = nil
        button.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Converter")
        button.image?.isTemplate = true
    }

    // MARK: - Menu

    @objc private func statusBarButtonClicked() {
        buildMenu().popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: statusItem.button!.bounds.height),
            in: statusItem.button
        )
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "ConverterApp", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())

        let convertItem = NSMenuItem(
            title: "Convert Finder Selection",
            action: #selector(convertFinderSelectionFromMenu),
            keyEquivalent: "c"
        )
        convertItem.keyEquivalentModifierMask = [.command, .shift]
        convertItem.target = self
        convertItem.isEnabled = activeConversions == 0
        menu.addItem(convertItem)

        let howToItem = NSMenuItem(
            title: "How to Use…",
            action: #selector(showWelcomeWindow),
            keyEquivalent: ""
        )
        howToItem.target = self
        menu.addItem(howToItem)

        menu.addItem(.separator())

        let versionString = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let versionItem = NSMenuItem(title: "Version \(versionString)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let ackItem = NSMenuItem(
            title: "Acknowledgments…",
            action: #selector(openAcknowledgments),
            keyEquivalent: ""
        )
        ackItem.target = self
        menu.addItem(ackItem)

        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        return menu
    }

    @objc private func convertFinderSelectionFromMenu() {
        handleHotkeyTriggered()
    }

    @objc private func showWelcomeWindow() {
        welcomeController.show()
    }

    @objc private func openAcknowledgments() {
        // Look inside the app bundle first; fall back to the project root during development.
        let candidates: [URL] = [
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/ACKNOWLEDGMENTS.md"),
            Bundle.main.resourceURL?
                .appendingPathComponent("ACKNOWLEDGMENTS.md"),
            URL(fileURLWithPath: #file)
                .deletingLastPathComponent()   // Sources/App
                .deletingLastPathComponent()   // Sources
                .deletingLastPathComponent()   // project root
                .appendingPathComponent("ACKNOWLEDGMENTS.md"),
        ].compactMap { $0 }

        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
            return
        }
        log.error("ACKNOWLEDGMENTS.md not found in bundle or project root")
    }

    // MARK: - Drop zone

    private func installProximityWindow() {
        guard let button = statusItem.button else { return }
        let window = ProximityDropWindow()
        window.onDragEntered  = { [weak self] urls in self?.showDropZone(incomingFiles: urls) }
        window.onDragExited   = { [weak self] in self?.hideDropZone() }
        window.onFilesDropped = { [weak self] urls, mods in
            self?.handleDroppedFiles(urls, modifiers: mods)
        }
        window.reposition(relativeTo: button)
        window.orderFront(nil)
        proximityWindow = window
    }

    private func showDropZone(incomingFiles: [URL] = []) {
        guard let button = statusItem.button,
              let screen = button.window?.screen ?? NSScreen.main else { return }

        let buttonRect = button.window?.convertToScreen(
            button.convert(button.bounds, to: nil)
        ) ?? .zero

        let size = DropZonePanel.preferredSize
        let panelX = buttonRect.midX - size.width / 2
        let panelY = buttonRect.minY - size.height - 6

        let frame = NSRect(
            x: max(screen.visibleFrame.minX,
                   min(panelX, screen.visibleFrame.maxX - size.width)),
            y: max(screen.visibleFrame.minY, panelY),
            width: size.width,
            height: size.height
        )

        if dropZonePanel == nil {
            let panel = DropZonePanel(contentRect: frame)
            panel.onFilesDropped = { [weak self] urls, mods in
                self?.handleDroppedFiles(urls, modifiers: mods)
            }
            dropZonePanel = panel
        }
        dropZonePanel?.updateForIncomingFiles(incomingFiles)
        dropZonePanel?.present(at: frame)
    }

    private func hideDropZone() {
        dropZonePanel?.dismiss()
        dropZonePanel?.resetMessage()
    }

    // MARK: - Hotkey entry point

    func handleHotkeyTriggered() {
        let modifiers = NSEvent.modifierFlags
        let urls = FinderSelectionReader.selectedURLs()
        guard !urls.isEmpty else {
            log.info("hotkey fired but no Finder selection")
            showNotification(title: "No files selected", body: "Select files in Finder first")
            return
        }
        handleDroppedFiles(urls, modifiers: modifiers)
    }

    // MARK: - File handling

    func handleDroppedFiles(_ urls: [URL], modifiers: NSEvent.ModifierFlags = []) {
        hideDropZone()

        // Partition: anything that needs LibreOffice vs. pure-image conversions that don't.
        let needsEngine = urls.contains { url in
            switch FileTypeDetector.detect(url) {
            case .word, .pdf, .office: return true
            case .image, .unsupported: return false
            }
        }

        if needsEngine && !LibreOfficeInstaller.isInstalled {
            pendingDrops.append((urls, modifiers))
            presentEngineSetupIfNeeded()
            return
        }

        dispatchDrops(urls, modifiers: modifiers)
    }

    /// Routes each URL to its converter. Caller must have already verified the engine is
    /// installed for any URL that needs it.
    private func dispatchDrops(_ urls: [URL], modifiers: NSEvent.ModifierFlags) {
        let usePanel = modifiers.contains(.option)
        for url in urls {
            let kind = FileTypeDetector.detect(url)
            switch kind {
            case .word:
                Task { await convertWordToPDF(url, usePanel: usePanel) }
            case .pdf:
                Task { await convertPDFToWord(url, usePanel: usePanel) }
            case .image(let inputType):
                showImageFormatPicker(for: url, inputType: inputType, usePanel: usePanel)
            case .office(let source):
                showOfficeFormatPicker(for: url, source: source, usePanel: usePanel)
            case .unsupported:
                showNotification(title: "Unsupported format", body: url.lastPathComponent)
            }
        }
    }

    // MARK: - Engine setup gate

    private func presentEngineSetupIfNeeded() {
        if engineSetupWindow != nil { return }  // already showing — drops queued
        let window = EngineSetupWindow()
        engineSetupWindow = window
        window.present { [weak self] outcome in
            guard let self else { return }
            self.engineSetupWindow = nil
            switch outcome {
            case .success:
                let queued = self.pendingDrops
                self.pendingDrops.removeAll()
                for drop in queued {
                    self.dispatchDrops(drop.urls, modifiers: drop.modifiers)
                }
            case .cancelled:
                self.pendingDrops.removeAll()
            case .failed(let error):
                self.pendingDrops.removeAll()
                self.showNotification(title: "Engine install failed", body: error.localizedDescription)
            }
        }
    }

    // MARK: - Conversion

    private func convertWordToPDF(_ url: URL, usePanel: Bool) async {
        let stem = url.deletingPathExtension().lastPathComponent
        guard let outputURL = SavePathResolver.resolve(
            source: url, stem: stem, ext: "pdf", showPanel: usePanel
        ) else { return }

        beginConversion()
        showNotification(title: "Converting…", body: url.lastPathComponent)
        do {
            let output = try await WordToPDFConverter.convert(input: url, outputURL: outputURL)
            endConversion()
            showCompletionNotification(outputURL: output)
        } catch {
            endConversion()
            showNotification(title: "Conversion failed", body: error.localizedDescription)
        }
    }

    private func convertPDFToWord(_ url: URL, usePanel: Bool) async {
        let stem = url.deletingPathExtension().lastPathComponent
        guard let outputURL = SavePathResolver.resolve(
            source: url, stem: stem, ext: "docx", showPanel: usePanel
        ) else { return }

        beginConversion()
        showNotification(title: "Converting…", body: url.lastPathComponent)
        do {
            let output = try await PDFToWordConverter.convert(input: url, outputURL: outputURL)
            endConversion()
            showCompletionNotification(outputURL: output)
        } catch {
            endConversion()
            showNotification(title: "Conversion failed", body: error.localizedDescription)
        }
    }

    // MARK: - Image format picker

    private func showImageFormatPicker(for url: URL, inputType: UTType, usePanel: Bool) {
        guard let button = statusItem.button else {
            log.error("no status item button when showing picker")
            return
        }

        log.info("showing image format picker for \(url.path)")
        let menu = ImageFormatPicker.makeMenu(inputType: inputType) { [weak self] destinationType in
            log.info("menu selection: \(destinationType.identifier)")
            Task { await self?.convertImage(url, to: destinationType, usePanel: usePanel) }
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height),
            in: button
        )
    }

    private func convertImage(_ url: URL, to type: UTType, usePanel: Bool) async {
        log.info("convertImage start: \(url.path) -> \(type.identifier)")
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = type.preferredFilenameExtension ?? "img"
        guard let outputURL = SavePathResolver.resolve(
            source: url, stem: stem, ext: ext, showPanel: usePanel
        ) else {
            log.info("convertImage cancelled (save panel)")
            return
        }

        beginConversion()
        showNotification(title: "Converting…", body: url.lastPathComponent)
        do {
            let output = try await ImageConverter.convert(input: url, to: type, outputURL: outputURL)
            log.info("convertImage success: \(output.path)")
            endConversion()
            showCompletionNotification(outputURL: output)
        } catch {
            log.error("convertImage failed: \(error.localizedDescription)")
            endConversion()
            showNotification(title: "Conversion failed", body: error.localizedDescription)
        }
    }

    // MARK: - Office format picker

    private func showOfficeFormatPicker(for url: URL, source: OfficeSource, usePanel: Bool) {
        guard let button = statusItem.button else {
            log.error("no status item button when showing office picker")
            return
        }

        log.info("showing office format picker for \(url.path)")
        let menu = OfficeFormatPicker.makeMenu(source: source) { [weak self] target in
            log.info("office menu selection: \(target.ext)")
            Task { await self?.convertOffice(url, target: target, usePanel: usePanel) }
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height),
            in: button
        )
    }

    private func convertOffice(_ url: URL, target: OfficeTarget, usePanel: Bool) async {
        log.info("convertOffice start: \(url.path) -> \(target.ext)")
        let stem = url.deletingPathExtension().lastPathComponent
        guard let outputURL = SavePathResolver.resolve(
            source: url, stem: stem, ext: target.ext, showPanel: usePanel
        ) else {
            log.info("convertOffice cancelled (save panel)")
            return
        }

        beginConversion()
        showNotification(title: "Converting…", body: url.lastPathComponent)
        do {
            let output = try await OfficeConverter.convert(input: url, target: target, outputURL: outputURL)
            log.info("convertOffice success: \(output.path)")
            endConversion()
            showCompletionNotification(outputURL: output)
        } catch {
            log.error("convertOffice failed: \(error.localizedDescription)")
            endConversion()
            showNotification(title: "Conversion failed", body: error.localizedDescription)
        }
    }

    // MARK: - Conversion counter (drives icon state)

    private func beginConversion() {
        activeConversions += 1
    }

    private func endConversion() {
        activeConversions = max(0, activeConversions - 1)
    }

    // MARK: - Notifications

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Posts a "Conversion complete" notification with a "Reveal in Finder" action button.
    private func showCompletionNotification(outputURL: URL) {
        let content = UNMutableNotificationContent()
        content.title    = "Conversion complete"
        content.body     = outputURL.lastPathComponent
        content.categoryIdentifier = NotificationID.revealCategory
        content.userInfo = [NotificationID.outputPathKey: outputURL.path]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
