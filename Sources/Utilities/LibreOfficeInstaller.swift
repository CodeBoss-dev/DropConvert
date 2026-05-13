import Foundation
import CryptoKit
import os

private let log = Logger(subsystem: "com.dropconvert", category: "LibreOfficeInstaller")

/// Errors produced by the on-demand LibreOffice installer.
enum LibreOfficeInstallError: Error, LocalizedError {
    case downloadFailed(Int)
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(exitCode: Int32, stderr: String)
    case cancelled
    case missingSoffice
    case fileSystem(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let code):
            return "Engine download failed (HTTP \(code))."
        case .checksumMismatch:
            return "Engine download is corrupted. Please retry."
        case .extractionFailed(let code, _):
            return "Engine extraction failed (tar exit \(code))."
        case .cancelled:
            return "Engine install was cancelled."
        case .missingSoffice:
            return "Engine install completed but the soffice binary is missing."
        case .fileSystem(let msg):
            return "Engine install failed: \(msg)"
        }
    }

    var debugDescription: String {
        switch self {
        case .checksumMismatch(let expected, let actual):
            return "SHA-256 mismatch: expected \(expected), got \(actual)"
        case .extractionFailed(_, let stderr):
            return "tar stderr: \(stderr)"
        default:
            return errorDescription ?? "unknown"
        }
    }
}

/// Manages the on-demand download/extraction of the bundled LibreOffice engine into
/// `~/Library/Application Support/DropConvert/LibreOffice/`. Keeping the engine outside
/// the .app bundle lets us ship a ~50MB installer while still running fully offline once
/// the user has converted at least once.
enum LibreOfficeInstaller {

    // MARK: - Configuration

    /// Engine version we expect on disk. Bumping this triggers a re-install on next launch.
    static let expectedVersion = "26.2.3"

    /// HTTPS URL of the engine tarball. Replace with the production CDN URL (Cloudflare R2
    /// or GitHub Releases) once hosting is set up. `file://` URLs are accepted for local
    /// testing — see `make engine-tarball`.
    static let downloadURL = URL(string: "https://github.com/CodeBoss-dev/DropConvert/releases/download/v1.3.0/LibreOffice-26.2.3-aarch64.tar.gz")!

    /// SHA-256 of the tarball (hex, lowercase). Compute with:
    ///   `shasum -a 256 LibreOffice-26.2.3-aarch64.tar.gz`
    static let expectedSHA256 = "20232d7763c596a474c0df47fd7f23b2610ea00b98919a01932029e148c165dd"

    // MARK: - Paths

