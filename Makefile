APP_NAME       = ConverterApp
BUILD_DIR      = .build/release
APP_BUNDLE     = $(APP_NAME).app
CONTENTS       = $(APP_BUNDLE)/Contents
MACOS_DIR      = $(CONTENTS)/MacOS
RESOURCES_DIR  = $(CONTENTS)/Resources
LO_SRC         = LibreOffice
ENGINE_VERSION = 26.2.3
ENGINE_ARCH    = aarch64
ENGINE_TARBALL = LibreOffice-$(ENGINE_VERSION)-$(ENGINE_ARCH).tar.gz

.PHONY: build bundle run clean engine-tarball

build:
	swift build -c release

# v2: app bundle no longer carries LibreOffice. The engine is downloaded into
# ~/Library/Application Support/ConverterApp/LibreOffice/ on first conversion
# via LibreOfficeInstaller. This keeps the website download ~50MB.
bundle: build
	@echo "→ Assembling $(APP_BUNDLE)"
	@rm -rf $(APP_BUNDLE)
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	@cp $(BUILD_DIR)/$(APP_NAME) $(MACOS_DIR)/$(APP_NAME)
	@cp Sources/Resources/Info.plist $(CONTENTS)/Info.plist
	@cp ACKNOWLEDGMENTS.md $(RESOURCES_DIR)/ACKNOWLEDGMENTS.md
	@# Strip extended attributes (com.apple.FinderInfo, com.apple.provenance, etc.)
	@# before signing. macOS's APFS automatically tags files copied across volumes
	@# or downloaded with various xattrs; codesign refuses to sign bundles with
	@# resource forks / FinderInfo and exits with "resource fork, Finder
	@# information, or similar detritus not allowed".
	@xattr -cr $(APP_BUNDLE)
	@# Ad-hoc sign the whole bundle. Without this, an unsigned bundle that has
	@# the quarantine xattr (any download from the web does) triggers macOS's
	@# "damaged and can't be opened" dialog with no recovery path. Ad-hoc
	@# signing isn't trusted by Gatekeeper (users still see the unsigned-app
	@# warning the first time), but it prevents the "damaged" failure mode.
	@# For a fully-trusted experience, a $99/yr Apple Developer ID and
	@# notarization are required — out of scope today.
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "✓ $(APP_BUNDLE) ready (engine downloads on first run)"

run: bundle
	@echo "→ Launching $(APP_NAME)"
	@open $(APP_BUNDLE)

# Produces the engine tarball used by LibreOfficeInstaller. Upload this to your CDN
# (Cloudflare R2, GitHub Releases, etc.) and paste the resulting SHA-256 into
# Sources/Utilities/LibreOfficeInstaller.swift.
engine-tarball:
	@if [ ! -d "$(LO_SRC)" ]; then \
		echo "✗ $(LO_SRC)/ not found. Run Scripts/strip-libreoffice.sh first."; exit 1; \
	fi
	@# gzip rather than zstd: macOS's bsdtar handles gzip natively, but for zstd
	@# it shells out to a separate `zstd` binary that's NOT in a default app
	@# process's PATH (it lives at /opt/homebrew/bin/zstd or similar). Users
	@# without Homebrew get "Can't initialize filter; unable to run program zstd".
	@# gzip costs ~50MB more download size vs. zstd-19 but works for everyone.
	@echo "→ Packaging $(ENGINE_TARBALL) (gzip via tar)"
	@tar -czf $(ENGINE_TARBALL) -C $(LO_SRC) .
	@echo "→ SHA-256:"
	@shasum -a 256 $(ENGINE_TARBALL)
	@echo "→ Size:"
	@du -h $(ENGINE_TARBALL)

clean:
	@rm -rf .build $(APP_BUNDLE)
	@echo "✓ Cleaned"
