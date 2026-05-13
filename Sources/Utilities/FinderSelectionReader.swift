import AppKit
import os

private let log = Logger(subsystem: "com.dropconvert", category: "FinderSelectionReader")

enum FinderSelectionReader {
    /// Returns the URLs of all files currently selected in Finder.
    /// Returns an empty array if Finder is not running or nothing is selected.
    static func selectedURLs() -> [URL] {
        let source = """
        tell application "Finder"
            set sel to selection as alias list
            set paths to {}
            repeat with f in sel
                set end of paths to POSIX path of f
            end repeat
            return paths
        end tell
        """

        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        guard let result = script?.executeAndReturnError(&error) else {
            if let err = error {
                log.error("AppleScript error: \(err)")
            }
            return []
        }

        var urls: [URL] = []
        // Result is a list descriptor; iterate its items.
        let count = result.numberOfItems
        for i in 1 ... max(1, count) {
            guard i <= count,
                  let item = result.atIndex(i),
                  let path = item.stringValue else { continue }
            urls.append(URL(fileURLWithPath: path))
        }
        log.info("Finder selection: \(urls.map(\.lastPathComponent))")
        return urls
    }
}
