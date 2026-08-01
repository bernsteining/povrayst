#!/usr/bin/env bash
# Build POV-Ray's C/C++ dependencies as WASM static libs into $PREFIX.
#
# Produces:
#   $PREFIX/lib/libz.a
#   $PREFIX/lib/libpng.a    (+ libpng16.a symlink)
#   $PREFIX/lib/libboost_{system,thread,date_time,chrono}.a  (no filesystem)
#   $PREFIX/include/...     (headers for all of the above)
#
# Re-running is cheap: each component is skipped if its library is
# already present under $PREFIX/lib.

set -euo pipefail

PREFIX="${1:?usage: build-deps.sh <prefix>}"
SCRATCH="$(dirname "$(readlink -f "$0")")/../build/deps"
mkdir -p "$PREFIX/lib" "$PREFIX/include" "$SCRATCH"

ZLIB_VERSION="1.3.2"
LIBPNG_VERSION="1.6.43"
BOOST_VERSION="1.87.0"
BOOST_US="1_87_0"

JOBS="$(nproc)"

# Shared optimization flags. Kept in sync with ../Makefile so the deps
# and the final plugin are ABI/codegen compatible.
#   -O3              aggressive optimization (deps are pure number-crunching
#                    and never user-facing, so favor speed over size)
#   -flto            link-time optimization; em++ honors LTO across .a files
#   -msimd128        WebAssembly SIMD128 (Typst's wasmi supports this)
#   -msse*           enables Emscripten's SSE-to-wasm-SIMD header shims
#                    (libpng and zlib both have hand-written SSE paths that
#                    get auto-lowered to wasm SIMD through these)
#   -fno-exceptions  deps don't throw; keeps libs slim and avoids the
#                    wasi-stub exception trap table in the final wasm
OPT_FLAGS="-O3 -flto -DNDEBUG"
SIMD_FLAGS="-msimd128 -msse -msse2 -msse3 -mssse3 -msse4.1 -msse4.2"
# Same -ffile-prefix-map as the top-level Makefile so docker / native
# builds emit identical bytes (no host paths or username leak into the
# wasm name section / debug strings).
PROJECT_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PREFIX_MAP="-ffile-prefix-map=$PROJECT_ROOT=povrayst"
COMMON_CFLAGS="$OPT_FLAGS $SIMD_FLAGS $PREFIX_MAP -fno-exceptions"
COMMON_CXXFLAGS="$COMMON_CFLAGS -fno-rtti"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }

# ---- zlib ----------------------------------------------------------------

if false; then # zlib dropped: the plugin emits raw RGBA (no PNG), so nothing uses zlib
    log "building zlib $ZLIB_VERSION (autotools — cmake path can't build SHARED under emscripten)"
    cd "$SCRATCH"
    [[ -d "zlib-$ZLIB_VERSION" ]] || curl -fsSL \
        "https://github.com/madler/zlib/releases/download/v$ZLIB_VERSION/zlib-$ZLIB_VERSION.tar.gz" \
        | tar xz
    cd "zlib-$ZLIB_VERSION"
    # zlib's hand-rolled configure respects CC/AR/RANLIB/CFLAGS from emconfigure.
    CFLAGS="$COMMON_CFLAGS" \
    emconfigure ./configure --static --prefix="$PREFIX"
    emmake make -j"$JOBS" CFLAGS="$COMMON_CFLAGS" libz.a
    # `make install` tries to build and install the shared lib too; install
    # only the static artifacts by hand.
    cp libz.a "$PREFIX/lib/"
    cp zlib.h zconf.h "$PREFIX/include/"
    make clean >/dev/null 2>&1 || true
else
    log "zlib already built, skipping"
fi

# ---- libpng --------------------------------------------------------------

if false; then # libpng dropped: the plugin emits raw RGBA, and image input is stripped
    log "building libpng $LIBPNG_VERSION"
    cd "$SCRATCH"
    [[ -d "libpng-$LIBPNG_VERSION" ]] || curl -fsSL \
        "https://download.sourceforge.net/libpng/libpng-$LIBPNG_VERSION.tar.gz" \
        | tar xz
    cd "libpng-$LIBPNG_VERSION"
    rm -rf build && mkdir build && cd build
    # Pass SIMD + LTO + O3 flags to libpng's build. libpng has SSE intrinsics
    # for filter routines (png_read_filter_row_*) — with -msseN flags these
    # are auto-translated to wasm SIMD by Emscripten's intrinsic shims.
    # CMAKE_INTERPROCEDURAL_OPTIMIZATION enables full LTO across the
    # static library.
    emcmake cmake -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_C_FLAGS="$COMMON_CFLAGS" \
        -DCMAKE_CXX_FLAGS="$COMMON_CXXFLAGS" \
        -DCMAKE_C_FLAGS_RELEASE="$COMMON_CFLAGS" \
        -DCMAKE_CXX_FLAGS_RELEASE="$COMMON_CXXFLAGS" \
        -DCMAKE_INTERPROCEDURAL_OPTIMIZATION=ON \
        -DZLIB_INCLUDE_DIR="$PREFIX/include" \
        -DZLIB_LIBRARY="$PREFIX/lib/libz.a" \
        -DPNG_SHARED=OFF -DPNG_STATIC=ON \
        -DPNG_TESTS=OFF -DPNG_EXECUTABLES=OFF \
        -DPNG_INTEL_SSE=on \
        ..
    make -j"$JOBS" install
    # POV-Ray looks for -lpng; libpng installs as libpng16.a. Symlink.
    if [[ -f "$PREFIX/lib/libpng16.a" && ! -e "$PREFIX/lib/libpng.a" ]]; then
        ln -sf libpng16.a "$PREFIX/lib/libpng.a"
    fi
