# Plan: macOS Menu Bar File Converter

## Summary

A native macOS menu bar app built in Swift. Converts files locally, on-device, with no
friction. Drag a file onto the menu bar icon → converted output appears next to the source.
No save dialog, no uploads, no browser.

**Build system:** SwiftPM + Makefile (no Xcode project — avoids Xcode 26 indexer crash).

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Build | SwiftPM + Makefile |
| UI | Swift, AppKit, NSStatusItem |
| PDF parsing | PDFKit |
| OCR | Apple Vision |
| PDF↔DOCX | LibreOffice headless (stripped, placed in `LibreOffice/`) |
| DOCX post-processing | DOCXPostProcessor (strips image overlays from LO output) |
| Image conversion | Core Image + ImageIO |
| Save path | SavePathResolver (smart default + Option-key NSSavePanel) |
| Global hotkey | Carbon RegisterEventHotKey (Cmd+Shift+C) |
| Finder integration | NSAppleScript |

---

## Project Structure

```
ConverterApp/                        ← repo root
  Sources/                           ← Swift source files
    App/
      AppDelegate.swift
      StatusBarController.swift
      DropTargetView.swift
      DropZonePanel.swift
      HotkeyManager.swift
    Converters/
      PDFToWordConverter.swift
      WordToPDFConverter.swift
      ImageConverter.swift
    Utilities/
      LibreOfficeRunner.swift
      SavePathResolver.swift
      FileTypeDetector.swift
      FinderSelectionReader.swift
      OCRPreprocessor.swift
      DOCXPostProcessor.swift
    Resources/
      Info.plist
  LibreOffice/                       ← stripped LibreOffice (~300MB, gitignored)
  Scripts/
    strip-libreoffice.sh             ← strips full LO .app to headless-only essentials
  Package.swift                      ← SwiftPM manifest
  Makefile                           ← build / bundle / run
  Check.md                           ← original spec
  PLAN.md                            ← this file
  MIGRATION.md                       ← SwiftPM migration guide
```

---

## LibreOffice Setup

LibreOffice is NOT bundled inside the repo. Set it up once:

1. Download LibreOffice `.dmg` from https://www.libreoffice.org/download/libreoffice-fresh/
2. Mount the dmg, copy `LibreOffice.app` to `/tmp/LibreOffice_source.app`
3. Run the strip script:
   ```bash
   bash Scripts/strip-libreoffice.sh
   ```
4. This produces a stripped copy at `LibreOffice/` in the project root (~300MB)
5. `make bundle` copies it into the `.app` via rsync automatically

The script removes: app icons, Calc/Impress/Draw/Base/Math binaries, extensions,
templates, non-English language packs, help files, sample files.

It keeps: `MacOS/soffice`, `program/` core engine, `share/registry/`, DOCX and PDF
import/export filters.

---

## Build Commands

```bash
swift build          # compile only
make bundle          # compile + assemble .app bundle
make run             # compile + bundle + launch
make clean           # remove .build/
```

---

## Milestones

| Milestone | Status | Deliverable |
|-----------|--------|-------------|
| M1 | ✅ Done | Menu bar icon, drag-and-drop, drop zone panel, UTType file detection |
| M2 | ✅ Done | LibreOffice bundled; DOCX→PDF end-to-end |
| M3 | ✅ Done | PDF→DOCX (text-based) end-to-end |
| M4 | ✅ Done | Vision OCR preprocessor; scanned PDF→DOCX |
| M5 | ✅ Done | Image conversion end-to-end (PNG/JPG/HEIC/WEBP/TIFF/BMP) |
| M6 | ✅ Done | SavePathResolver smart defaults; Option-key NSSavePanel |
| M7 | ✅ Done | HotkeyManager + FinderSelectionReader; Cmd+Shift+C global hotkey |
| M8 | ✅ Done | Menu polish, icon states, "Reveal in Finder" notification action |
| M9 | ✅ Done | ACKNOWLEDGMENTS.md, licensing menu item, error handling completeness |

**All milestones complete. v1 is done.**

---

## Key Design Decisions

