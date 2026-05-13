import AppKit
import os

private let log = Logger(subsystem: "com.dropconvert", category: "EngineSetupWindow")

/// Modal-style window shown on first launch (or after engine removal) while the
/// LibreOffice engine is being downloaded and installed. The user sees a progress
/// bar, a status label, and a Cancel button. On completion the window invokes its
/// `onFinished` callback with the result and the caller decides what to do next
/// (typically: retry the queued conversion, or show the error).
///
/// Uses AppKit only — no SwiftUI — to match the rest of the app.
@MainActor
final class EngineSetupWindow: NSObject {

    /// Outcome of an install attempt.
    enum Outcome {
        case success
        case cancelled
        case failed(Error)
    }

    // MARK: - State

    private let window: NSPanel
    private let progressBar: NSProgressIndicator
    private let statusLabel: NSTextField
    private let cancelButton: NSButton
    private let retryButton: NSButton
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField

    private var installTask: Task<Void, Never>?
    private var onFinished: ((Outcome) -> Void)?

    // MARK: - Init

    override init() {
        let contentRect = NSRect(x: 0, y: 0, width: 460, height: 220)
        let style: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        panel.title = "Set Up Converter"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let title = NSTextField(labelWithString: "One-time setup")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let subtitle = NSTextField(wrappingLabelWithString:
            "DropConvert needs to download its document engine (LibreOffice, ~200 MB) before it can convert Word, PowerPoint, or Excel files. This only happens once.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.maximumNumberOfLines = 0

        let bar = NSProgressIndicator()
        bar.isIndeterminate = true
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.translatesAutoresizingMaskIntoConstraints = false

        let status = NSTextField(labelWithString: "Preparing…")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false

        let cancel = NSButton(title: "Cancel", target: nil, action: nil)
        cancel.bezelStyle = .rounded
        cancel.translatesAutoresizingMaskIntoConstraints = false

        let retry = NSButton(title: "Retry", target: nil, action: nil)
        retry.bezelStyle = .rounded
        retry.keyEquivalent = "\r"
        retry.isHidden = true
        retry.translatesAutoresizingMaskIntoConstraints = false

        self.window = panel
        self.progressBar = bar
        self.statusLabel = status
        self.cancelButton = cancel
        self.retryButton = retry
        self.titleLabel = title
        self.subtitleLabel = subtitle

        super.init()

        guard let content = panel.contentView else { return }
        content.addSubview(title)
        content.addSubview(subtitle)
        content.addSubview(bar)
        content.addSubview(status)
        content.addSubview(cancel)
        content.addSubview(retry)

        cancel.target = self
        cancel.action = #selector(cancelTapped)
        retry.target = self
        retry.action = #selector(retryTapped)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            bar.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            bar.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            status.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 8),
            status.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            status.trailingAnchor.constraint(equalTo: title.trailingAnchor),

            cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            cancel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            retry.bottomAnchor.constraint(equalTo: cancel.bottomAnchor),
            retry.trailingAnchor.constraint(equalTo: cancel.leadingAnchor, constant: -12),
        ])
    }

    // MARK: - Public entry point

    /// Presents the window and starts the install. `onFinished` is invoked once on the
    /// main actor with the outcome. The window is dismissed automatically on success or
    /// cancellation; on failure it stays open with a Retry button.
    func present(onFinished: @escaping (Outcome) -> Void) {
        self.onFinished = onFinished
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        startInstall()
    }

    // MARK: - Install lifecycle

    private func startInstall() {
        retryButton.isHidden = true
        cancelButton.title = "Cancel"
        statusLabel.stringValue = "Downloading…"
        progressBar.isIndeterminate = false
        progressBar.doubleValue = 0

        installTask = Task { [weak self] in
            // Capture a Sendable progress handler that forwards to the main actor.
            // `self` is unowned-ish here — the Task is cancelled when the window goes away.
            let onProgress: @Sendable (Double) -> Void = { fraction in
                Task { @MainActor in
                    self?.updateProgress(fraction)
                }
            }
            do {
                try await LibreOfficeInstaller.install(progressHandler: onProgress)
                await MainActor.run { [weak self] in
                    self?.finish(.success)
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.finish(.cancelled)
                }
            } catch LibreOfficeInstallError.cancelled {
                await MainActor.run { [weak self] in
                    self?.finish(.cancelled)
                }
            } catch {
                log.error("engine install failed: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { [weak self] in
                    self?.showFailure(error)
                }
            }
        }
    }

    private func updateProgress(_ fraction: Double) {
        progressBar.doubleValue = fraction
        let pct = Int((fraction * 100).rounded())
        if fraction >= 0.999 {
            statusLabel.stringValue = "Extracting…"
            progressBar.isIndeterminate = true
            progressBar.startAnimation(nil)
        } else {
            statusLabel.stringValue = "Downloading… \(pct)%"
        }
    }

    private func showFailure(_ error: Error) {
        progressBar.stopAnimation(nil)
        progressBar.isIndeterminate = false
        progressBar.doubleValue = 0
        statusLabel.stringValue = error.localizedDescription
        statusLabel.textColor = .systemRed
        retryButton.isHidden = false
        cancelButton.title = "Close"
    }

    private func finish(_ outcome: Outcome) {
        installTask = nil
        let handler = onFinished
        onFinished = nil
        window.orderOut(nil)
        handler?(outcome)
    }

    @objc private func cancelTapped() {
        if installTask != nil {
            installTask?.cancel()
            installTask = nil
            finish(.cancelled)
        } else {
            // Failure state — "Close" button.
            finish(.cancelled)
        }
    }

    @objc private func retryTapped() {
        statusLabel.textColor = .secondaryLabelColor
        startInstall()
    }
}
