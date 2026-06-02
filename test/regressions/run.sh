#!/usr/bin/env bash
# Regression runner: each .typ in this directory is a deliberately broken
# scene. typst compile MUST fail with a non-zero exit, MUST print the
# expected fragment from the test's "# expected:" header comment, and MUST
# NOT hang (we hard-cap each at 30 s).
#
# Usage:
#   ./run.sh                      run all
#   ./run.sh error_directive      run a subset
#
# Output: one PASS/FAIL line per test.

set -u
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)

tests=("$@")
if [ ${#tests[@]} -eq 0 ]; then
    tests=()
    for f in *.typ; do tests+=("${f%.typ}"); done
fi

pass=0; fail=0
for t in "${tests[@]}"; do
    expected=$(grep -m1 "// expect:" "$t.typ" 2>/dev/null | sed 's|^// expect:[ \t]*||')
    if [ -z "$expected" ]; then
        echo "FAIL $t — no '// expect:' header in test file"
        fail=$((fail+1))
        continue
    fi
    out=$(timeout 30 typst compile --root "$ROOT" "$t.typ" /tmp/_reg.pdf 2>&1)
    code=$?
    if [ "$code" -eq 0 ]; then
        echo "FAIL $t — typst compile succeeded but should have failed"
        fail=$((fail+1))
        continue
    fi
    if [ "$code" -eq 124 ]; then
        echo "FAIL $t — TIMED OUT (parser hang regression)"
        fail=$((fail+1))
        continue
    fi
    if echo "$out" | grep -qF "$expected"; then
        echo "PASS $t"
        pass=$((pass+1))
    else
        echo "FAIL $t — error did not contain expected fragment"
        echo "  expected: $expected"
        echo "  got: $(echo "$out" | head -1)"
        fail=$((fail+1))
    fi
done

rm -f /tmp/_reg.pdf
echo "---"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