### DOCXPostProcessor
LibreOffice's PDF import filter imports every XObject image from a PDF as a floating
`mc:AlternateContent` shape (with a `w:pict` fallback). On Google Docs / Skia-rendered
PDFs this produces white box overlays covering the text. DOCXPostProcessor strips all
`mc:AlternateContent` and `w:pict` elements from the DOCX XML after LibreOffice runs.
None of these elements contain real text — verified against the actual document structure.

### SavePathResolver
Captures the Option key state at the moment of conversion trigger (drop or hotkey), not
at drop time. This is intentional — storing modifier state across async boundaries is
fragile. The resolver is called synchronously before any async conversion work begins.

### HotkeyManager (Carbon)
Uses `Unmanaged.passRetained` to pass `self` through the C callback boundary, with
`takeUnretainedValue` inside the handler. The retained reference lives for the lifetime
of the installed handler and is released in `deinit` when `RemoveEventHandler` is called.

### No Xcode project
Xcode 26.4.1 has a confirmed bug in `PBXFileSystemSynchronizedRootGroup` — it throws
`NSRangeException` and crashes when a project references a large folder (LibreOffice,
9,473 files). The `.xcodeproj` is replaced by `Package.swift` + `Makefile`. All Swift
source files are unchanged.

---

## Out of Scope (v1)

- Batch conversion
- App Store distribution
- Persistent recent files across reboots

---

## v2: Distribution Refactor (in progress)

Goal: get the website-download size from ~580MB to ~50MB by extracting LibreOffice
from the .app bundle and downloading it on first launch (Xcode-style). Add Sparkle
for app updates and a manifest-based engine update flow.

### Status

- ✅ **Step 1a — Strip script fixed.** `Scripts/strip-libreoffice.sh` rewritten with
  correct paths for LO 26 (was targeting `share/extensions` etc. which don't exist
  in this version). Bundle is now 581MB (was 734MB). Saved 153MB.
  - **Critical lesson:** `xpdfimport` MUST stay. The `writer_pdf_import` filter
    shells out to it for GPL license isolation. Removing it breaks PDF→DOCX with
    "source file could not be loaded". Documented in script header.
- ✅ **Step 1b — Office format expansion.** PPTX, XLSX, ODT, ODS, ODP, RTF, CSV,
  TXT now supported via `OfficeConverter` + `OfficeFormatPicker`. Update the
  "Out of Scope" section above to reflect this.

### Step 2 — Move LibreOffice out of the .app bundle (1-2 days)

**Goal:** App bundle drops from 581MB to ~50MB. LibreOffice lives in
`~/Library/Application Support/ConverterApp/LibreOffice/` and is downloaded on
first conversion attempt.

Detailed sub-steps:

1. **Create `LibreOfficeInstaller.swift`** in `Sources/Utilities/`:
   - `static var installedSofficePath: URL` — returns
     `~/Library/Application Support/ConverterApp/LibreOffice/MacOS/soffice`.
   - `static var isInstalled: Bool` — checks file exists AND is executable AND
     verifies version file matches expected.
   - `static func install(progressHandler: @escaping (Double) -> Void) async throws` —
     downloads `.tar.zst` from a hosting URL, verifies SHA-256, extracts to the
     app support dir atomically (extract to `.tmp` then rename), writes a
     `version.txt` marker.
   - Uses `URLSession.shared.bytes(for:)` for streaming download with progress.
   - Use `Foundation.Process` to invoke `tar -xf` for extraction (zstd support
     is built into macOS 13+ tar).

2. **Update `LibreOfficeRunner.sofficePath()`** to call
   `LibreOfficeInstaller.installedSofficePath` instead of looking inside the
   app bundle. Keep the existing error type `sofficeNotFound` — it now means
   "engine not installed" rather than "broken bundle."

3. **Create `EngineSetupWindow.swift`** in `Sources/App/`:
   - Small NSWindow with a progress bar, status label, "Cancel" button.
   - Shown by `StatusBarController` when a conversion is attempted but
     `LibreOfficeInstaller.isInstalled` is false.
   - On success: dismiss window, retry the queued conversion. On failure:
     show error, offer retry.

