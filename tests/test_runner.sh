#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"
export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"
source "$ATLAS_ROOT/internal/module.sh"
source "$ATLAS_ROOT/internal/runner.sh"

# install across the two happy fixtures runs end-to-end (exit 0)
assert_status "runner install succeeds on fixtures" 0 \
  runner::run install core/alpha apps/beta

# unknown verb is a usage error (run in a subshell so die's exit doesn't kill the suite)
assert_status "runner rejects unknown verb" 2 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/runner.sh"; runner::run frobnicate'

# placeholder install path emits the not-implemented notice
out="$(runner::run install core/alpha 2>&1 || true)"
assert_contains "install reaches placeholder hook" "$out" "not yet implemented"

# a module whose check passes is skipped
out="$(ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules_satisfied" \
       bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"; source "$ATLAS_ROOT/internal/module.sh"; source "$ATLAS_ROOT/internal/runner.sh"; runner::run install core/sat' 2>&1 || true)"
assert_contains "satisfied module is skipped" "$out" "already satisfied"
