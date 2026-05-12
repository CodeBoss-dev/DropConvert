import Foundation
import PDFKit
import Vision
import AppKit

enum OCRError: Error, LocalizedError {
    case cannotOpenPDF(URL)
    case pageRenderFailed(Int)
    case recognitionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .cannotOpenPDF(let url):       return "Cannot open PDF at \(url.path)"
        case .pageRenderFailed(let i):      return "Failed to render page \(i)"
        case .recognitionFailed(let err):   return "OCR failed: \(err.localizedDescription)"
        }
    }
}

/// Runs Apple Vision OCR on each page of a PDF, returning recognized text lines per page.
enum OCRPreprocessor {
    /// Renders each page at 2x scale (for sharper OCR) and runs VNRecognizeTextRequest.
    /// - Returns: array of pages, each containing an ordered array of recognized lines.
    static func recognize(pdf url: URL) async throws -> [[String]] {
        guard let pdf = PDFDocument(url: url) else { throw OCRError.cannotOpenPDF(url) }

        var pages: [[String]] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else {
                throw OCRError.pageRenderFailed(i)
            }
            let cgImage = try renderPage(page, scale: 2.0)
            let lines = try await recognizeText(in: cgImage)
            pages.append(lines)
        }
        return pages
    }

    // MARK: - Rendering

    private static func renderPage(_ page: PDFPage, scale: CGFloat) throws -> CGImage {
        let bounds = page.bounds(for: .mediaBox)
        let width  = Int(bounds.width  * scale)
        let height = Int(bounds.height * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw OCRError.pageRenderFailed(page.pageRef?.pageNumber ?? -1)
        }

        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)

        guard let image = ctx.makeImage() else {
            throw OCRError.pageRenderFailed(page.pageRef?.pageNumber ?? -1)
        }
        return image
    }

    // MARK: - Vision OCR

    private static func recognizeText(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(error))
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(error))
            }
        }
    }
}
