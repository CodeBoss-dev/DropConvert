# Trust & Install

DropConvert is a free, open-source macOS utility for converting files locally.
It is not notarized yet, so macOS will ask you to approve it manually the first
time you open it.

## Why macOS Shows a Warning

DropConvert is not currently signed with an Apple Developer ID or notarized by
Apple. That requires a paid Apple Developer Program membership, which is being
deferred until the app has enough real-world validation.

The warning does not mean macOS found malware. It means Apple has not reviewed
or notarized this build.

## First Launch Steps

1. Download the latest release from GitHub.
2. Unzip `DropConvert-<version>.zip`.
3. Move `DropConvert.app` to your Applications folder.
4. Double-click the app. macOS will show an "Apple could not verify" warning.
5. Click `Done`.
6. Open `System Settings -> Privacy & Security`.
7. Scroll to the message saying DropConvert was blocked.
8. Click `Open Anyway`, enter your password, and confirm.

macOS should only require this approval once for that copy of the app.

## What Runs Locally

DropConvert converts documents on your Mac. Your documents are not uploaded to a
server for conversion.

Supported inputs include:

- PDF
- DOCX and DOC
- PPTX and PPT
- XLSX and XLS
- ODT, ODS, ODP
- RTF, CSV, TXT
- PNG, JPG, HEIC, WebP, TIFF, BMP

The app uses LibreOffice for office-document conversion and native macOS
frameworks for image conversion and scanned-PDF text extraction.

## Network Access

DropConvert needs network access for two things:

- Downloading the LibreOffice conversion engine on first use.
- Opening the GitHub Releases page when you choose `Check for Updates...`.

After the LibreOffice engine has been downloaded once, conversions can run
offline. You can verify this by disconnecting from the internet and converting a
file again.

The engine is stored at:

```text
~/Library/Application Support/DropConvert/LibreOffice/
```

## Checksums

The app verifies the downloaded LibreOffice engine before installing it. The
current engine checksum is:

```text
20232d7763c596a474c0df47fd7f23b2610ea00b98919a01932029e148c165dd  LibreOffice-26.2.3-aarch64.tar.gz
```

For the current app release:

```text
de7c0258dbcdf8eb341bc02d82252e373fc733feed1d58e28bab60b6eefa24ba  DropConvert-1.3.0.zip
```

To verify a downloaded file yourself:

```sh
shasum -a 256 DropConvert-1.3.0.zip
shasum -a 256 LibreOffice-26.2.3-aarch64.tar.gz
```

The printed value should match the checksum above.

## Updates

DropConvert does not use Sparkle auto-updates yet. The menu bar item
`Check for Updates...` opens the GitHub Releases page so you can compare your
installed version with the latest release.

This is intentional for now: without notarization, automatic updates would still
run into macOS trust prompts. A proper signed and notarized update flow is the
right next step once the app is validated.

## Source Code

The full source code is available in this repository. If you are comfortable
with Swift/macOS development, you can inspect the code or build the app yourself.
