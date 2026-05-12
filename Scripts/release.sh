#!/usr/bin/env bash
# Builds release artifacts for distribution.
#
# Produces two files in the project root:
#   - ConverterApp-<version>.zip           (the app — what users download)
#   - LibreOffice-<version>-aarch64.tar.zst (the engine — downloaded on first launch)
#
# Run from the project root:
#   bash Scripts/release.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
cd "$ROOT"

# Read app version from Info.plist
APP_VERSION=$(plutil -extract CFBundleShortVersionString raw Sources/Resources/Info.plist 2>/dev/null || echo "1.0.0")
APP_ZIP="ConverterApp-${APP_VERSION}.zip"
ENGINE_TARBALL="LibreOffice-26.2.3-aarch64.tar.zst"

echo "================================================================"
echo "  Building ConverterApp v${APP_VERSION} for distribution"
echo "================================================================"

# 1. Make sure the stripped LibreOffice exists (needed for engine tarball)
if [[ ! -d "LibreOffice" ]]; then
    echo "✗ LibreOffice/ folder not found at project root."
    echo "  Run this first: bash Scripts/strip-libreoffice.sh"
    exit 1
fi

# 2. Build the app
echo ""
echo "→ Step 1/3: Building the app..."
make bundle

# 3. Package the app as a zip
echo ""
echo "→ Step 2/3: Packaging the app as ${APP_ZIP}..."
rm -f "${APP_ZIP}"
# `ditto` is Apple's recommended tool — it preserves resource forks, code signatures,
# and extended attributes that regular `zip` would strip and break the app.
ditto -c -k --keepParent ConverterApp.app "${APP_ZIP}"

# 4. Build the engine tarball (only if it's missing or older than the LibreOffice/ source)
echo ""
echo "→ Step 3/3: Building the engine tarball..."
if [[ -f "${ENGINE_TARBALL}" ]] && [[ "${ENGINE_TARBALL}" -nt "LibreOffice" ]]; then
    echo "  (already up to date — skipping)"
else
    make engine-tarball
fi

# 5. Print everything the user needs to upload
echo ""
echo "================================================================"
echo "  ✓ Release artifacts ready"
echo "================================================================"
echo ""
echo "Files to upload (from project root):"
ls -lh "${APP_ZIP}" "${ENGINE_TARBALL}" | awk '{printf "  %-50s  %s\n", $9, $5}'
echo ""
echo "SHA-256 hashes (you'll need the engine one for LibreOfficeInstaller.swift):"
echo ""
shasum -a 256 "${ENGINE_TARBALL}" | awk '{printf "  Engine SHA-256: %s\n", $1}'
shasum -a 256 "${APP_ZIP}" | awk '{printf "  App SHA-256:    %s\n", $1}'
echo ""
echo "Next: upload both files, then tell Claude the engine URL + SHA-256."
echo ""
