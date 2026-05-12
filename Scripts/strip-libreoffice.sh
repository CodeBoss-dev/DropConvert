#!/usr/bin/env bash
# Downloads LibreOffice and strips it down to the headless conversion engine.
# Output goes to ConverterApp/Resources/LibreOffice/.
#
# Run once from the repo root before building:
#   bash Scripts/strip-libreoffice.sh
#
# What we strip and why:
#   - GUI utility binaries (gengal, opencltest, regview, senddoc, uno*, unopkg,
#     uri-encode) — only soffice and the dylibs it loads are needed for
#     `--convert-to`. Headless conversion never invokes the others.
#   (NOTE: xpdfimport is NOT removed despite living in MacOS/. The
#    `writer_pdf_import` filter shells out to it as a separate process —
#    LibreOffice keeps Poppler in its own binary for GPL-license isolation.
#    Removing it breaks PDF->DOCX. Confirmed by direct testing.)
#   - 9 of 10 icon themes — we never show LibreOffice's UI. Keep `colibre`
#     (the default) as a safety net so soffice doesn't complain at startup. (~80MB)
#   - Spell-check dictionaries (dict-en/es/fr) — spell-check is a Writer UI
#     feature. The conversion pipeline does not run spell-check on export. (~55MB)
#   - nlpsolver — the non-linear programming solver for Calc. UI feature. (~6MB)
#   - gallery — clip art library for inserting into documents. Insert-only. (~13MB)
#   - template — document templates (resumes, letters). File>New feature. (~8MB)
#   - wizards — UI wizards (mail merge, label maker). Pure UI. (~5MB)
#   - autocorr — autocorrect dictionaries. Typing-time UI feature. (~900KB)
#   - autotext — text autocompletion. UI feature.
#   - firebird — embedded DB for LO Base. We don't touch Base. (~1.6MB)
#   - help, README, CREDITS.fodt — docs / metadata. (~few MB)
#
# What we KEEP (load-bearing for conversion quality):
#   - All Frameworks/*.dylib — the actual conversion engine (libmergedlo,
#     libsclo, libsdlo, libswlo, etc.)
#   - fonts/ — fallback fonts so documents render correctly even when the
#     user's Mac is missing a font the source document references.
#   - filter/, registry/, types/, basic/, java/ — internal config the
#     conversion engine reads at startup. Removing these breaks soffice.
#   - One icon theme (colibre) — soffice probes for an icon theme on startup.
#   - en.lproj — the only language pack present anyway.

set -euo pipefail

LO_VERSION="26.2.3"
# SHA-256 sourced from the official metalink at:
#   http://download.documentfoundation.org/libreoffice/stable/26.2.3/mac/aarch64/LibreOffice_26.2.3_MacOS_aarch64.dmg.meta4
LO_SHA256_AARCH64="8ea6bdf67dbffc9c47104f73a3c98ed145ff26c00dde44c43633f5b3d741479f"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Stripped LibreOffice lives at the project root (one level above Scripts/).
# `make engine-tarball` reads from this same path (LO_SRC in the Makefile).
DEST="$SCRIPT_DIR/../LibreOffice"
MOUNT_POINT="/Volumes/LibreOffice"

# Detect architecture
ARCH="$(uname -m)"
if [[ "$ARCH" == "arm64" ]]; then
    LO_DMG="LibreOffice_${LO_VERSION}_MacOS_aarch64.dmg"
    # Direct mirror URL — avoids the redirector that causes partial-transfer failures
    LO_URL="https://ftp.osuosl.org/pub/tdf/libreoffice/stable/${LO_VERSION}/mac/aarch64/${LO_DMG}"
    EXPECTED_SHA256="$LO_SHA256_AARCH64"
else
    echo "ERROR: Intel (x86_64) SHA-256 not pinned yet. Run the script on Apple Silicon or add the hash manually." >&2
    exit 1
fi

TMP_DMG="/tmp/$LO_DMG"

echo "==> Architecture: $ARCH"
echo "==> LibreOffice version: $LO_VERSION"

# --- Download (resume-capable) ---
VALID=false
if [[ -f "$TMP_DMG" ]]; then
    SIZE=$(stat -f%z "$TMP_DMG" 2>/dev/null || echo 0)
    if [[ "$SIZE" -gt 10000000 ]]; then
        echo "==> Found existing DMG ($(du -sh "$TMP_DMG" | cut -f1)), verifying hash before using it..."
        ACTUAL=$(shasum -a 256 "$TMP_DMG" | awk '{print $1}')
        if [[ "$ACTUAL" == "$EXPECTED_SHA256" ]]; then
            echo "==> Hash verified. Skipping download."
            VALID=true
        else
            echo "==> Hash mismatch — re-downloading."
            rm -f "$TMP_DMG"
        fi
    else
        echo "==> Cached file too small (${SIZE} bytes), removing."
        rm -f "$TMP_DMG"
    fi
