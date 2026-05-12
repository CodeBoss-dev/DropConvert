# PLAN.md — macOS File Converter Menu Bar App

## Overview

A native macOS menu bar app that converts files locally on-device with drag-and-drop simplicity. No uploads, no browser, no friction. Built in Swift with Apple frameworks and LibreOffice headless for conversion quality on par with ilovepdf.

---

## Goals

- Personal tool first. No telemetry, no accounts, no internet required.
- Match ilovepdf conversion quality using local processing.
- Entire interaction happens from the menu bar. No separate app window.
- Drag a file onto the menu bar icon, get converted output saved next to the source. No save dialog by default.

---

## Target Conversions (v1 Scope)

| Input | Output |
|-------|--------|
| PDF | DOCX (Word) |
| DOCX (Word) | PDF |
| Images (PNG, JPG, HEIC, WEBP, BMP, TIFF) | Any other image format in this list |

Out of scope for v1: XLSX, PPTX, video, audio, batch conversion.

---

## Tech Stack

| Layer | Technology | Reason |
|-------|------------|--------|
| Build system | SwiftPM + Makefile | No Xcode project — avoids Xcode 26 indexer crash on large bundles |
| UI | Swift, AppKit, NSStatusItem | Native menu bar, no third-party UI framework |
| PDF parsing | Apple PDFKit | Native, fast, no dependency |
| OCR (scanned PDFs) | Apple Vision framework | On-device, high quality, free |
| PDF↔DOCX | LibreOffice headless via Swift Process | Best local conversion quality available |
| DOCX post-processing | Custom DOCXPostProcessor (zip/unzip) | Strips floating image overlays from LibreOffice output |
| Image conversion | Core Image + ImageIO | Native Apple frameworks, handles HEIC natively |
| Save path | SavePathResolver | Smart default (same folder as input); Option-key override for NSSavePanel |
| Global hotkey | Carbon RegisterEventHotKey | Cmd+Shift+C converts current Finder selection |
| Finder integration | NSAppleScript | Reads currently selected file(s) in Finder |

No Python. No Electron. Fully native Swift.

---

## LibreOffice Setup

LibreOffice is **not bundled inside the .app**. Instead:

1. Download the LibreOffice `.dmg` from https://www.libreoffice.org/download/libreoffice-fresh/
2. Move the `.app` to `/tmp/LibreOffice_source.app` (or any temp location)
3. Run `Scripts/strip-libreoffice.sh` — this strips non-essential files and copies the result to `LibreOffice/` in the project root
4. `make bundle` copies `LibreOffice/` into the `.app` bundle via rsync

The stripped LibreOffice lives at `LibreOffice/` in the project root and is referenced by the Makefile. It is gitignored (too large to commit).

CLI invocation pattern (inside the app):

```bash
<app>/Contents/Resources/LibreOffice/MacOS/soffice \
    --headless \
    --infilter=writer_pdf_import \
    --convert-to docx \
    --outdir /path/to/output/ \
    /path/to/input.pdf
```

---

## Architecture

```
ConverterApp/                        ← repo root
  Sources/                           ← all Swift source files
    App/
      AppDelegate.swift
      StatusBarController.swift      ← menu bar icon, drag target, drop zone panel
      DropTargetView.swift           ← NSView that accepts file drops on the icon
      DropZonePanel.swift            ← floating panel shown when dragging near menu bar
      HotkeyManager.swift            ← global hotkey via Carbon RegisterEventHotKey
    Converters/
      PDFToWordConverter.swift       ← LibreOffice headless + DOCXPostProcessor
      WordToPDFConverter.swift       ← LibreOffice headless
      ImageConverter.swift           ← Core Image + ImageIO
    Utilities/
      LibreOfficeRunner.swift        ← resolves bundled soffice path, runs Process
      SavePathResolver.swift         ← smart default save path, Option-key NSSavePanel
      FileTypeDetector.swift         ← UTType-based file kind detection
      FinderSelectionReader.swift    ← AppleScript bridge for Finder selection
      OCRPreprocessor.swift          ← Vision OCR for scanned PDFs
      DOCXPostProcessor.swift        ← strips mc:AlternateContent + w:pict overlays
    Resources/
      Info.plist
  LibreOffice/                       ← stripped LibreOffice (gitignored, ~300MB)
  Scripts/
    strip-libreoffice.sh             ← strips LibreOffice .app to essentials
  Package.swift                      ← SwiftPM manifest
  Makefile                           ← build / bundle / run shortcuts
```

