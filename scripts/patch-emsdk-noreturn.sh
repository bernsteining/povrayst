#!/bin/bash
# Patch emscripten's system headers + sources to remove [[noreturn]] /
# _LIBCXXABI_NORETURN from throw helpers and exception handlers.
#
# Required because LTO + __cxa_throw(noreturn) causes LLVM to DCE
# ALL code after any potentially-throwing C++ call in POV-Ray's VFE.
#
# Run this ONCE after emsdk install or update. The script:
# 1. Patches SOURCE headers (for libc++ rebuild)
# 2. Patches SOURCE files (memory_resource.cpp, cxa_handlers.cpp)
# 3. Clears emscripten cache
# 4. Pre-builds all libc++ variants from patched sources
# 5. Patches CACHE headers (what user code sees)
#
# Idempotent: safe to re-run.

set -euo pipefail

EMSDK="${EMSDK:-$HOME/.local/share/emsdk}"
source "$EMSDK/emsdk_env.sh" >/dev/null 2>&1

SRC_LIBCXX="$EMSDK/upstream/emscripten/system/lib/libcxx/include"
SRC_LIBCXXABI="$EMSDK/upstream/emscripten/system/lib/libcxxabi/include"
SRC_LIBCXXABI_SRC="$EMSDK/upstream/emscripten/system/lib/libcxxabi/src"
SRC_LIBCXX_SRC="$EMSDK/upstream/emscripten/system/lib/libcxx/src"

echo "==> patching source headers..."
# cxxabi.h: _LIBCXXABI_NORETURN macro
sed -i 's/^#define _LIBCXXABI_NORETURN  __attribute__((noreturn))/#define _LIBCXXABI_NORETURN  \/* noreturn removed *\//' \
    "$SRC_LIBCXXABI/cxxabi.h" 2>/dev/null || true

# libc++ throw helpers: [[__noreturn__]]
for f in $(grep -rl '\[\[__noreturn__\]\].*__throw' "$SRC_LIBCXX/" 2>/dev/null); do
    sed -i 's/\[\[__noreturn__\]\]\(.*__throw\)/\/*noreturn*\/\1/g' "$f"
done

echo "==> patching source files..."
# memory_resource.cpp: add return nullptr after __throw_bad_alloc
sed -i 's/std::__throw_bad_alloc(); }/std::__throw_bad_alloc(); return nullptr; }/' \
    "$SRC_LIBCXX_SRC/memory_resource.cpp" 2>/dev/null || true

# cxa_handlers.cpp: remove inline noreturn, add __builtin_unreachable
sed -i 's/__attribute__((noreturn))/\/* noreturn *\//' \
    "$SRC_LIBCXXABI_SRC/cxa_handlers.cpp" 2>/dev/null || true
sed -i 's/__unexpected(get_unexpected());/__unexpected(get_unexpected()); __builtin_unreachable();/' \
    "$SRC_LIBCXXABI_SRC/cxa_handlers.cpp" 2>/dev/null || true
sed -i 's/__terminate(get_terminate());/__terminate(get_terminate()); __builtin_unreachable();/' \
    "$SRC_LIBCXXABI_SRC/cxa_handlers.cpp" 2>/dev/null || true

echo "==> clearing emscripten cache..."
emcc --clear-cache 2>&1 | tail -1

echo "==> building all libc++ variants..."
echo 'int main(){}' | emcc -x c - -o /tmp/_emsdk_test.js 2>&1 | grep error || true
echo '#include <string>
int main(){ std::string s("t"); }' | em++ -x c++ - -fexceptions -flto -o /tmp/_emsdk_test.js 2>&1 | grep error || true
rm -f /tmp/_emsdk_test.js /tmp/_emsdk_test.wasm

echo "==> patching cache headers..."
CACHE="$EMSDK/upstream/emscripten/cache/sysroot/include/c++/v1"
sed -i 's/^#define _LIBCXXABI_NORETURN  __attribute__((noreturn))/#define _LIBCXXABI_NORETURN  \/* noreturn removed *\//' \
    "$CACHE/cxxabi.h" 2>/dev/null || true
for f in $(grep -rl '\[\[__noreturn__\]\].*__throw' "$CACHE/" 2>/dev/null); do
    sed -i 's/\[\[__noreturn__\]\]\(.*__throw\)/\/*noreturn*\/\1/g' "$f"
done

echo "==> done."
