#!/usr/bin/env bash
# Strip features the WASM plugin can't use (no filesystem):
#
#   - TrueType text rendering (`text { ttf ... }`): stub Parse_TrueType
#     and the internal-font lookup so the font .o files become orphan and
#     can be dropped via POVRAY_DEAD_OBJS in the top-level Makefile.
#   - External image reading for image_map / bump_map / material_map /
#     height_field "file.png": short-circuit at Parse_Image so the error
#     is clean and LTO can drop Read_Image / Image::Read.
#   - SceneData destructor: replace the always-empty TTFonts delete loop
#     with .clear(), so truetype.o doesn't get pulled back in by the
#     virtual destructor.
#
# Originally a multi-stage shell+python script (see git history).
# Migrated to a static .patch file applied via `git apply`.
#
# Regenerate the .patch after editing POV-Ray source: see
# patches/0001-emscripten-source-fixes.patch.sh for the workflow.

set -euo pipefail

POVRAY_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/0002-strip-truetype-and-image-parse.patch"

cd "$POVRAY_DIR"

if git apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
    echo ">> 0002 already applied"
    exit 0
fi

echo ">> applying $PATCH_FILE"
git apply "$PATCH_FILE"
echo ">> feature-strip patches applied"