---

## User Flow

1. User drags a file toward the menu bar — a drop zone panel appears near the icon.
2. User drops the file. App detects file type via UTType.
3. For PDF → DOCX or DOCX → PDF: conversion runs immediately, output saved next to source.
4. For image files: a format picker menu appears near the menu bar icon.
5. User picks target format. Conversion runs, output saved next to source.
6. macOS notification fires: "Saved invoice.docx". 
7. Hold Option at drop time to override save location with NSSavePanel.
8. Press Cmd+Shift+C with a file selected in Finder to trigger conversion without dragging.

---

## Conversion Pipeline Detail

### PDF to DOCX

```
Input PDF
    |
    v
PDFKit: check if PDF has extractable text (isScanned check)
    |
    +-- Scanned --> Apple Vision OCR --> searchable PDF (temp file)
    |
    v
LibreOffice headless --infilter=writer_pdf_import --convert-to docx
    |
    v
DOCXPostProcessor: strip mc:AlternateContent + w:pict overlays
(fixes white box issue from Google Docs / Skia-rendered PDFs)
    |
    v
Output .docx saved to resolved path
```

### DOCX to PDF

```
Input DOCX → LibreOffice headless --convert-to pdf → Output .pdf
```

### Image Conversion

```
Input image
    |
    v
SavePathResolver: resolve output URL (default or NSSavePanel)
    |
    v
CGImageSourceCreateWithURL → CGImageSourceCreateImageAtIndex
    |
    v
CGImageDestinationCreateWithURL → CGImageDestinationAddImage → Finalize
    |
    v
Output image at resolved path
```

---

## Smart Save Behavior

`SavePathResolver.resolve(for:outputExtension:utType:)`:

1. If Option key held at drop/trigger time → present NSSavePanel
2. If input directory is not writable → fall back to NSSavePanel
3. Otherwise → save next to input file, auto-renamed with new extension
4. De-duplicate: if output already exists, append ` (1)`, ` (2)`, etc.

---

## Global Hotkey Flow

1. App registers `Cmd+Shift+C` at launch via Carbon `RegisterEventHotKey`
2. On press: `FinderSelectionReader.currentSelection()` reads selected files in Finder
3. Selected file(s) routed through the same `handleDroppedFiles` path as drag-and-drop
4. macOS prompts for Automation permission on first use (one-time native dialog)

---

## Error Handling

| Error | User-facing message |
|-------|---------------------|
| Unsupported file type | "This file type is not supported yet." |
| Conversion failed | "Conversion failed. Try re-exporting the source file." |
| No Finder selection | "No file selected in Finder." |
| LibreOffice not found | "Bundled LibreOffice not found inside the app bundle." |

All errors surface as macOS notifications.

---

## Permissions Required (Info.plist)

- `LSUIElement` = true — menu bar only, no Dock icon
- `NSAppleEventsUsageDescription` — for Finder selection reading via AppleScript
- No network permissions. App is fully offline.
- No sandbox (`ENABLE_APP_SANDBOX = NO`) — required for LibreOffice subprocess and Carbon hotkey

---

## Milestones

| Milestone | Status | Deliverable |
|-----------|--------|-------------|
| M1 | ⬜ Next | Menu bar icon, drag-and-drop, drop zone panel, file type detection |
| M2 | ⬜ | LibreOffice bundled and working; DOCX→PDF end-to-end |
| M3 | ⬜ | PDF→DOCX (text-based) end-to-end |
| M4 | ⬜ | OCR preprocessor; scanned PDF→DOCX works |
| M5 | ⬜ | Image conversion end-to-end (PNG/JPG/HEIC/WEBP/TIFF/BMP) |
| M6 | ⬜ | SavePathResolver smart defaults; Option-key NSSavePanel override |
| M7 | ⬜ | HotkeyManager + FinderSelectionReader; Cmd+Shift+C hotkey |
| M8 | ⬜ | Menu polish, icon states (idle/converting/done/error), "Reveal in Finder" notification |
| M9 | ⬜ | Error handling completeness, ACKNOWLEDGMENTS.md, licensing menu item |

---

## Out of Scope (v1)

- Batch conversion (multiple files at once)
- XLSX, PPTX conversions
- Cloud sync or iCloud integration
- Menubar history persistence across reboots
- App Store distribution (personal tool, direct install)
