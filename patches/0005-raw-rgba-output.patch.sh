#!/usr/bin/env bash
# Emit a raw RGBA8 blob from Image::Write (POVRAY_WASM) instead of a PNG, so the
# Typst plugin returns pixels the host embeds directly via
# image(format: (encoding: "rgba8", ...)) — skipping the zlib PNG encode here and
# the PNG decode in Typst (which re-compresses for the PDF anyway). The pixels
# are gamma/dither/premultiply-encoded identically to the PNG path, so output is
# byte-for-byte what the PNG would have decoded to.
#
# Applied after 0001, which adds the PNG-only Image::Write hook this rewrites.

set -euo pipefail

POVRAY_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/0005-raw-rgba-output.patch"

cd "$POVRAY_DIR"

if git apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
    echo ">> 0005 already applied"
    exit 0
fi

git apply "$PATCH_FILE"
echo ">> raw RGBA output applied"