else
    log "libpng already built, skipping"
fi

# ---- Boost ---------------------------------------------------------------

if [[ ! -f "$PREFIX/lib/libboost_system.a" ]]; then
    log "building Boost $BOOST_VERSION (system, thread, date_time, chrono — no filesystem)"
    cd "$SCRATCH"
    if [[ ! -d "boost_$BOOST_US" ]]; then
        curl -fsSL \
            "https://archives.boost.io/release/$BOOST_VERSION/source/boost_$BOOST_US.tar.gz" \
            | tar xz
    fi
    cd "boost_$BOOST_US"

    # Note: no filesystem — POV-Ray doesn't use boost::filesystem, and it
    # can't compile with -fno-exceptions (it uses throw internally).
    ./bootstrap.sh --prefix="$PREFIX" \
        --with-libraries=system,thread,date_time,chrono >/dev/null

    # Point Boost.Build at em++. The emsdk image exposes emcc/em++ on
    # PATH; Boost.Build just needs to know the command name.
    cat > tools/build/src/user-config.jam <<'EOF'
using clang : emscripten : em++ ;
EOF

    # Emscripten doesn't implement threads the way Boost expects, but
    # POV-Ray links boost::thread unconditionally. Build threading=single
    # so the library is usable as a header-compat shim; the threading
    # patch in ../patches/ replaces the runtime behavior.
    #
    # --with-<lib> scopes b2 to just the libraries POV-Ray needs (bootstrap's
    # --with-libraries alone doesn't constrain b2's build graph). We also
    # wrap with `|| true` because the 1.87 tree has a handful of platform-
    # specific targets (boost::log::syslog_backend, boost::process::ext/*,
    # boost::type_erasure::dynamic_binding, boost::container::pmr::
    # synchronized_pool_resource) that can't compile against wasi-libc —
    # none of them are linked by POV-Ray.
    # b2 takes cxxflags / cflags / linkflags on its command line. Pass the
    # same SIMD + LTO + O3 set we use everywhere else. `visibility=hidden`
    # lets LTO strip more aggressively.
    ./b2 -j"$JOBS" \
        toolset=clang-emscripten \
        link=static \
        threading=single \
        runtime-link=static \
        variant=release \
        visibility=hidden \
        optimization=speed \
        cflags="$COMMON_CFLAGS" \
        cxxflags="$COMMON_CXXFLAGS" \
        linkflags="-flto" \
        --with-system --with-thread --with-date_time \
        --with-chrono \
        --prefix="$PREFIX" \
        install || true

    # Verify the libraries we actually depend on made it into $PREFIX.
    for lib in system thread date_time chrono; do
        if [[ ! -f "$PREFIX/lib/libboost_$lib.a" ]]; then
            echo "error: libboost_$lib.a missing after install" >&2
            exit 1
        fi
    done
else
    log "boost already built, skipping"
fi

# ---- Nuke the real boost/thread headers ---------------------------------
#
# POV-Ray's autotools build inserts `-I$PREFIX/include` BEFORE our
# CXXFLAGS additions, so our stub `-I` at the back of the command line
# never wins for `#include <boost/thread.hpp>`. Rather than fight the
# include-order battle in every generated Makefile, we just remove
# the real boost/thread headers entirely — the stub tree at
# include/boost-thread-stub/ is the only viable source now.
#
# The static libboost_thread.a we still link against is effectively
# inert: no callsite in POV-Ray reaches it because the stub's
# boost::thread::join() / boost::mutex::lock() etc. are all inline
# no-ops.
log "removing real boost/thread headers (stubs take over)"
rm -rf "$PREFIX/include/boost/thread.hpp" \
       "$PREFIX/include/boost/thread" \
       "$PREFIX/include/boost/atomic.hpp" \
       "$PREFIX/include/boost/atomic"

log "deps ready in $PREFIX"