4. **Update `StatusBarController.handleDroppedFiles`** to gate every conversion
   on `LibreOfficeInstaller.isInstalled`. If not installed, queue the URLs +
   modifier flags, present `EngineSetupWindow`, then retry on completion.

5. **Update `Makefile`** — remove the `rsync LibreOffice/` step from `bundle`
   target. The .app no longer carries LibreOffice. Add a `make engine-tarball`
   target that produces `LibreOffice-<version>-aarch64.tar.zst` from the
   stripped LibreOffice for hosting.

6. **Pick hosting and host the tarball.** Recommend Cloudflare R2 (free egress)
   or GitHub Releases (free, easy if repo goes public). Hardcode the URL +
   SHA-256 in `LibreOfficeInstaller` for now.

7. **Test matrix** before declaring step 2 done:
   - Fresh install: delete `~/Library/Application Support/ConverterApp/`,
     launch app, drop a file → setup window appears → install completes →
     conversion runs.
   - Cancellation: cancel mid-download → window closes cleanly → next drop
     re-triggers install.
   - Already-installed: relaunch app → setup window does NOT appear → drop
     converts immediately.
   - All conversion types: DOCX→PDF, PDF→DOCX (text), PDF→DOCX (scanned),
     PPTX→PDF, XLSX→PDF, image conversions (these don't need LO at all).

### Step 3 — Sparkle for app updates (half a day)

1. Add Sparkle 2 via SwiftPM: `https://github.com/sparkle-project/Sparkle`,
   product `Sparkle`, target dependency.
2. Create EdDSA signing key: `./bin/generate_keys` from Sparkle's bin tools.
   Public key goes in `Info.plist` as `SUPublicEDKey`. Private key stored
   securely (1Password, NOT in repo).
3. Add `Info.plist` entries: `SUFeedURL` (https URL to appcast.xml on your
   site), `SUEnableAutomaticChecks` = YES, `SUScheduledCheckInterval` = 86400.
4. Initialize `SPUStandardUpdaterController` in `AppDelegate`. Add "Check for
   Updates…" menu item that calls `updater.checkForUpdates(_:)`.
5. Build a release build, sign it with `codesign`, generate appcast entry with
   Sparkle's `generate_appcast` tool, host appcast.xml + the .zip on your site.
6. Test: install older version, run app, confirm update prompt appears.

### Step 4 — Engine update flow (half a day)

1. Host `engine-manifest.json` on your site:
   ```json
   { "version": "26.2.3", "url": "...", "sha256": "...", "size_bytes": ... }
   ```
2. Add `EngineUpdateChecker.swift` — fetches manifest on app launch, compares
   to local `version.txt`. If newer, posts a notification "Engine update
   available — click to install" with a deep-link action.
3. Reuse `EngineSetupWindow` for the update flow (same UX as initial install,
   different label).
4. Atomic swap: download new engine to `LibreOffice.new/`, when complete,
   rename old to `LibreOffice.old/`, rename new to `LibreOffice/`, remove
   `LibreOffice.old/`. Guarantees no half-installed state.

### Step 5 — Hosting + release packaging (couple hours)

1. Cloudflare R2 bucket: `converterapp-releases.<domain>.com` (or use
   r2.dev URL).
2. Upload structure:
   ```
   /app/ConverterApp-1.0.0.zip          ← Sparkle update payload
   /app/appcast.xml                     ← Sparkle feed
   /engine/LibreOffice-26.2.3-aarch64.tar.zst
   /engine/manifest.json
   ```
3. Update `LibreOfficeInstaller` URL + SHA-256.
4. Build website download page that serves `ConverterApp-1.0.0.dmg` directly
   (50MB stub install).

### Risks / open questions

- **Code signing the downloaded binary.** The downloaded LibreOffice has its
  own ad-hoc signature (from strip-libreoffice.sh). When the parent app is
  hardened-runtime + notarized, can it spawn a subprocess with a different
  signature? May need entitlement
  `com.apple.security.cs.disable-library-validation` or similar. Test before
  shipping.
- **First-conversion latency.** ~2 min download on broadband. UX must make
  this feel intentional, not broken.
- **Network failure recovery.** Resume support via HTTP Range requests.
  Already proven by the strip script's curl `-C -`.
