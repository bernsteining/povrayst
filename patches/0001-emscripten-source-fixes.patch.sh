#!/usr/bin/env bash
# Apply the captured emscripten source fixes as a single unified diff.
#
# Originally a multi-stage shell+python+sed script (see git history).
# Migrated to a static .patch file applied via `git apply` so the diff
# is reviewable in any tool.
#
# Regenerate the .patch after editing POV-Ray source:
#   cd povray-src && git checkout . && git clean -fd
#   bash <previous-version-of-this-script> povray-src   # or hand-edit
#   cd povray-src && git diff > ../patches/0001-emscripten-source-fixes.patch
#
# What this patch does (high-level — see the diff for specifics):
#   - unix/povconfig/syspovconfig.h: add __EMSCRIPTEN__ branch
#   - source/base/configbase.h: char_traits<unsigned short> specialization
#   - source/core/render/trace.cpp: auto_ptr -> unique_ptr
#   - vfe/vfesession.{h,cpp}: split WorkerThread into Init/RunOnce/Finish
#   - source/backend/povray.{h,cpp}: split MainThreadFunction; expose
#     PumpMainThread + MainThreadInit + MainThreadShutdown
#   - source/backend/control/scene.cpp + source/backend/scene/view.cpp:
#     break ParserControlThread / RenderControlThread infinite loops;
#     drive task queues synchronously
#   - source/parser/parser_tokenizer.cpp: in-memory scene input
#   - vfe/vfe.cpp: OpenLocalFile sentinel routing for PNG output capture
#   - source/base/image/image.cpp: PNG-only Read/Write under POVRAY_WASM
#   - throw / try / catch -> (void)0 across 74+ files (no EH runtime)

set -euo pipefail

POVRAY_DIR="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/0001-emscripten-source-fixes.patch"

cd "$POVRAY_DIR"

# Idempotency: if the patch can be reverse-applied, it's already applied.
if git apply --reverse --check "$PATCH_FILE" 2>/dev/null; then
    echo ">> 0001 already applied"
    exit 0
fi

echo ">> applying $PATCH_FILE"
git apply "$PATCH_FILE"
echo ">> emscripten source fixes applied"
