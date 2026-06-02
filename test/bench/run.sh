#!/usr/bin/env bash
# Run each benchmark .typ through `typst compile` and report median wall time.
# Usage:
#   ./run.sh                       all benches, 3 samples each (median)
#   ./run.sh julia clebsch         subset, 3 samples each
#   ./run.sh -n 5                  5 samples per bench (slower, lower noise)
#   ./run.sh -n 1                  one sample (fast triage)
#
# Output is one "<bench>  <median_seconds>" line per row, suitable for diff.
#   ./run.sh > before.txt
#   ... apply refactor, rebuild ...
#   ./run.sh > after.txt
#   diff before.txt after.txt

set -u
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)

samples=3
if [ "${1-}" = "-n" ]; then samples="$2"; shift 2; fi

benches=(basic basic-q2 transparency orbit csg clebsch hopf julia knot gyroid)
if [ $# -gt 0 ]; then benches=("$@"); fi

run_once() {
  { time typst compile --root "$ROOT" "$1.typ" "/tmp/$1.pdf" > /dev/null 2>&1; } 2>&1 \
    | awk '/^real/ { split($2, a, "m"); split(a[2], b, "s"); printf "%.2f", a[1]*60 + b[1] }'
}

printf '%-14s  %8s' 'bench' 'median'
[ "$samples" -gt 1 ] && printf '  (%d samples)' "$samples"
echo
printf '%-14s  %8s\n' '-----' '------'

for b in "${benches[@]}"; do
  ts=()
  for ((i=0; i<samples; i++)); do
    ts+=("$(run_once "$b")")
  done
  median=$(printf '%s\n' "${ts[@]}" | sort -n | awk -v n="$samples" 'NR==int((n+1)/2)')
  printf '%-14s  %8s\n' "$b" "$median"
done
