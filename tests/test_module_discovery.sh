#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"
source "$ATLAS_ROOT/internal/module.sh"

found="$(module::discover | tr '\n' ' ')"
assert_contains "discovers alpha" "$found" "core/alpha"
assert_contains "discovers beta"  "$found" "apps/beta"

assert_eq "path points at module.sh" \
  "$(module::path core/alpha)" "$ATLAS_MODULES_DIR/core/alpha/module.sh"

# has_hook works after sourcing a module
( source "$(module::path core/alpha)"
  assert_status "alpha defines install hook" 0 module::has_hook install
  assert_status "alpha lacks backup hook"    1 module::has_hook backup )

out="$(not_implemented "x" 2>&1 || true)"
assert_contains "not_implemented warns" "$out" "not yet implemented"
