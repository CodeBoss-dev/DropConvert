import Foundation

/// Generic office-document converter built on top of LibreOffice. Used for any
/// office source that doesn't have a dedicated converter (PPTX, XLSX, ODT, RTF,
/// CSV, etc.). DOCX↔PDF still go through `WordToPDFConverter` /
/// `PDFToWordConverter` because those have extra pre/post processing.
enum OfficeConverter {
    /// Converts `input` to the given office target, writing to `outputURL`.
    static func convert(input: URL, target: OfficeTarget, outputURL: URL) async throws -> URL {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConverterApp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let loOutput = try await LibreOfficeRunner.convert(
            input: input,
            to: target.loFormat,
            outputDir: tmpDir
        )

        try? FileManager.default.removeItem(at: outputURL)
        try FileManager.default.moveItem(at: loOutput, to: outputURL)
        return outputURL
    }
}
