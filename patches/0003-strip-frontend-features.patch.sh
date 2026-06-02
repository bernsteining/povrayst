#!/usr/bin/env bash
# Smaller strips that don't touch the vfe.cpp frontend loop:
#
#   - Drop boost::posix_time from source/base/image/metadata.cpp; emit
#     a zero timestamp instead. libboost_date_time is otherwise empty
#     for our build, but the inline template instantiation it would
#     pull in is several KB.
#
# Animation / benchmark .o orphaning is handled separately via
# POVRAY_DEAD_OBJS in the top-level Makefile (LTO already drops them
# from the link closure; the explicit list saves compile time).
#
# Migrated from inline sed to a static .patch file applied via `git apply`.
# Regenerate: see patches/0001-emscripten-source-fixes.patch.sh.

set -euo pipefail

POVRAY_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/0003-strip-frontend-features.patch"

cd "$POVRAY_DIR"

if git apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
    echo ">> 0003 already applied"
    exit 0
fi

echo ">> applying $PATCH_FILE"
git apply "$PATCH_FILE"
echo ">> frontend-strip patches applied"
