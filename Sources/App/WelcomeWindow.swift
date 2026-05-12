import AppKit
import SwiftUI

/// First-launch onboarding window. AppKit hosts the window chrome; SwiftUI
/// renders the contents because the animated drag demo and stacked feature
/// cards are dramatically less code in SwiftUI than in equivalent AppKit.
///
/// Re-openable from the menu bar's "How to Use…" item. Tracks first-seen
/// state in UserDefaults so the auto-open path only fires once per user.
@MainActor
final class WelcomeWindowController {
    static let hasSeenWelcomeKey = "hasSeenWelcome"

    private var window: NSWindow?

    /// True if the user has already seen the welcome window at least once.
    static var hasSeenWelcome: Bool {
        UserDefaults.standard.bool(forKey: hasSeenWelcomeKey)
    }

    /// Show (or re-show) the welcome window. Marks `hasSeenWelcome = true`
    /// whether dismissed or not — once a user has seen it, we don't auto-pop
    /// it again. They can always re-open it from the menu.
    func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: WelcomeView(onDismiss: { [weak self] in
            self?.window?.close()
        }))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to ConverterApp"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("WelcomeWindow")

        self.window = window

        // LSUIElement apps don't activate automatically when opening a window.
        // Without this, the window appears behind whatever the user was using.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        UserDefaults.standard.set(true, forKey: Self.hasSeenWelcomeKey)
    }
}

// MARK: - SwiftUI content

private struct WelcomeView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DragDemoView()
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome to ConverterApp")
                            .font(.system(size: 22, weight: .semibold))
                        Text("Convert files locally on your Mac. No uploads, no waiting.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    FeatureCard(
                        symbol: "arrow.down.doc.fill",
                        title: "Drag a file onto the menu bar icon",
                        text: "The converted file appears next to the original. Hold ⌥ Option while dropping to choose where to save."
                    )

                    FeatureCard(
                        symbol: "command",
                        title: "Or press ⌘⇧C in Finder",
                        text: "Select one or more files in Finder and press Command-Shift-C. ConverterApp converts your selection without leaving Finder."
                    )

                    FeatureCard(
                        symbol: "doc.on.doc",
                        title: "Supported formats",
                        text: "PDF, DOCX, PPTX, XLSX, ODT, ODS, ODP, RTF, CSV, TXT, and images (PNG, JPG, HEIC, WebP, TIFF, BMP)."
                    )
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }

            Divider()

            HStack {
                Text("You can re-open this window any time from the menu bar.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Got it") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 620)
    }
}

private struct FeatureCard: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color(nsColor: .controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Animated drag demo

/// Loops a stylized "drag a file onto the menu bar" animation. Pure SwiftUI —
/// no GIFs, no external assets.
///
/// Layout: a faux menu bar is pinned to the very top of the view. The
/// converter icon sits at a fixed position inside that menu bar (right-aligned
/// with the wifi/battery icons). The dragged document is absolutely
/// positioned so its X coordinate matches the converter icon — this keeps the
/// drag motion visually aligned regardless of view width.
///
/// Phases:
///   1. File icon rises from bottom of the demo area toward the converter icon.
///   2. Drop: file fades out into the converter icon, which pulses.
///   3. A green "✓" briefly appears next to the converter icon.
///   4. Reset and repeat every ~3 seconds.
private struct DragDemoView: View {
    @State private var phase: Phase = .idle

    enum Phase { case idle, dragging, dropped, completed }

    // Layout constants. The menu bar icons cluster around the horizontal
    // center of the demo area, and the dragged document rises along the same
    // vertical line as the converter icon to keep the motion visually aligned.
    private let menuBarHeight: CGFloat = 28
    private let dragStartY: CGFloat = 180          // bottom of the demo area
    private let dragEndY: CGFloat = 28             // just under the menu bar (where the icon is)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Faux menu bar pinned to the very top.
                fauxMenuBar
                    .frame(height: menuBarHeight)
                    .frame(maxWidth: .infinity)

                // Dragged document — positioned absolutely so it lines up
                // with the converter icon in the menu bar above. The converter
                // icon is the rightmost item in the centered cluster of three
                // (wifi, battery, converter), so we offset slightly right of
                // dead-center to land on it.
                let dragX = geo.size.width / 2 + 36
                let dragY = phase == .idle ? dragStartY : dragEndY

                Image(systemName: "doc.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.tint)
                    .position(x: dragX, y: dragY)
                    .opacity(documentOpacity)
                    .animation(.easeInOut(duration: 1.0), value: phase)

                // Cursor — sits at the top-right corner of the document so it
                // reads as "user is grabbing this file and dragging it up."
                // SF Symbol "cursorarrow" is the standard macOS pointer shape.
                Image(systemName: "cursorarrow")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .position(x: dragX + 14, y: dragY - 12)
                    .opacity(documentOpacity)
                    .animation(.easeInOut(duration: 1.0), value: phase)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear(perform: startLoop)
    }

    private var fauxMenuBar: some View {
        // Centered cluster of menu-bar icons. Spacers on both sides keep the
        // group horizontally centered regardless of view width.
        HStack(spacing: 16) {
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.100percent")
            ZStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .scaleEffect(phase == .dropped ? 1.3 : 1.0)
                    .foregroundStyle(phase == .dropped ? Color.accentColor : Color.primary)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: phase)
                if phase == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                        .background(Circle().fill(.background).padding(-1))
                        .offset(x: 10, y: -8)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            Spacer()
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .background(.regularMaterial)
    }

    private var documentOpacity: Double {
        switch phase {
        case .idle, .dragging: return 1
        case .dropped, .completed: return 0
        }
    }

    private func startLoop() {
        Task {
            while !Task.isCancelled {
                phase = .idle
                try? await Task.sleep(nanoseconds: 700_000_000)
                phase = .dragging
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                phase = .dropped
                try? await Task.sleep(nanoseconds: 500_000_000)
                phase = .completed
                try? await Task.sleep(nanoseconds: 1_300_000_000)
            }
        }
    }
}
