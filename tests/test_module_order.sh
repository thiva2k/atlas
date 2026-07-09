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

# a dependency cycle reaches the user through runner::run as exit 3 (Fix A)
assert_status "runner surfaces a dependency cycle as exit 3" 3 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"; export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"; source "$ATLAS_ROOT/internal/module.sh"; source "$ATLAS_ROOT/internal/runner.sh"; runner::run install core/cyc_a'

# an unmet (missing) dependency is a fatal dependency error, exit 3 (Fix B)
assert_status "runner surfaces an unmet dependency as exit 3" 3 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"; export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules_unmetdep"; source "$ATLAS_ROOT/internal/module.sh"; source "$ATLAS_ROOT/internal/runner.sh"; runner::run install core/needy'
