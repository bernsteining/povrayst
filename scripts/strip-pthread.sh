#!/usr/bin/env bash
# Strip -pthread / -lpthread from POV-Ray's config.status, then re-run
# it so every Makefile gets regenerated without those flags.
#
# Why this script and not a Makefile one-liner: config.status wraps long
# substitution strings using sh's `"foo"\n"bar"` concatenation, so plain
# `sed -i 's/-pthread//g'` misses cases where `-pthread` is split across
# lines. Python can do the unwrap-strip-rewrap reliably.
#
# Why strip at all: with our thread-stub headers on the include path,
# boost::thread no longer requires -pthread. Dropping -pthread here
# tells clang to NOT enable the WebAssembly atomics target feature;
# otherwise libc++ / libc++abi emit ~125 atomic.rmw.* ops (for
# shared_ptr and exception refcounts) that wasmi rejects at module load.

set -euo pipefail

POVRAY_DIR="$1"
CS="$POVRAY_DIR/config.status"

if [[ ! -f "$CS" ]]; then
    echo "error: $CS not found" >&2
    exit 1
fi

python3 - "$CS" <<'PY'
import re, sys
path = sys.argv[1]
with open(path) as f:
    s = f.read()

# Unwrap sh-string line continuations of the form: `"`\n`"`
# (a closing quote, newline, opening quote — meaning "the string just
# continues"). That way we can match `-pthread` even when autoconf
# wrapped it in the middle.
unwrapped = re.sub(r'"\s*\\\n\s*"', '', s)

# Strip the flags.
stripped = unwrapped.replace('-pthread', '').replace('-lpthread', '')

with open(path, 'w') as f:
    f.write(stripped)

# Quick sanity count.
before = len(re.findall(r'-pthread|-lpthread', s))
after  = len(re.findall(r'-pthread|-lpthread', stripped))
print(f"  removed {before - after} -pthread/-lpthread token(s)")
PY

# Regenerate every Makefile from the freshly-stripped config.status.
cd "$POVRAY_DIR"
./config.status >/dev/null

echo "  regenerated Makefiles from patched config.status"
