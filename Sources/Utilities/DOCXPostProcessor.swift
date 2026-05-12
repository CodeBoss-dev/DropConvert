import Foundation

/// Strips non-text floating shapes that LibreOffice injects when importing PDFs.
///
/// LibreOffice's PDF import produces two kinds of mc:AlternateContent shapes:
///   1. Text boxes  — contain real w:t text; these ARE the document content.
///   2. Decorative shapes — filled rectangles, lines, borders; no real text.
///      These render as opaque overlays (white boxes) covering the text boxes.
///
/// Strategy: keep any mc:AlternateContent that contains non-whitespace w:t text
/// OR embeds a picture (pic: graphicData URI). Remove everything else.
enum DOCXPostProcessor {
    enum PostProcessError: Error, LocalizedError {
        case cannotReadDocx(URL)
        case cannotWriteDocx(URL)
        case unzipFailed(Int32)
        case rezipFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .cannotReadDocx(let url): return "Cannot read DOCX at \(url.path)"
            case .cannotWriteDocx(let url): return "Cannot write DOCX at \(url.path)"
            case .unzipFailed(let code): return "Failed to unpack DOCX (exit \(code))"
            case .rezipFailed(let code): return "Failed to repack DOCX (exit \(code))"
            }
        }
    }

    static func stripImageOverlays(at url: URL) throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("DOCXPostProcessor-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: workDir) }

        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

        let zipSrc = workDir.appendingPathComponent("input.docx")
        try fm.copyItem(at: url, to: zipSrc)

        let unzipDir = workDir.appendingPathComponent("unzipped")
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", zipSrc.path, "-d", unzipDir.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else {
            throw PostProcessError.unzipFailed(unzip.terminationStatus)
        }

        let documentXMLURL = unzipDir.appendingPathComponent("word/document.xml")
        guard let xmlData = fm.contents(atPath: documentXMLURL.path) else {
            throw PostProcessError.cannotReadDocx(url)
        }

        let cleaned = stripDecorativeShapes(from: xmlData)

        guard fm.createFile(atPath: documentXMLURL.path, contents: cleaned) else {
            throw PostProcessError.cannotWriteDocx(url)
        }

        let repackedZip = workDir.appendingPathComponent("output.docx")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = unzipDir
        zip.arguments = ["-qr", repackedZip.path, "."]
        try zip.run()
        zip.waitUntilExit()
        guard zip.terminationStatus == 0 else {
            throw PostProcessError.rezipFailed(zip.terminationStatus)
        }

        _ = try fm.replaceItemAt(url, withItemAt: repackedZip)
    }

    // MARK: - XML scrubbing

    private static let picURI = "http://schemas.openxmlformats.org/drawingml/2006/picture"

    /// Removes mc:AlternateContent blocks that are decorative overlays (no real text, no image).
    /// Operates on raw UTF-8 to avoid XMLDocument re-serialisation changing the file.
    static func stripDecorativeShapes(from data: Data) -> Data {
        guard let xml = String(data: data, encoding: .utf8) else { return data }
        var result = removeDecorativeAlternateContent(in: xml)
        result = removeDecorativePicts(in: result)
        result = recolorInvisibleText(in: result)
        return Data(result.utf8)
    }

    /// After stripping shape overlays, any text that was drawn in white relied on a
    /// colored background behind it to be visible. Those backgrounds are gone, so
    /// the white text now disappears against the page. Rewrite white/near-white
    /// `w:color` values to `auto` so the theme renders them readably.
    ///
    /// Only run-level (`w:rPr/w:color`) values are touched. Highlight shading and
    /// table cell fills are left alone — those are still real background colors.
    static func recolorInvisibleText(in text: String) -> String {
        let pattern = #"<w:color([^/>]*?)w:val="([0-9A-Fa-f]{6})"([^/>]*?)/>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var result = ""
        var cursor = 0
        for match in matches {
            let full = match.range
            let hexRange = match.range(at: 2)
            result += ns.substring(with: NSRange(location: cursor, length: full.location - cursor))
            let hex = ns.substring(with: hexRange)
            if isNearWhite(hex) {
                let pre = ns.substring(with: match.range(at: 1))
                let post = ns.substring(with: match.range(at: 3))
                result += "<w:color\(pre)w:val=\"auto\"\(post)/>"
            } else {
                result += ns.substring(with: full)
            }
            cursor = full.location + full.length
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Treat any color where R, G, and B are all ≥ 0xE0 as "near white" — these
    /// were drawn assuming a dark fill behind them and become unreadable on a
    /// blank page.
    private static func isNearWhite(_ hex: String) -> Bool {
        guard hex.count == 6 else { return false }
        let scalars = Array(hex.uppercased())
        func byte(_ i: Int) -> Int? {
            let s = String(scalars[i]) + String(scalars[i + 1])
            return Int(s, radix: 16)
        }
        guard let r = byte(0), let g = byte(2), let b = byte(4) else { return false }
        return r >= 0xE0 && g >= 0xE0 && b >= 0xE0
    }

    /// Removes standalone `w:pict` blocks that contain no text and no embedded image.
    /// LibreOffice inserts these as full-page white rectangles on each page from PDF imports.
    private static func removeDecorativePicts(in text: String) -> String {
        let open = "<w:pict"
        let close = "</w:pict>"
        var result = ""
        var remainder = text[...]

        while let startRange = remainder.range(of: open) {
            result += remainder[..<startRange.lowerBound]

            guard let endRange = remainder.range(of: close, range: startRange.lowerBound..<remainder.endIndex) else {
                remainder = remainder[startRange.lowerBound...]
                break
            }

            let block = String(remainder[startRange.lowerBound..<endRange.upperBound])
            remainder = remainder[endRange.upperBound...]

            if isDecorativePict(block) {
                // Drop it
            } else {
                result += block
            }
        }

        result += remainder
        return result
    }

    private static func isDecorativePict(_ block: String) -> Bool {
        // Keep picts that embed images (v:imagedata)
        if block.contains("imagedata") { return false }

        // Keep picts with real text content
        var search = block[...]
        let wtOpen  = "<w:t"
        let wtClose = "</w:t>"
        while let startRange = search.range(of: wtOpen) {
            guard let gtRange = search.range(of: ">", range: startRange.upperBound..<search.endIndex),
                  let endRange = search.range(of: wtClose, range: gtRange.upperBound..<search.endIndex)
            else { break }
            let txt = String(search[gtRange.upperBound..<endRange.lowerBound])
            if !txt.trimmingCharacters(in: .init(charactersIn: " \t\n\r")).isEmpty {
                return false
            }
            search = search[endRange.upperBound...]
        }

        return true  // Empty decorative pict — strip
    }

    private static func removeDecorativeAlternateContent(in text: String) -> String {
        let open = "<mc:AlternateContent"
        let close = "</mc:AlternateContent>"
        var result = ""
        var remainder = text[...]

        while let startRange = remainder.range(of: open) {
            // Append everything before this block
            result += remainder[..<startRange.lowerBound]

            guard let endRange = remainder.range(of: close, range: startRange.lowerBound..<remainder.endIndex) else {
                // Malformed XML — leave the rest untouched
                remainder = remainder[startRange.lowerBound...]
                break
            }

            let block = String(remainder[startRange.lowerBound..<endRange.upperBound])
            remainder = remainder[endRange.upperBound...]

            if isDecorativeOverlay(block) {
                // Drop it — don't append to result
            } else {
                result += block
            }
        }

        result += remainder
        return result
    }

    /// A block is a decorative overlay (safe to remove) if it has no real text
    /// and is not an embedded image.
    private static func isDecorativeOverlay(_ block: String) -> Bool {
        // Keep picture shapes (logos, embedded images)
        if block.contains(picURI) { return false }

        // Extract all w:t content and check for non-whitespace text
        var search = block[...]
        let wtOpen  = "<w:t"
        let wtClose = "</w:t>"

        while let startRange = search.range(of: wtOpen) {
            guard let gtRange = search.range(of: ">", range: startRange.upperBound..<search.endIndex),
                  let endRange = search.range(of: wtClose, range: gtRange.upperBound..<search.endIndex)
            else { break }

            let text = String(search[gtRange.upperBound..<endRange.lowerBound])
            if !text.trimmingCharacters(in: .init(charactersIn: " \t\n\r")).isEmpty {
                return false  // Has real text — keep
            }
            search = search[endRange.upperBound...]
        }

        return true  // No real text and no image — strip
    }
}
