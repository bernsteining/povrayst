#!/usr/bin/env bash
# Install build dependencies for the POV-Ray Typst plugin on a fresh
# Void Linux host (tower). Idempotent: each step is skipped if already
# satisfied. Run as the build user, not as root — `sudo` is used only
# for the distro package step.
#
# Usage:  ./scripts/setup-tower.sh
#
# Installs:
#   xbps: cmake python3 gcc make patch (binaryen is NOT in xbps-src)
#   ~/.local/bin/wasm-opt   (binaryen prebuilt, extracted from GitHub release)
#   ~/.cargo/bin/{cargo,wasi-stub}
#   ~/.local/share/emsdk    (emscripten)
#
# After completion, opens a new shell: `emcc`, `wasm-opt`, `wasi-stub`
# are all on PATH via ~/.bashrc.

set -euo pipefail

# This script MUST run as the regular build user, not root. It uses
# `sudo` internally only for the xbps-install step; everything else
# installs into $HOME (rustup, cargo, emsdk, binaryen prebuilt).
# Running the whole script under sudo would drop all of that into
# /root/.local/... where the build user can't reach it.
if [[ $EUID -eq 0 ]]; then
    echo "error: do not run this script as root / with sudo." >&2
    echo "run it as your regular user; it will call sudo itself where needed." >&2
    exit 1
fi

BINARYEN_VERSION="${BINARYEN_VERSION:-128}"
LOCAL_BIN="$HOME/.local/bin"
LOCAL_LIB="$HOME/.local/lib"
EMSDK_DIR="$HOME/.local/share/emsdk"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }

mkdir -p "$LOCAL_BIN" "$LOCAL_LIB"

# ---------- 1. Distro packages (xbps) ------------------------------------
# binaryen is not in the xbps repos; we install it below from upstream.

log "installing distro packages via xbps"
sudo xbps-install -Sy cmake python3 gcc make patch autoconf automake libtool \
                     pkg-config git curl xz

# ---------- 2. Binaryen (wasm-opt) — prebuilt x86_64 binary --------------

if command -v wasm-opt >/dev/null 2>&1; then
    log "wasm-opt already available: $(command -v wasm-opt)"
else
    log "installing binaryen $BINARYEN_VERSION into $LOCAL_BIN"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    url="https://github.com/WebAssembly/binaryen/releases/download/version_${BINARYEN_VERSION}/binaryen-version_${BINARYEN_VERSION}-x86_64-linux.tar.gz"
    curl -fsSL "$url" | tar xz -C "$tmp"
    src="$tmp/binaryen-version_${BINARYEN_VERSION}"
    # Install both the binaries and the shared libs (wasm-opt links libbinaryen.so).
    cp -f  "$src/bin/"*       "$LOCAL_BIN/"
    cp -rf "$src/lib/"*       "$LOCAL_LIB/"
    # Expose the lib dir to the dynamic loader for this user.
    if ! grep -qs "$LOCAL_LIB" "$HOME/.config/ld-local" 2>/dev/null; then
        mkdir -p "$HOME/.config"
        echo "$LOCAL_LIB" > "$HOME/.config/ld-local"
    fi
    trap - EXIT
    rm -rf "$tmp"
fi

# ---------- 3. Rust + wasi-stub ------------------------------------------

if [[ ! -x "$HOME/.cargo/bin/cargo" ]]; then
    log "installing rustup (minimal profile, stable toolchain)"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --profile minimal --default-toolchain stable
else
    log "rust already installed: $("$HOME/.cargo/bin/cargo" --version)"
fi

# shellcheck disable=SC1091
source "$HOME/.cargo/env"

if ! command -v wasi-stub >/dev/null 2>&1; then
    log "installing wasi-stub"
    cargo install wasi-stub
else
    log "wasi-stub already installed: $(command -v wasi-stub)"
fi

# ---------- 4. Emscripten (emsdk) ----------------------------------------

if [[ ! -d "$EMSDK_DIR/.git" ]]; then
    log "cloning emsdk into $EMSDK_DIR"
    mkdir -p "$(dirname "$EMSDK_DIR")"
    git clone https://github.com/emscripten-core/emsdk "$EMSDK_DIR"
fi

log "installing/activating latest emscripten (this downloads ~300MB of LLVM)"
(
    cd "$EMSDK_DIR"
    ./emsdk install latest
    ./emsdk activate latest
)

# ---------- 5. Shell integration (~/.bashrc) -----------------------------

MARKER="# >>> povray-typst-plugin setup >>>"
if ! grep -qsF "$MARKER" "$HOME/.bashrc"; then
    log "appending PATH + emsdk sourcing to ~/.bashrc"
    cat >> "$HOME/.bashrc" <<EOF

$MARKER
export PATH="\$HOME/.local/bin:\$HOME/.cargo/bin:\$PATH"
export LD_LIBRARY_PATH="\$HOME/.local/lib:\${LD_LIBRARY_PATH:-}"
if [ -f "$EMSDK_DIR/emsdk_env.sh" ]; then
    # shellcheck disable=SC1091
    source "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1
fi
# <<< povray-typst-plugin setup <<<
EOF
else
    log "~/.bashrc already contains setup block, skipping"
fi

# ---------- 6. Verify ----------------------------------------------------

log "verification"
# Re-source env in this shell so the messages below reflect the real state.
export PATH="$LOCAL_BIN:$HOME/.cargo/bin:$PATH"
export LD_LIBRARY_PATH="$LOCAL_LIB:${LD_LIBRARY_PATH:-}"
# shellcheck disable=SC1091
source "$EMSDK_DIR/emsdk_env.sh" >/dev/null 2>&1 || true

for tool in emcc em++ emconfigure emmake wasm-opt wasi-stub cargo cmake git; do
    if path="$(command -v "$tool" 2>/dev/null)"; then
        printf '  \033[1;32m✓\033[0m %-14s %s\n' "$tool" "$path"
    else
        printf '  \033[1;31m✗\033[0m %-14s MISSING\n' "$tool"
    fi
done

log "done. Open a new shell (or 'source ~/.bashrc') before running 'make deps'."
