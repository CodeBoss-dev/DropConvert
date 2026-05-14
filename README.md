# DropConvert

https://github.com/user-attachments/assets/abc21e82-242f-422f-a458-f46659e2112e

⭐️ If DropConvert saves you from uploading a document to an online converter, consider starring the repo — it helps others discover the project. ⭐️

**Convert files on your Mac. Locally. No documents ever leave your machine.**

A native macOS menu bar app for converting between PDF, DOCX, PPTX, XLSX, ODF formats, and common images. Drag a file onto the menu bar icon — the converted file appears next to the original. No uploads, no cloud, no third-party servers.

You can verify this yourself: pull the Wi-Fi cable after first launch. Every conversion still works.

## Download

**👉 [Download the latest release](https://github.com/CodeBoss-dev/DropConvert/releases/latest)** — macOS 13+, Apple Silicon.

## Running the app for the first time

Because this app isn't notarized by Apple (notarization requires a $99/yr Apple Developer account, which is being deferred until the app is validated), macOS will block it on first launch with a *"Apple could not verify"* dialog. **This is not because the app is malware.** It's the standard treatment for apps distributed outside the App Store that have not been notarized. To run it:

1. Click **Done** on the warning dialog.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to the message *"DropConvert was blocked because it is not from an identified developer."*
4. Click **Open Anyway** → enter your password → confirm.

Once approved, that copy of the app can open normally. The full source code is in this repo if you want to inspect how it works.

For more detail on installation, network access, checksums, and updates, see [TRUST_AND_INSTALL.md](TRUST_AND_INSTALL.md).

## License

MIT for DropConvert itself. The bundled LibreOffice engine (downloaded on first launch) is licensed under the [Mozilla Public License 2.0](https://www.libreoffice.org/about-us/licenses/) — see [ACKNOWLEDGMENTS.md](ACKNOWLEDGMENTS.md).
