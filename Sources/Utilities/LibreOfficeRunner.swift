import Foundation
import os

private let log = Logger(subsystem: "com.converterapp", category: "LibreOfficeRunner")

enum LibreOfficeError: Error, LocalizedError {
    case sofficeNotFound(URL)
    case conversionFailed(exitCode: Int32, stderr: String)
    case outputNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .sofficeNotFound:
            return "LibreOffice engine not installed. Install it from the menu and try again."
        case .conversionFailed(let code, _):
            return "Document conversion failed (LibreOffice exit \(code))."
        case .outputNotFound:
            return "LibreOffice finished but produced no output file."
        }
    }

    /// Full detail including internal paths — for os.Logger only, never shown to the user.
    var debugDescription: String {
        switch self {
        case .sofficeNotFound(let path):
            return "soffice binary not found at \(path.path)"
        case .conversionFailed(let code, let stderr):
            return "LibreOffice exited \(code): \(stderr)"
        case .outputNotFound(let url):
            return "Expected output not found at \(url.path)"
        }
    }
}

/// Runs LibreOffice headless to convert a document, placing output in a specified directory.
enum LibreOfficeRunner {
    /// Resolves the soffice binary in the user's Application Support directory.
    /// The engine is downloaded on first use by `LibreOfficeInstaller`; if missing,
    /// `convert(...)` throws `sofficeNotFound` which the UI uses to prompt for install.
    static func sofficePath() -> URL {
        LibreOfficeInstaller.installedSofficePath
    }


    /// Converts `input` to `format` (e.g. "pdf", "docx"), writing output to `outputDir`.
    /// Pass `infilter` to override how LibreOffice opens the input (e.g. "writer_pdf_import"
    /// forces PDF→Writer mode so DOCX export works; without it LO defaults to Draw mode).
    /// Returns the URL of the produced file.
    static func convert(
        input: URL,
        to format: String,
        outputDir: URL,
        infilter: String? = nil
    ) async throws -> URL {
        let soffice = sofficePath()
        guard FileManager.default.isExecutableFile(atPath: soffice.path) else {
            throw LibreOfficeError.sofficeNotFound(soffice)
        }

        var args: [String] = [
            "--headless",
            "--norestore",
            "--nofirststartwizard",
        ]
        if let infilter {
            args += ["--infilter=\(infilter)"]
        }
        args += [
            "--convert-to", format,
            "--outdir", outputDir.path,
            input.path,
        ]

        let process = Process()
        process.executableURL = soffice
        process.arguments = args

        // LibreOffice writes a lock file and user profile to $HOME by default.
        // Point it at a temp location so it never touches the user's LO install.
        let userInstallDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConverterApp-LO-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: userInstallDir, withIntermediateDirectories: true)

        var env = ProcessInfo.processInfo.environment
        env["HOME"] = userInstallDir.path
        process.environment = env

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(decoding: stderrData, as: UTF8.self)

                guard proc.terminationStatus == 0 else {
                    let err = LibreOfficeError.conversionFailed(
                        exitCode: proc.terminationStatus,
                        stderr: stderrText
                    )
                    log.error("\(err.debugDescription)")
                    continuation.resume(throwing: err)
                    return
                }

                let stem = input.deletingPathExtension().lastPathComponent
                let ext = format.components(separatedBy: ":").first ?? format
                let outputURL = outputDir
                    .appendingPathComponent(stem)
                    .appendingPathExtension(ext)

                guard FileManager.default.fileExists(atPath: outputURL.path) else {
                    let err = LibreOfficeError.outputNotFound(outputURL)
                    log.error("\(err.debugDescription)")
                    continuation.resume(throwing: err)
                    return
                }

                continuation.resume(returning: outputURL)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
