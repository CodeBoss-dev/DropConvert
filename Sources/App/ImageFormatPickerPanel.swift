import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Builds an NSMenu for picking an image output format. NSMenu is used instead of a
/// custom NSPanel because menus handle event routing, dismissal, and activation
/// correctly in background-only menu-bar apps — custom panels do not.
enum ImageFormatPicker {
    /// All formats we'd offer, in display order.
    private static let candidateFormats: [(label: String, type: UTType)] = [
        ("PNG",  .png),
        ("JPEG", .jpeg),
        ("HEIC", .heic),
        ("TIFF", .tiff),
        ("BMP",  .bmp),
        ("WebP", .webP),
    ]

    /// UTIs that CGImageDestination can actually encode on this OS.
    /// Computed once — the set is fixed for a given macOS version.
    private static let writableUTIs: Set<String> = {
        let supported = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return Set(supported)
    }()

    /// Formats to show for a given input type — drops anything ImageIO can't write
    /// (notably WebP on macOS: readable but not writable) and the input's own format
    /// (converting PNG → PNG would be pointless).
    private static func formats(for inputType: UTType) -> [(label: String, type: UTType)] {
        candidateFormats.filter { candidate in
            writableUTIs.contains(candidate.type.identifier)
                && !inputType.conforms(to: candidate.type)
        }
    }

    /// Build a menu. The provided `onSelection` is invoked with the chosen UTType.
    /// The smart default is marked with a checkmark and labeled "(suggested)".
    static func makeMenu(inputType: UTType, onSelection: @escaping (UTType) -> Void) -> NSMenu {
        let smartDefault = ImageConverter.smartDefault(for: inputType)
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Convert to…", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for format in formats(for: inputType) {
            let isDefault = format.type == smartDefault
            let title = isDefault ? "\(format.label) (suggested)" : format.label
            let item = ClosureMenuItem(title: title) { onSelection(format.type) }
            if isDefault { item.state = .on }
            menu.addItem(item)
        }
        return menu
    }
}

/// NSMenuItem subclass that invokes a closure when selected.
/// Keeps the target/action wiring local to the item.
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
