import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import os

private let log = Logger(subsystem: "com.dropconvert", category: "ImageConverter")

enum ImageConverterError: LocalizedError {
    case unreadableSource
    case unsupportedDestinationType
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableSource:        return "Could not read source image."
        case .unsupportedDestinationType: return "Unsupported output image format."
        case .encodingFailed:          return "Failed to encode output image."
        }
    }
}

enum ImageConverter {
    /// Convert `input` to `destinationType`, writing to `outputURL`.
    /// Returns the URL of the written output file.
    static func convert(input: URL, to destinationType: UTType, outputURL: URL) async throws -> URL {
        log.info("convert called: \(input.path) -> \(destinationType.identifier)")

        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            log.error("CGImageSourceCreateWithURL returned nil for \(input.path)")
            throw ImageConverterError.unreadableSource
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            log.error("CGImageSourceCreateImageAtIndex returned nil")
            throw ImageConverterError.unreadableSource
        }

        log.info("output path: \(outputURL.path)")

        let uti = destinationType.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, uti, 1, nil) else {
            log.error("CGImageDestinationCreateWithURL returned nil for UTI \(destinationType.identifier)")
            throw ImageConverterError.unsupportedDestinationType
        }

        let options: [CFString: Any] = compressionOptions(for: destinationType)
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            log.error("CGImageDestinationFinalize failed")
            throw ImageConverterError.encodingFailed
        }

        log.info("conversion complete: \(outputURL.path)")
        return outputURL
    }

    private static func compressionOptions(for type: UTType) -> [CFString: Any] {
        if type.conforms(to: .jpeg) {
            return [kCGImageDestinationLossyCompressionQuality: 0.85]
        }
        return [:]
    }

    /// Smart default output type for a given input UTType.
    /// PNG → JPEG, everything else → PNG.
    static func smartDefault(for inputType: UTType) -> UTType {
        if inputType.conforms(to: .png) { return .jpeg }
        return .png
    }
}
