import Foundation

enum PDFToWordConverter {
    /// Converts a PDF file to DOCX next to the source file.
    ///
    /// Flow:
    ///   1. Probe the PDF for extractable text.
    ///   2. If text-based → LibreOffice + DOCXPostProcessor.
    ///   3. If scanned → Vision OCR + DOCXBuilder.
    static func convert(input: URL, outputURL: URL) async throws -> URL {
        if PDFTextProbe.isLikelyScanned(input) {
            return try await convertScanned(input: input, outputURL: outputURL)
        }
        return try await convertTextBased(input: input, outputURL: outputURL)
    }

    private static func convertTextBased(input: URL, outputURL: URL) async throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DropConvert-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let loOutput = try await LibreOfficeRunner.convert(
            input: input,
            to: "docx:MS Word 2007 XML",
            outputDir: tmpDir,
            infilter: "writer_pdf_import"
        )
        try DOCXPostProcessor.stripImageOverlays(at: loOutput)

        // Move from LibreOffice's auto-named output to the caller-chosen path.
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: loOutput, to: outputURL)
        return outputURL
    }

    private static func convertScanned(input: URL, outputURL: URL) async throws -> URL {
        let pages = try await OCRPreprocessor.recognize(pdf: input)
        try DOCXBuilder.build(pages: pages, outputURL: outputURL)
        return outputURL
    }
}
