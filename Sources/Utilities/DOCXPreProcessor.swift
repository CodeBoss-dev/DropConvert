import Foundation
import os

private let log = Logger(subsystem: "com.converterapp", category: "DOCXPreProcessor")

/// Rewrites a DOCX in place so any table wider than the page text area is
/// marked as 100% page width. This mirrors what Word does at render time
/// ("AutoFit to window") but which LibreOffice's headless renderer does not
/// apply — without this step, oversized tables get clipped at the right margin
/// of the produced PDF.
///
/// Only overflowing top-level tables are touched. Tables that already fit, are
/// already declared as a percentage width, or are nested inside another table
/// are left alone.
enum DOCXPreProcessor {
    /// Returns a URL to a new DOCX (in a temp directory) with overflowing
    /// tables widened to 100%. If nothing needed changing, returns the input
    /// URL unchanged.
    static func shrinkOverflowingTables(input: URL) throws -> URL {
        let unzipDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConverterApp-docx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)

        try runProcess(
            executable: "/usr/bin/unzip",
            args: ["-q", input.path, "-d", unzipDir.path]
        )

        let documentXML = unzipDir
            .appendingPathComponent("word")
            .appendingPathComponent("document.xml")

        guard FileManager.default.fileExists(atPath: documentXML.path) else {
            log.notice("No word/document.xml — leaving DOCX untouched")
            try? FileManager.default.removeItem(at: unzipDir)
            return input
        }

        let originalData = try Data(contentsOf: documentXML)
        let rewritten = try rewriteDocumentXML(data: originalData)
        guard let rewritten else {
            try? FileManager.default.removeItem(at: unzipDir)
            return input
        }
        try rewritten.write(to: documentXML)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConverterApp-docx-fit-\(UUID().uuidString).docx")
        try? FileManager.default.removeItem(at: outputURL)

        // Re-zip from inside unzipDir so paths are stored relative (no leading
        // unzipDir prefix). `-X` strips extra attributes, `-r` recurses.
        try runProcess(
            executable: "/bin/sh",
            args: ["-c", "cd \(shellQuote(unzipDir.path)) && /usr/bin/zip -qrX \(shellQuote(outputURL.path)) ."]
        )

