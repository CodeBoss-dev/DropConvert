# ConverterApp

A native macOS menu bar file converter that runs entirely on-device. Drag a file onto the menu bar icon — get a converted file next to the original. No uploads, no waiting for a server, no save dialog by default.

## Download

**👉 [Download the latest release](https://github.com/CodeBoss-dev/ConverterApp/releases/latest)**

Unzip, drag `ConverterApp.app` to your Applications folder, and you're ready to go.

**Requirements:** macOS 13 (Ventura) or later, Apple Silicon (M1/M2/M3/M4).

## What it converts

| From | To |
|---|---|
| **PDF** | DOCX (text-based or scanned via Apple Vision OCR) |
| **DOCX** | PDF |
| **PPTX** | PDF, ODP |
| **XLSX** | PDF, ODS, CSV |
| **ODT / RTF / TXT** | PDF, DOCX, and each other |
| **ODS / CSV** | PDF, XLSX |
| **ODP** | PDF, PPTX |
| **Images** (PNG, JPG, HEIC, TIFF, BMP, WebP-read-only) | PNG, JPG, HEIC, TIFF, BMP |

## How to use

- **Drag a file onto the menu bar icon.** The converted file appears next to the original.
- **Hold ⌥ Option while dropping** to open a save dialog and choose where the output goes.
- **Press ⌘⇧C in Finder** to convert your current Finder selection without leaving Finder.
- **Click the menu bar icon → "How to Use…"** to re-open the welcome guide any time.

## First launch

1. Right-click `ConverterApp.app` → **Open** → confirm the security dialog.
   (macOS shows this for apps not from the App Store. You only need to do it once.)
2. The first time you drop a file, the app downloads its conversion engine (~140 MB, one time only). Subsequent conversions are instant.

## Privacy

Conversion happens **entirely on your Mac.** Files never leave your machine. The app:
- Has no telemetry, analytics, or tracking.
- Connects to the internet **only once**, on first launch, to download the conversion engine from this GitHub repository.
- Stores no data outside `~/Library/Application Support/ConverterApp/` (the engine cache).

You can verify by disconnecting from the internet — once the engine is installed, all conversions continue to work offline.

## How it works

The app is intentionally tiny (~200 KB). The heavy lifting comes from a stripped, headless build of [LibreOffice](https://www.libreoffice.org/) that's downloaded on first use into `~/Library/Application Support/ConverterApp/`. The app itself is Swift / AppKit / SwiftUI; OCR uses Apple Vision; image conversions use ImageIO.

This split keeps the website download under a megabyte and lets you update the app frequently without re-downloading hundreds of megabytes each time.

## Building from source

```bash
git clone https://github.com/CodeBoss-dev/ConverterApp.git
cd ConverterApp
bash Scripts/strip-libreoffice.sh    # downloads + strips LibreOffice (~5 min)
make bundle                          # builds the .app
open ConverterApp.app
```

Requires Swift 5.9+ (Xcode 15 or command-line tools).

## License

ConverterApp itself is [released here under the MIT License](https://opensource.org/licenses/MIT).

The bundled (downloaded-on-first-launch) LibreOffice components are licensed under the [Mozilla Public License 2.0](https://www.libreoffice.org/about-us/licenses/) — see [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md) for full attribution.

## Troubleshooting

**"App can't be opened because Apple cannot check it for malicious software."** Right-click the app → **Open** → click **Open** in the dialog. Only needed the first time.

**Engine download fails.** Check your internet connection, then quit and re-launch the app. The download resumes from where it stopped.

**A specific file fails to convert.** [Open an issue](https://github.com/CodeBoss-dev/ConverterApp/issues) with the file type, source app (Word, Pages, Google Docs, etc.), and any error message you saw.

---

Built by [CodeBoss-dev](https://github.com/CodeBoss-dev).
