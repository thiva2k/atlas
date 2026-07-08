#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"

assert_eq "usage exit code constant" "$ATLAS_EXIT_USAGE" "2"
assert_eq "module exit code constant" "$ATLAS_EXIT_MODULE" "4"

# die exits with the given code (run in a subshell so it doesn't kill the test)
assert_status "die uses the provided code" 3 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; die 3 "boom"'

# die surfaces what / why / how
out="$(bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; die 1 "what-x" "why-y" "how-z"' 2>&1 || true)"
assert_contains "die prints what" "$out" "what-x"
assert_contains "die prints why"  "$out" "why-y"
assert_contains "die prints how"  "$out" "how-z"
