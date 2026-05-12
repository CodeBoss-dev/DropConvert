APP_NAME       = ConverterApp
BUILD_DIR      = .build/release
APP_BUNDLE     = $(APP_NAME).app
CONTENTS       = $(APP_BUNDLE)/Contents
MACOS_DIR      = $(CONTENTS)/MacOS
RESOURCES_DIR  = $(CONTENTS)/Resources
LO_SRC         = LibreOffice
ENGINE_VERSION = 26.2.3
ENGINE_ARCH    = aarch64
ENGINE_TARBALL = LibreOffice-$(ENGINE_VERSION)-$(ENGINE_ARCH).tar.zst

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
	@echo "→ Packaging $(ENGINE_TARBALL) (zstd via tar)"
	@tar --options 'zstd:compression-level=19' \
	     --zstd \
	     -cf $(ENGINE_TARBALL) \
	     -C $(LO_SRC) .
	@echo "→ SHA-256:"
	@shasum -a 256 $(ENGINE_TARBALL)
	@echo "→ Size:"
	@du -h $(ENGINE_TARBALL)

clean:
	@rm -rf .build $(APP_BUNDLE)
	@echo "✓ Cleaned"
