# Acknowledgments

ConverterApp uses the following open-source software and Apple system frameworks.

---

## LibreOffice

Copyright © 2000–2024 The Document Foundation and contributors.

Licensed under the **Mozilla Public License 2.0 (MPL-2.0)**.

ConverterApp bundles a stripped copy of the LibreOffice headless engine to perform
PDF ↔ DOCX document conversion on-device. No modifications have been made to the
LibreOffice source code.

Full source code is available at: https://www.libreoffice.org/download/source-code/

Full license text: https://www.mozilla.org/en-US/MPL/2.0/

---

## Apple Frameworks

The following Apple system frameworks are used under the terms of the
[Apple SDK License Agreement](https://developer.apple.com/terms/):

| Framework | Purpose |
|-----------|---------|
| AppKit | Menu bar UI, `NSStatusItem`, drag-and-drop |
| PDFKit | PDF parsing and page rendering |
| Vision | On-device OCR for scanned PDFs |
| Core Image | Image processing pipeline |
| ImageIO | Image encoding and decoding (PNG, JPEG, HEIC, TIFF, BMP) |
| UserNotifications | Conversion progress and completion notifications |
| Carbon | Global hotkey registration (`RegisterEventHotKey`) |
| UniformTypeIdentifiers | File type detection |

---

## Swift

Copyright © 2014–2024 Apple Inc. and the Swift project authors.

Licensed under the **Apache License 2.0** with a Runtime Library Exception.

https://swift.org/LICENSE.txt

---

*ConverterApp is an independent open-source project and is not affiliated with The Document Foundation or Apple Inc.*