    /// `~/Library/Application Support/DropConvert/`
    static var applicationSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DropConvert", isDirectory: true)
    }

    /// `…/DropConvert/LibreOffice/`
    static var engineDir: URL {
        applicationSupportDir.appendingPathComponent("LibreOffice", isDirectory: true)
    }

    /// `…/DropConvert/LibreOffice/MacOS/soffice`
    static var installedSofficePath: URL {
        engineDir.appendingPathComponent("MacOS").appendingPathComponent("soffice")
    }

    /// `…/DropConvert/LibreOffice/version.txt` — installation marker.
    static var versionMarker: URL {
        engineDir.appendingPathComponent("version.txt")
    }

    // MARK: - State

    /// `true` when the engine is present, executable, and matches `expectedVersion`.
    static var isInstalled: Bool {
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: installedSofficePath.path) else { return false }
        guard let data = try? Data(contentsOf: versionMarker),
              let installed = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return false }
        return installed == expectedVersion
    }

    // MARK: - Install

    /// Downloads the engine tarball with progress, verifies SHA-256, extracts atomically
    /// to `engineDir`, and writes the version marker. Safe to call when already installed
    /// — it will overwrite. Throws `LibreOfficeInstallError.cancelled` if the task is
    /// cancelled mid-flight.
    ///
    /// `progressHandler` is invoked on the cooperative task's executor; callers that need
    /// to update UI should hop to `@MainActor` themselves.
    static func install(progressHandler: @Sendable @escaping (Double) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: applicationSupportDir, withIntermediateDirectories: true)

        let tarball = applicationSupportDir.appendingPathComponent("engine-download.tar.gz")
        try? fm.removeItem(at: tarball)

        try await downloadTarball(to: tarball, progressHandler: progressHandler)
        try Task.checkCancellation()

        try verifyChecksum(of: tarball)
        try Task.checkCancellation()

        try await extractAndInstall(tarball: tarball)
        try? fm.removeItem(at: tarball)

        guard fm.isExecutableFile(atPath: installedSofficePath.path) else {
            throw LibreOfficeInstallError.missingSoffice
        }

        try Data(expectedVersion.utf8).write(to: versionMarker, options: .atomic)
        log.info("engine install complete at \(engineDir.path, privacy: .public)")
    }

    // MARK: - Download (streamed with progress)

    private static func downloadTarball(
        to destination: URL,
        progressHandler: @Sendable @escaping (Double) -> Void
    ) async throws {
        let request = URLRequest(url: downloadURL)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw LibreOfficeInstallError.downloadFailed(http.statusCode)
        }

        let total = response.expectedContentLength  // -1 if unknown
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)
        var lastReport: Double = -1

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= 64 * 1024 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if total > 0 {
                    let fraction = Double(received) / Double(total)
                    if fraction - lastReport >= 0.005 {
                        lastReport = fraction
                        progressHandler(fraction)
                    }
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        progressHandler(1.0)
        log.info("downloaded \(received) bytes")
    }

    // MARK: - Checksum

    private static func verifyChecksum(of file: URL) throws {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1 << 20)  // 1 MiB
            if chunk.isEmpty { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        let digest = hasher.finalize()
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex == expectedSHA256.lowercased() else {
            log.error("checksum mismatch expected=\(expectedSHA256, privacy: .public) actual=\(hex, privacy: .public)")
            throw LibreOfficeInstallError.checksumMismatch(expected: expectedSHA256, actual: hex)
        }
    }

    // MARK: - Extraction (atomic: extract to .tmp → rename)

    private static func extractAndInstall(tarball: URL) async throws {
        let fm = FileManager.default
        let stagingDir = applicationSupportDir.appendingPathComponent("LibreOffice.staging", isDirectory: true)
        let oldDir = applicationSupportDir.appendingPathComponent("LibreOffice.old", isDirectory: true)

        try? fm.removeItem(at: stagingDir)
        try? fm.removeItem(at: oldDir)
        try fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        // We use gzip-compressed tarballs (.tar.gz) rather than zstd because macOS's
        // bsdtar shells out to a separate `zstd` binary for zstd decompression —
        // and that binary is NOT in the PATH a GUI app inherits unless the user has
        // installed it via Homebrew. gzip is handled natively by libarchive, works
        // for everyone, and costs only ~50MB more download size.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", tarball.path, "-C", stagingDir.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle(forWritingAtPath: "/dev/null") ?? Pipe().fileHandleForWriting

        // Drain stderr asynchronously so a chatty tar can't fill the buffer and deadlock.
        var stderrData = Data()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { stderrData.append(chunk) }
        }

        try process.run()
        process.waitUntilExit()
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let stderrText = String(decoding: stderrData, as: UTF8.self)
        log.info("tar exit=\(process.terminationStatus, privacy: .public) stderr=\(stderrText, privacy: .public)")

        if process.terminationStatus != 0 {
            try? fm.removeItem(at: stagingDir)
            throw LibreOfficeInstallError.extractionFailed(exitCode: process.terminationStatus, stderr: stderrText)
        }

        // The tarball may contain either `LibreOffice/MacOS/soffice` directly or just
        // `MacOS/soffice` at the top level. Locate `MacOS/soffice` and use its parent as
        // the engine root.
        let installedRoot = try locateEngineRoot(in: stagingDir)

        // Atomic swap: move existing → .old, move new → engineDir, delete .old.
        if fm.fileExists(atPath: engineDir.path) {
            try fm.moveItem(at: engineDir, to: oldDir)
        }
        do {
            try fm.moveItem(at: installedRoot, to: engineDir)
        } catch {
            // Roll back if the rename failed.
            if fm.fileExists(atPath: oldDir.path) {
                try? fm.moveItem(at: oldDir, to: engineDir)
            }
            throw LibreOfficeInstallError.fileSystem("could not install engine: \(error.localizedDescription)")
        }

        // Cleanup. Staging dir may still contain other top-level entries.
        try? fm.removeItem(at: stagingDir)
        try? fm.removeItem(at: oldDir)
    }

    /// Walks the staging directory to find the folder containing `MacOS/soffice`.
    private static func locateEngineRoot(in staging: URL) throws -> URL {
        let fm = FileManager.default
        let direct = staging.appendingPathComponent("MacOS/soffice")
        if fm.fileExists(atPath: direct.path) {
            return staging
        }
        let children = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
        for child in children {
            let candidate = child.appendingPathComponent("MacOS/soffice")
            if fm.fileExists(atPath: candidate.path) {
                return child
            }
        }
        throw LibreOfficeInstallError.missingSoffice
    }
}
