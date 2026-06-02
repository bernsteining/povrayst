# Reproducible build environment for the Povrayst plugin (POV-Ray 3.8 → WASM).
#
# Usage:
#   docker build -t povrayst-build .
#   docker run --rm -v "$PWD":/workspace povrayst-build make wasm
#
# The image carries only the toolchain (emsdk, binaryen, wasi-stub,
# autotools); mount your checkout at /workspace to build it. Output ends up
# in pkg/povray.wasm on the host.

FROM docker.io/library/alpine:3.20

ENV LANG=C.UTF-8

# Toolchain: build-base brings gcc/make/musl-dev; gcompat lets glibc
# binaries (emsdk's bundled clang + node, binaryen, wasi-stub) run on musl.
RUN apk add --no-cache \
        bash \
        build-base \
        autoconf \
        automake \
        libtool \
        pkgconf \
        python3 \
        git \
        curl \
        ca-certificates \
        xz \
        cmake \
        perl \
        gcompat \
        libstdc++ \
        nodejs

# Binaryen (wasm-opt) — upstream release; Alpine's apk wasm-opt (if any)
# wouldn't have --gufa.
ENV BINARYEN_VERSION=128
RUN curl -fsSL "https://github.com/WebAssembly/binaryen/releases/download/version_${BINARYEN_VERSION}/binaryen-version_${BINARYEN_VERSION}-x86_64-linux.tar.gz" \
    | tar -xz -C /opt \
    && ln -s "/opt/binaryen-version_${BINARYEN_VERSION}/bin/wasm-opt" /usr/local/bin/wasm-opt

# wasi-stub — prebuilt musl-linked binary from the typst-community release.
ENV WASI_STUB_VERSION=0.3.0
RUN curl -fsSL "https://github.com/typst-community/wasm-minimal-protocol/releases/download/wasi-stub-${WASI_STUB_VERSION}/wasi-stub-x86_64-unknown-linux-musl.tar" \
    | tar -x --strip-components=1 -C /usr/local/bin \
    && chmod +x /usr/local/bin/wasi-stub

# Emscripten SDK — pinned to match the host build environment.
ENV EMSDK_VERSION=5.0.5
ENV EMSDK=/opt/emsdk
RUN git clone --depth 1 --branch ${EMSDK_VERSION} \
        https://github.com/emscripten-core/emsdk.git ${EMSDK} \
    && ${EMSDK}/emsdk install ${EMSDK_VERSION} \
    && ${EMSDK}/emsdk activate ${EMSDK_VERSION} \
    && rm -f ${EMSDK}/node/*/bin/node \
    && ln -s /usr/bin/node ${EMSDK}/node/$(ls ${EMSDK}/node/)/bin/node \
    && rm -f ${EMSDK}/upstream/bin/wasm-opt \
    && ln -s /usr/local/bin/wasm-opt ${EMSDK}/upstream/bin/wasm-opt

# Makefile expects EMSDK_ENV to point at emsdk_env.sh.
ENV EMSDK_ENV=${EMSDK}/emsdk_env.sh

# Trust /workspace at the system-config level so non-root --user invocations
# (recommended, so output is host-owned) don't need a writable HOME for
# `git config --global --add safe.directory`.
RUN printf '[safe]\n\tdirectory = *\n' > /etc/gitconfig

# emsdk's bundled node is glibc-linked (fcntl64 missing on musl); we
# already symlinked /usr/bin/node into emsdk's tree above.

WORKDIR /workspace
CMD ["make", "wasm"]
