# ConverterApp

**Convert files on your Mac. Locally. No documents ever leave your machine.**

A native macOS menu bar app for converting between PDF, DOCX, PPTX, XLSX, ODF formats, and common images. Drag a file onto the menu bar icon — the converted file appears next to the original. No uploads, no cloud, no third-party servers.

You can verify this yourself: pull the Wi-Fi cable after first launch. Every conversion still works.

## Download

**👉 [Download the latest release](https://github.com/CodeBoss-dev/ConverterApp/releases/latest)** — macOS 13+, Apple Silicon.

## Running the app for the first time

Because this app isn't notarized by Apple (notarization requires a $99/yr Apple Developer account — overkill for a free, open-source tool), macOS will block it on first launch with a *"Apple could not verify"* dialog. **This is not because the app is malware.** It's the standard treatment for any app from outside the App Store that hasn't paid Apple's notarization tax. To run it:

1. Click **Done** on the warning dialog.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the message *"ConverterApp was blocked because it is not from an identified developer."*
4. Click **Open Anyway** → enter your password → confirm.

Done once, never asked again. The full source code is in this repo if you want to verify there's nothing shady inside.

## License

MIT for ConverterApp itself. The bundled LibreOffice engine (downloaded on first launch) is licensed under the [Mozilla Public License 2.0](https://www.libreoffice.org/about-us/licenses/) — see [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md).
