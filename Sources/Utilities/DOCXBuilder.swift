import Foundation

enum DOCXBuilderError: Error, LocalizedError {
    case zipFailed(Int32)
    case writeFailed(URL)

    var errorDescription: String? {
        switch self {
        case .zipFailed(let code): return "zip exited \(code)"
        case .writeFailed(let url): return "Failed to write file at \(url.path)"
        }
    }
}

/// Builds a minimal valid DOCX from a list of pages, each containing paragraphs.
/// The result is a Word-readable .docx with plain paragraphs separated by page breaks.
enum DOCXBuilder {
    /// Writes a DOCX file at `outputURL` containing the given pages of text lines.
    /// Each line becomes one paragraph; pages are separated by hard page breaks.
    static func build(pages: [[String]], outputURL: URL) throws {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("DOCXBuilder-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: workDir) }

        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: workDir.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: workDir.appendingPathComponent("word"), withIntermediateDirectories: true)

        try contentTypesXML.write(
            to: workDir.appendingPathComponent("[Content_Types].xml"),
            atomically: true, encoding: .utf8
        )
        try rootRelsXML.write(
            to: workDir.appendingPathComponent("_rels/.rels"),
            atomically: true, encoding: .utf8
        )
        try documentXML(for: pages).write(
            to: workDir.appendingPathComponent("word/document.xml"),
            atomically: true, encoding: .utf8
        )

        // Zip the directory contents into outputURL
        try? fm.removeItem(at: outputURL)

        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = workDir
        zip.arguments = ["-qr", outputURL.path, "."]
        try zip.run()
        zip.waitUntilExit()

        guard zip.terminationStatus == 0 else {
            throw DOCXBuilderError.zipFailed(zip.terminationStatus)
        }
        guard fm.fileExists(atPath: outputURL.path) else {
            throw DOCXBuilderError.writeFailed(outputURL)
        }
    }

    // MARK: - XML

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """

    private static let rootRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    private static func documentXML(for pages: [[String]]) -> String {
        var body = ""
        for (pageIndex, lines) in pages.enumerated() {
            for line in lines {
                body += paragraph(line)
            }
            if pageIndex < pages.count - 1 {
                body += pageBreak
            }
        }

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
        \(body)
          </w:body>
        </w:document>
        """
    }

    private static func paragraph(_ text: String) -> String {
        "<w:p><w:r><w:t xml:space=\"preserve\">\(escapeXML(text))</w:t></w:r></w:p>"
    }

    private static let pageBreak = "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"

    private static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&",  with: "&amp;")
         .replacingOccurrences(of: "<",  with: "&lt;")
         .replacingOccurrences(of: ">",  with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'",  with: "&apos;")
    }
}