fi

if [[ "$VALID" == false ]]; then
    echo "==> Downloading from $LO_URL ..."
    curl -L --fail --retry 5 --retry-delay 5 -C - --progress-bar -o "$TMP_DMG" "$LO_URL"

    echo "==> Verifying SHA-256..."
    ACTUAL=$(shasum -a 256 "$TMP_DMG" | awk '{print $1}')
    if [[ "$ACTUAL" != "$EXPECTED_SHA256" ]]; then
        echo "ERROR: SHA-256 mismatch!" >&2
        echo "  Expected: $EXPECTED_SHA256" >&2
        echo "  Got:      $ACTUAL" >&2
        rm -f "$TMP_DMG"
        exit 1
    fi
    echo "==> SHA-256 verified."
fi

# --- Mount ---
echo "==> Mounting DMG..."
if [[ -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true
fi
hdiutil attach "$TMP_DMG" -mountpoint "$MOUNT_POINT" -nobrowse -quiet

LO_APP="$MOUNT_POINT/LibreOffice.app"

# --- Copy to destination ---
echo "==> Copying LibreOffice.app/Contents to $DEST ..."
rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -R "$LO_APP/Contents" "$DEST"

# --- Unmount ---
hdiutil detach "$MOUNT_POINT" -quiet

# --- Strip ---
echo "==> Stripping unnecessary components..."
SIZE_BEFORE=$(du -sm "$DEST" | cut -f1)

# Unused MacOS/ binaries. We only invoke `soffice`; everything else is a
# command-line utility for features we don't use.
for bin in gengal opencltest regview senddoc uno unoinfo unopkg uri-encode; do
    rm -f "$DEST/MacOS/$bin"
done
# IMPORTANT: do NOT remove xpdfimport — `writer_pdf_import` shells out to it
# at runtime. Removing it breaks PDF->DOCX with "source file could not be loaded".

# Icon themes — keep only colibre (LibreOffice's default modern theme).
# Removing all of them sometimes makes soffice log warnings at startup.
KEEP_THEME="colibre"
find "$DEST/Resources/config" -maxdepth 1 -name "images_*.zip" \
    ! -name "images_${KEEP_THEME}*.zip" \
    ! -name "images_helpimg.zip" \
    -delete 2>/dev/null || true
# images_helpimg is referenced by some filters' error messages — keep it (small).

# Spell-check dictionaries and the NLP solver. Conversion does not spell-check.
rm -rf \
    "$DEST/Resources/extensions/dict-en" \
    "$DEST/Resources/extensions/dict-es" \
    "$DEST/Resources/extensions/dict-fr" \
    "$DEST/Resources/extensions/nlpsolver" \
    2>/dev/null || true

# Pure-UI / authoring features — gallery, templates, wizards, autocorrect, autotext.
rm -rf \
    "$DEST/Resources/gallery" \
    "$DEST/Resources/template" \
    "$DEST/Resources/wizards" \
    "$DEST/Resources/autocorr" \
    "$DEST/Resources/autotext" \
    "$DEST/Resources/wordbook" \
    2>/dev/null || true

# Embedded database engine — we never touch LibreOffice Base.
rm -rf "$DEST/Resources/firebird" 2>/dev/null || true

# Documentation / credits / sample content.
rm -rf \
    "$DEST/Resources/help" \
    "$DEST/Resources/samples" \
    "$DEST/Resources/readmes" \
    2>/dev/null || true
rm -f \
    "$DEST/Resources/CREDITS.fodt" \
    "$DEST/Resources/LICENSE.html" \
    "$DEST/Resources/NOTICE" \
    "$DEST/Resources/README" \
    "$DEST/Resources/scriptforge.pyi" \
    2>/dev/null || true

# Re-sign — stripping invalidates the original signature.
echo "==> Re-signing with ad-hoc signature..."
find "$DEST/Frameworks" -name "*.dylib" -exec codesign --force --sign - {} \; 2>/dev/null
find "$DEST/MacOS" -type f -perm +111 -exec codesign --force --sign - {} \; 2>/dev/null
xattr -rd com.apple.quarantine "$DEST" 2>/dev/null || true

SIZE_AFTER=$(du -sm "$DEST" | cut -f1)
echo "==> Done."
echo "==> Size before strip: ${SIZE_BEFORE}MB"
echo "==> Size after  strip: ${SIZE_AFTER}MB"
echo "==> Saved: $((SIZE_BEFORE - SIZE_AFTER))MB"
echo "==> Final location: $DEST"
