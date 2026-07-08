#!/usr/bin/env bash
set -uo pipefail
ATLAS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ATLAS_ROOT
# keep test state out of the real state dir
export ATLAS_STATE_DIR="$ATLAS_ROOT/.local/state/atlas"

source "$ATLAS_ROOT/tests/lib/assert.sh"

total_pass=0 total_fail=0
for t in "$ATLAS_ROOT"/tests/test_*.sh; do
  [ -e "$t" ] || continue
  printf '\n%s\n' "$(basename "$t")"
  ATLAS_TESTS_PASS=0 ATLAS_TESTS_FAIL=0
  # shellcheck source=/dev/null
  source "$t"
  total_pass=$((total_pass + ATLAS_TESTS_PASS))
  total_fail=$((total_fail + ATLAS_TESTS_FAIL))
done

printf '\n== %d passed, %d failed ==\n' "$total_pass" "$total_fail"
[ "$total_fail" -eq 0 ]