        try? FileManager.default.removeItem(at: unzipDir)
        return outputURL
    }

    /// Returns rewritten XML data, or nil if no changes were needed.
    private static func rewriteDocumentXML(data: Data) throws -> Data? {
        let doc = try XMLDocument(data: data, options: [.nodePreserveAll])

        guard let root = doc.rootElement() else { return nil }
        guard let body = (try root.nodes(forXPath: "./*[local-name()='body']").first) as? XMLElement
        else { return nil }

        // Build the ordered list of section break boundaries within <w:body>.
        // Each entry: (index of the body child that ends the section, sectPr).
        let sectionBoundaries = sectionBoundaries(in: body)

        // Walk body children in order. For each top-level table, look up the
        // governing section (first boundary at or after the table's body index)
        // and measure against that section's page geometry.
        var changed = false
        for (childIndex, child) in body.children?.enumerated() ?? [].enumerated() {
            guard let element = child as? XMLElement, element.localName == "tbl" else { continue }

            guard let sectPr = governingSectPr(forBodyIndex: childIndex, boundaries: sectionBoundaries)
            else {
                log.notice("Table at body index \(childIndex) has no governing section; skipping")
                continue
            }
            guard let textAreaTwips = textAreaWidthTwips(sectPr: sectPr) else { continue }

            if try shrinkIfOverflowing(table: element, textAreaTwips: textAreaTwips) {
                changed = true
            }
        }

        guard changed else { return nil }
        return doc.xmlData(options: [.nodePreserveAll])
    }

    /// Per-section boundaries within `<w:body>`, in document order. Each entry
    /// is (body child index at which the section ends, sectPr element).
    ///
    /// `<w:sectPr>` lives either as a direct child of `<w:body>` (the final
    /// section) or inside `<w:p>/<w:pPr>` (mid-document section breaks). The
    /// section governs all body content from the previous boundary up to and
    /// including this one.
    private static func sectionBoundaries(in body: XMLElement) -> [(endIndex: Int, sectPr: XMLElement)] {
        var result: [(Int, XMLElement)] = []
        guard let children = body.children else { return result }

        for (i, child) in children.enumerated() {
            guard let element = child as? XMLElement else { continue }

            if element.localName == "sectPr" {
                result.append((i, element))
                continue
            }
            if element.localName == "p",
               let pPr = (try? element.nodes(forXPath: "./*[local-name()='pPr']").first) as? XMLElement,
               let sectPr = (try? pPr.nodes(forXPath: "./*[local-name()='sectPr']").first) as? XMLElement {
                result.append((i, sectPr))
            }
        }
        return result
    }

    /// Returns the sectPr governing a body child at `bodyIndex` — the first
    /// boundary whose `endIndex >= bodyIndex`. Falls back to the last boundary
    /// (the document-default) if nothing matches.
    private static func governingSectPr(
        forBodyIndex bodyIndex: Int,
        boundaries: [(endIndex: Int, sectPr: XMLElement)]
    ) -> XMLElement? {
        for boundary in boundaries where boundary.endIndex >= bodyIndex {
            return boundary.sectPr
        }
        return boundaries.last?.sectPr
    }

    /// Returns text-area width (page width − left/right margins − gutter), in twips,
    /// for the given section properties element.
    private static func textAreaWidthTwips(sectPr: XMLElement) -> Int? {
        let pgSz = (try? sectPr.nodes(forXPath: "./*[local-name()='pgSz']").first) as? XMLElement
        let pgMar = (try? sectPr.nodes(forXPath: "./*[local-name()='pgMar']").first) as? XMLElement

        guard let pageWidth = pgSz?.attributeValueIgnoringNS("w").flatMap(Int.init) else {
            return nil
        }
        let left = pgMar?.attributeValueIgnoringNS("left").flatMap(Int.init) ?? 0
        let right = pgMar?.attributeValueIgnoringNS("right").flatMap(Int.init) ?? 0
        let gutter = pgMar?.attributeValueIgnoringNS("gutter").flatMap(Int.init) ?? 0

        let usable = pageWidth - left - right - gutter
        return usable > 0 ? usable : nil
    }

    /// Mutates `table` if it overflows. Returns true if a change was made.
    private static func shrinkIfOverflowing(table: XMLElement, textAreaTwips: Int) throws -> Bool {
        let tblPr = (try table.nodes(forXPath: "./*[local-name()='tblPr']").first) as? XMLElement
        let tblW = (try tblPr?.nodes(forXPath: "./*[local-name()='tblW']").first) as? XMLElement

        // If table width is already declared as a percentage, leave it alone —
        // it's already responsive.
        if tblW?.attributeValueIgnoringNS("type") == "pct" {
            return false
        }

        let declaredWidth: Int?
        if let tblW, tblW.attributeValueIgnoringNS("type") == "dxa",
           let w = tblW.attributeValueIgnoringNS("w").flatMap(Int.init) {
            declaredWidth = w
        } else {
            // Fall back to summing tblGrid/gridCol widths.
            let gridCols = (try? table.nodes(forXPath: "./*[local-name()='tblGrid']/*[local-name()='gridCol']")) ?? []
            let sum = gridCols
                .compactMap { ($0 as? XMLElement)?.attributeValueIgnoringNS("w") }
                .compactMap(Int.init)
                .reduce(0, +)
            declaredWidth = sum > 0 ? sum : nil
        }

        guard let width = declaredWidth else { return false }

        // 50 twips ≈ 2.5pt — tolerance for rounding noise.
        guard width > textAreaTwips + 50 else { return false }

        log.info("Shrinking table: declared \(width) twips > text area \(textAreaTwips) twips")
        scaleColumnAndCellWidths(table: table, originalWidth: width, targetWidth: textAreaTwips)
        setTableWidthToFullPagePercent(table: table)
        return true
    }

    /// Proportionally scales every `<w:gridCol w:w>` and every descendant
    /// `<w:tcW w:w>` (only when expressed in dxa) so that the column widths
    /// sum to `targetWidth` instead of `originalWidth`. The last column
    /// absorbs any rounding remainder.
    ///
    /// Required when we set `<w:tblW>` to a percentage: without this, the
    /// per-column dxa widths still claim the original total, which causes
    /// LibreOffice to render cells overlapping each other.
    private static func scaleColumnAndCellWidths(table: XMLElement, originalWidth: Int, targetWidth: Int) {
        guard originalWidth > 0 else { return }

        // Scale <w:gridCol> widths. Track the new widths so we know the
        // post-scaling sum and can correct any rounding drift on the last col.
        let gridCols = ((try? table.nodes(forXPath: "./*[local-name()='tblGrid']/*[local-name()='gridCol']")) ?? [])
            .compactMap { $0 as? XMLElement }

        var newGridWidths: [Int] = []
        var runningSum = 0
        for (i, col) in gridCols.enumerated() {
            guard let oldW = col.attributeValueIgnoringNS("w").flatMap(Int.init) else {
                newGridWidths.append(0)
                continue
            }
            let scaled: Int
            if i == gridCols.count - 1 {
                // Last column absorbs the remainder.
                scaled = max(0, targetWidth - runningSum)
            } else {
                scaled = Int((Double(oldW) * Double(targetWidth) / Double(originalWidth)).rounded())
            }
            newGridWidths.append(scaled)
            runningSum += scaled
            setAttributeIgnoringNS(element: col, localName: "w", value: String(scaled))
        }

        // Scale every <w:tcW> in every row, but only when expressed in dxa.
        // pct/auto widths are responsive already.
        let tcWs = ((try? table.nodes(forXPath: ".//*[local-name()='tcW']")) ?? [])
            .compactMap { $0 as? XMLElement }
        for tcW in tcWs {
            guard tcW.attributeValueIgnoringNS("type") == "dxa",
                  let oldW = tcW.attributeValueIgnoringNS("w").flatMap(Int.init) else {
                continue
            }
            let scaled = Int((Double(oldW) * Double(targetWidth) / Double(originalWidth)).rounded())
            setAttributeIgnoringNS(element: tcW, localName: "w", value: String(scaled))
        }
    }

    /// Replaces an attribute matched by local name (any namespace prefix).
    /// Preserves whatever prefix the document originally used (typically `w:`)
    /// rather than hard-coding it.
    private static func setAttributeIgnoringNS(element: XMLElement, localName: String, value: String) {
        guard let attrs = element.attributes else { return }
        for attr in attrs where attr.localName == localName {
            guard let name = attr.name else { return }
            element.removeAttribute(forName: name)
            let replacement = XMLNode.attribute(withName: name, stringValue: value) as! XMLNode
            element.addAttribute(replacement)
            return
        }
    }

    /// Sets the table's `<w:tblW>` to `type="pct" w="5000"` (100% in
    /// fiftieths of percent — OOXML's pct unit).
    private static func setTableWidthToFullPagePercent(table: XMLElement) {
        let tblPr: XMLElement
        if let existing = (try? table.nodes(forXPath: "./*[local-name()='tblPr']").first) as? XMLElement {
            tblPr = existing
        } else {
            tblPr = XMLElement(name: "w:tblPr")
            table.insertChild(tblPr, at: 0)
        }

        if let existingTblW = (try? tblPr.nodes(forXPath: "./*[local-name()='tblW']").first) as? XMLElement {
            tblPr.removeChild(at: existingTblW.index)
        }

        let tblW = XMLElement(name: "w:tblW")
        tblW.addAttribute(XMLNode.attribute(withName: "w:w", stringValue: "5000") as! XMLNode)
        tblW.addAttribute(XMLNode.attribute(withName: "w:type", stringValue: "pct") as! XMLNode)
        tblPr.insertChild(tblW, at: 0)
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runProcess(executable: String, args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            let errText = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(
                domain: "DOCXPreProcessor",
                code: Int(p.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "\(executable) failed: \(errText)"]
            )
        }
    }
}

private extension XMLElement {
    /// Returns the attribute value by local name, ignoring the namespace prefix.
    /// Word uses the `w:` prefix on every attribute (e.g., `w:w`, `w:type`),
    /// but XPath namespace handling in `XMLDocument` is fiddly — easier to
    /// just scan attributes by local name.
    func attributeValueIgnoringNS(_ localName: String) -> String? {
        guard let attrs = self.attributes else { return nil }
        for attr in attrs {
            if attr.localName == localName {
                return attr.stringValue
            }
        }
        return nil
    }
}
