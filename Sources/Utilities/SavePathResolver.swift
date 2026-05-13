import AppKit
import os

private let log = Logger(subsystem: "com.dropconvert", category: "SavePathResolver")

enum SavePathResolver {
    /// Resolves the output URL for a conversion.
    ///
    /// - Parameters:
    ///   - source: The source file being converted.
    ///   - stem: Base filename (without extension) for the output.
    ///   - ext: Desired output file extension.
    ///   - showPanel: When `true`, presents an `NSSavePanel` so the user can choose a location.
    ///                When `false`, places the output next to the source file.
    /// - Returns: The resolved output URL, or `nil` if the user cancelled the save panel.
    @MainActor
    static func resolve(
        source: URL,
        stem: String,
        ext: String,
        showPanel: Bool
    ) -> URL? {
        if showPanel {
            return presentPanel(stem: stem, ext: ext, directory: source.deletingLastPathComponent())
        }
        return nextToSource(source: source, stem: stem, ext: ext)
    }

    // MARK: - Private

    private static func nextToSource(source: URL, stem: String, ext: String) -> URL {
        let dir = source.deletingLastPathComponent()
        var candidate = dir.appendingPathComponent("\(stem).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(stem) \(counter).\(ext)")
            counter += 1
        }
        log.info("resolved (auto): \(candidate.path)")
        return candidate
    }

    @MainActor
    private static func presentPanel(stem: String, ext: String, directory: URL) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(stem).\(ext)"
        panel.directoryURL = directory
        panel.allowedContentTypes = [] // free-form; extension is set in the filename

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            log.info("save panel cancelled")
            return nil
        }
        log.info("resolved (panel): \(url.path)")
        return url
    }
}
