#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"
source "$ATLAS_ROOT/internal/module.sh"

assert_eq "beta declares its dep" "$(module::deps_of apps/beta)" "core/alpha"

# resolving beta pulls in alpha first
order="$(module::resolve_order apps/beta | tr '\n' ' ')"
assert_eq "dependency comes before dependent" "$order" "core/alpha apps/beta "

# a cycle is a fatal dependency error (exit 3)
assert_status "cycle detected as exit 3" 3 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"; source "$ATLAS_ROOT/internal/module.sh"; module::resolve_order core/cyc_a'
