import AppKit

/// NSMenu builder for picking an office output format. Mirrors
/// `ImageFormatPicker` — NSMenu is the right primitive for status-bar UIs;
/// custom NSPanels don't get reliable event routing in LSUIElement apps.
enum OfficeFormatPicker {
    static func makeMenu(source: OfficeSource, onSelection: @escaping (OfficeTarget) -> Void) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Convert \(source.displayName) to…", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let targets = source.targets
        for target in targets {
            // PDF is the most common ask across all office families — mark it
            // as suggested so users get a visual default.
            let isSuggested = target.ext == "pdf"
            let title = isSuggested ? "\(target.label) (suggested)" : target.label
            let item = ClosureMenuItem(title: title) { onSelection(target) }
            if isSuggested { item.state = .on }
            menu.addItem(item)
        }
        return menu
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func invoke() { handler() }
}
