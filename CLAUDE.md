# ConverterApp

A native macOS menu bar file converter that runs entirely on-device. Users drag files onto the menu bar icon (or use a global hotkey to convert the current Finder selection) and get converted output saved next to the source with no save dialog. Conversion is powered by a bundled stripped LibreOffice for PDF↔DOCX, Apple Vision for OCR on scanned PDFs, and Core Image + ImageIO for image format conversions.

## Development Workflow

After completing each phase, automatically run /security-review then /security-scan before committing or moving to the next phase. Fix all CRITICAL and HIGH issues before proceeding.

Read `PLAN.md` at the start of each session to know what phase is next and what's already done.

## Rules

Follow the Swift-specific rules in addition to the common rules:
- `~/.claude/rules/swift/coding-style.md`
- `~/.claude/rules/swift/hooks.md`
- `~/.claude/rules/swift/patterns.md`
- `~/.claude/rules/swift/security.md`
- `~/.claude/rules/swift/testing.md`

Follow the common rules:
- `~/.claude/rules/common/coding-style.md`
- `~/.claude/rules/common/development-workflow.md`
- `~/.claude/rules/common/git-workflow.md`
- `~/.claude/rules/common/hooks.md`
- `~/.claude/rules/common/patterns.md`
- `~/.claude/rules/common/performance.md`
- `~/.claude/rules/common/security.md`
- `~/.claude/rules/common/testing.md`

## Tech Stack

- **Language**: Swift
- **UI Framework**: AppKit (`NSStatusItem` for menu bar)
- **PDF Handling**: PDFKit
- **OCR**: Apple Vision
- **Image Conversion**: Core Image, ImageIO
- **Document Conversion**: LibreOffice headless (bundled, stripped)
- **Concurrency**: Swift async/await
- **System Integration**: Carbon (`RegisterEventHotKey`), AppleScript / Scripting Bridge (Finder selection)
- **Platform**: macOS 13+

## Lessons Learned

Platform-specific gotchas discovered while building this app. Apply these whenever the situation arises — they cost real debugging time to find.

### Status bar UI: use `NSMenu`, not custom `NSPanel`

For "pick one option" interactions in a menu bar app, use `NSMenu.popUp(positioning:at:in:)`. Custom `NSPanel`s with subview click handling do **not** work reliably in background-only (`LSUIElement`) apps:
- The panel never becomes key/main, so `NSButton` action dispatch through the responder chain silently fails.
- `mouseDown`/`mouseUp` on subviews are unreliable without app activation.
- Even `NSEvent.addLocalMonitorForEvents` is flaky when the app isn't active.

`NSMenu` is the OS-blessed primitive — it handles event routing, dismissal, keyboard navigation, and styling for free. When AppKit fights you on a status bar UI, you're probably reaching past the right tool.

To attach a closure to each menu item, subclass `NSMenuItem` with a stored handler and `target = self` (see `ImageFormatPickerPanel.swift` → `ClosureMenuItem`).

### ImageIO has asymmetric codec support

macOS can *read* more image formats than it can *write*. Notably:
- **WebP**: readable on macOS 11+, **not writable** — Apple ships only a decoder.

Always query `CGImageDestinationCopyTypeIdentifiers()` at runtime to find what's actually writable on the current OS. Do not assume "if I can read it, I can write it."

### Prefer `UTType.conforms(to:)` over `==`

UTIs form a hierarchy. A `.jpeg` file may conform to multiple JPEG-family UTIs, and future macOS versions can introduce new variants (e.g. JPEG-XL) under the same family. Equality (`==`) misses these; `conforms(to:)` is the documented, future-proof check.

### Use `os.Logger`, not `print()`

When something goes wrong in a status bar app you can't put a breakpoint on, `os.Logger` is what saves you. Tag with a subsystem and category, then query with:
```
log show --predicate 'subsystem == "com.converterapp"' --last 2m --info
```
This pinpointed the WebP encoder failure in seconds. `print()` output is invisible once the app is bundled and launched via Finder.

### Capture modifier state synchronously

Modifier keys (Option, Shift, etc.) should be read at the moment a conversion is triggered (drop callback, hotkey callback), **never inside an async continuation**. Storing modifier state across `await` boundaries is fragile — the user may have released the key by the time the async work runs. Read `NSEvent.modifierFlags` synchronously and pass the captured value through to any async work.
