import Foundation

enum WordToPDFConverter {
    /// Converts a DOCX/DOC file to PDF, writing to `outputURL`.
    /// - Returns: URL of the produced PDF.
    static func convert(input: URL, outputURL: URL) async throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConverterApp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Pre-process: any table wider than the page text area gets marked
        // as 100% width so LibreOffice doesn't render it clipped.
        // Falls back to the original input on any failure — we never want
        // pre-processing to block conversion.
        let docxToConvert: URL
        if input.pathExtension.lowercased() == "docx",
           let preprocessed = try? DOCXPreProcessor.shrinkOverflowingTables(input: input) {
            docxToConvert = preprocessed
        } else {
            docxToConvert = input
        }
        defer {
            if docxToConvert != input {
                try? FileManager.default.removeItem(at: docxToConvert)
            }
        }

        let loOutput = try await LibreOfficeRunner.convert(input: docxToConvert, to: "pdf", outputDir: tmpDir)

        // Move from LibreOffice's auto-named output to the caller-chosen path.
        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: loOutput, to: outputURL)
        return outputURL
    }
}
