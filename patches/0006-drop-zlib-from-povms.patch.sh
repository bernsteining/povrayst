#!/usr/bin/env bash
# Guard POVMS's zlib dependency behind POVRAY_WASM so the tree builds without
# zlib (dropped in 52602d7; the plugin emits raw RGBA and never needs it).
# povmscpp.cpp #include's <zlib.h> unconditionally and calls uncompress() in the
# gzip-decode branch — but the matching compress path is already
# #ifdef POVMS_COMPRESSION_ENABLED (undefined here), so POV-Ray never produces a
# gzip stream and the decode branch is unreachable at runtime. We wrap both
# under #ifndef POVRAY_WASM.
#
# We guard on POVRAY_WASM (a -D on the compile line) rather than LIBZ_MISSING
# (the autoconf macro backend/povray.cpp uses) because the <zlib.h> include sits
# at the top of the file, above the #include "povmscpp.h" that first pulls in
# config.h — so LIBZ_MISSING isn't defined yet at that point and the guard would
# not fire. POVRAY_WASM is visible from the first line.
#
# Applied after 0001, whose throw-stripping produced the (void)0 lines this
# patch's context matches.

set -euo pipefail

POVRAY_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/0006-drop-zlib-from-povms.patch"

cd "$POVRAY_DIR"

if git apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
    echo ">> 0006 already applied"
    exit 0
fi

git apply "$PATCH_FILE"
echo ">> zlib dropped from POVMS"
