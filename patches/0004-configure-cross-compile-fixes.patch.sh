#!/usr/bin/env bash
# In-place fixes for povray-src/configure (the autotools-generated script,
# not configure.ac). A unified diff doesn't fly here because configure's
# exact byte content depends on the autoconf version that ran prebuild —
# context lines drift between distros. The patches below match autoconf's
# *message strings* instead, which are stable across versions.
#
# Applied AFTER unix/prebuild.sh has regenerated configure. Idempotent
# via a sentinel comment after the shebang.

set -euo pipefail

POVRAY_DIR="$1"
CONFIGURE="$POVRAY_DIR/configure"
SENTINEL="POVRAY_WASM_CROSS_COMPILE_FIXES"

if grep -q "$SENTINEL" "$CONFIGURE"; then
    echo ">> 0004 already applied"
    exit 0
fi

echo ">> patching $CONFIGURE for wasm cross-compile"

# Two regex replacements, both via perl (always installed alongside git):
#   1. ax_check_lib's cross-compile branch forgets to set ax_check_lib="ok",
#      so libpng / libz / boost version probes default to "unknown" and fail.
#   2. boost_thread usability loop's `# FIXME` cross-compile branch forgets
#      to set boost_thread_links=1, breaking the enclosing loop.
perl -i -0pe '
    # Insert sentinel after shebang.
    s/^(#![^\n]*\n)/$1# '"$SENTINEL"' applied\n/;

    # Fix ax_check_lib cross-compile.
    s{(\{ printf "%s\\n" "\$as_me:\$\{as_lineno-\$LINENO\}: result: cross-compiling, forced" >&5\nprintf "%s\\n" "cross-compiling, forced" >&6; \})}
     {$1\n              ax_check_lib="ok"\n              ax_check_lib_version="cross-compile"}g;

    # Fix boost_thread cross-compile loop.
    s{(\{ printf "%s\\n" "\$as_me:\$\{as_lineno-\$LINENO\}: result: cross-compiling" >&5\nprintf "%s\\n" "cross-compiling" >&6; \}  \# FIXME)}
     {$1\n    boost_thread_links=1}g;
' "$CONFIGURE"

echo ">> configure cross-compile fixes applied"
