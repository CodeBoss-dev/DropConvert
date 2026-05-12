import UniformTypeIdentifiers
import Foundation

enum FileKind: CustomStringConvertible {
    case pdf
    case word                        // .docx / .doc — uses dedicated converter for PDF target
    case office(OfficeSource)        // pptx, xlsx, odt, ods, odp, rtf, csv, txt
    case image(UTType)
    case unsupported

    var description: String {
        switch self {
        case .pdf:                return "PDF"
        case .word:               return "Word document"
        case .office(let src):    return src.displayName
        case .image(let t):       return "Image (\(t.preferredFilenameExtension ?? "?"))"
        case .unsupported:        return "Unsupported"
        }
    }
}

enum FileTypeDetector {
    private static let supportedImageTypes: [UTType] = [
        .png, .jpeg, .heic, .webP, .tiff, .bmp
    ]

    static func detect(_ url: URL) -> FileKind {
        guard let uti = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return detectByExtension(url)
        }

        if uti.conforms(to: .pdf) { return .pdf }
        if uti.conforms(to: .data) && isWord(uti) { return .word }

        for imageType in supportedImageTypes where uti.conforms(to: imageType) {
            return .image(uti)
        }

        // Fall through to extension-based detection for office formats. UTType
        // conformance for PPTX/XLSX/ODF varies across macOS versions and
        // sometimes resolves to a generic ZIP UTI — extension is more reliable
        // for these.
        return detectByExtension(url)
    }

    private static func detectByExtension(_ url: URL) -> FileKind {
        let ext = url.pathExtension
        if let source = OfficeFormat.source(forExtension: ext) {
            return .office(source)
        }
        return .unsupported
    }

    private static func isWord(_ uti: UTType) -> Bool {
        // .docx = org.openxmlformats.wordprocessingml.document
        // .doc  = com.microsoft.word.doc
        uti.conforms(to: UTType("org.openxmlformats.wordprocessingml.document")!)
        || uti.conforms(to: UTType("com.microsoft.word.doc")!)
    }
}
