import Foundation
import PDFKit

/// Decides whether a PDF contains real extractable text or is a scan that needs OCR.
enum PDFTextProbe {
    /// PDFs with fewer than this many non-whitespace characters across all pages
    /// are treated as scans. Empirically chosen — covers cover-only blank pages
    /// while still flagging genuinely scanned documents.
    static let minTextChars = 50

    /// Returns true if the PDF is likely a scanned document (no embedded text).
    static func isLikelyScanned(_ url: URL) -> Bool {
        guard let pdf = PDFDocument(url: url) else { return false }
        var charCount = 0
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let text = page.string ?? ""
            charCount += text.trimmingCharacters(in: .whitespacesAndNewlines).count
            if charCount >= minTextChars { return false }
        }
        return true
    }
}
