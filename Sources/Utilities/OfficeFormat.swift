import Foundation
import UniformTypeIdentifiers

/// Office document families the app understands. Each case represents a *source*
/// document kind; the picker derives valid output targets from it.
enum OfficeFamily: String, CaseIterable, Sendable {
    case presentation   // pptx, ppt, odp, key (export only)
    case spreadsheet    // xlsx, xls, ods, csv
    case wordProcessing // docx, doc, odt, rtf, txt
}

/// A concrete output target for an office conversion. The `loFormat` value is
/// the LibreOffice `--convert-to` argument (filter name in `ext:Filter` form
/// when needed; bare extension when LO's default filter for that extension is
/// what we want).
///
/// Reference: https://help.libreoffice.org/latest/en-US/text/shared/guide/convertfilters.html
struct OfficeTarget: Sendable, Hashable {
    let label: String           // shown in menu
    let ext: String             // resulting file extension
    let loFormat: String        // value passed to --convert-to
    let family: OfficeFamily

    // MARK: - PDF (every family can export to PDF)
    static let pdf = OfficeTarget(label: "PDF", ext: "pdf", loFormat: "pdf", family: .wordProcessing)

    // MARK: - Word processing
    static let docx = OfficeTarget(label: "Word (.docx)", ext: "docx",
                                   loFormat: "docx:MS Word 2007 XML", family: .wordProcessing)
    static let odt  = OfficeTarget(label: "OpenDocument Text (.odt)", ext: "odt",
                                   loFormat: "odt", family: .wordProcessing)
    static let rtf  = OfficeTarget(label: "Rich Text (.rtf)", ext: "rtf",
                                   loFormat: "rtf", family: .wordProcessing)
    static let txt  = OfficeTarget(label: "Plain Text (.txt)", ext: "txt",
                                   loFormat: "txt:Text", family: .wordProcessing)

    // MARK: - Spreadsheet
    static let xlsx = OfficeTarget(label: "Excel (.xlsx)", ext: "xlsx",
                                   loFormat: "xlsx:Calc MS Excel 2007 XML", family: .spreadsheet)
    static let ods  = OfficeTarget(label: "OpenDocument Sheet (.ods)", ext: "ods",
                                   loFormat: "ods", family: .spreadsheet)
    static let csv  = OfficeTarget(label: "CSV (.csv)", ext: "csv",
                                   loFormat: "csv", family: .spreadsheet)

    // MARK: - Presentation
    static let pptx = OfficeTarget(label: "PowerPoint (.pptx)", ext: "pptx",
                                   loFormat: "pptx:Impress MS PowerPoint 2007 XML", family: .presentation)
    static let odp  = OfficeTarget(label: "OpenDocument Presentation (.odp)", ext: "odp",
                                   loFormat: "odp", family: .presentation)
}

/// Identifies a source office document and exposes the valid set of output targets.
struct OfficeSource: Sendable {
    let ext: String           // canonical extension of the source file (lowercase, no dot)
    let family: OfficeFamily
    let displayName: String

    /// All targets we offer for this source, excluding the source's own format.
    var targets: [OfficeTarget] {
        let all: [OfficeTarget]
        switch family {
        case .wordProcessing:
            all = [.pdf, .docx, .odt, .rtf, .txt]
        case .spreadsheet:
            all = [.pdf, .xlsx, .ods, .csv]
        case .presentation:
            all = [.pdf, .pptx, .odp]
        }
        return all.filter { $0.ext != ext }
    }
}

enum OfficeFormat {
    /// Maps a file extension to an `OfficeSource` if we recognize it as an
    /// office document we can convert via LibreOffice. Returns `nil` for
    /// unrecognized extensions or for `.docx`/`.pdf` which keep their existing
    /// dedicated converters (smart defaults preserved).
    static func source(forExtension rawExt: String) -> OfficeSource? {
        let ext = rawExt.lowercased()
        switch ext {
        // Presentation
        case "pptx": return OfficeSource(ext: "pptx", family: .presentation, displayName: "PowerPoint")
        case "ppt":  return OfficeSource(ext: "ppt",  family: .presentation, displayName: "PowerPoint (legacy)")
        case "odp":  return OfficeSource(ext: "odp",  family: .presentation, displayName: "OpenDocument Presentation")

        // Spreadsheet
        case "xlsx": return OfficeSource(ext: "xlsx", family: .spreadsheet,  displayName: "Excel")
        case "xls":  return OfficeSource(ext: "xls",  family: .spreadsheet,  displayName: "Excel (legacy)")
        case "ods":  return OfficeSource(ext: "ods",  family: .spreadsheet,  displayName: "OpenDocument Sheet")
        case "csv":  return OfficeSource(ext: "csv",  family: .spreadsheet,  displayName: "CSV")

        // Word processing additions (docx is intentionally excluded — it has a
        // dedicated converter with smart defaults to PDF).
        case "odt":  return OfficeSource(ext: "odt",  family: .wordProcessing, displayName: "OpenDocument Text")
        case "rtf":  return OfficeSource(ext: "rtf",  family: .wordProcessing, displayName: "Rich Text")
        case "txt":  return OfficeSource(ext: "txt",  family: .wordProcessing, displayName: "Plain Text")

        default: return nil
        }
    }
}
