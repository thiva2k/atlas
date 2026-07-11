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

# a module whose install hook fails makes runner::run return ATLAS_EXIT_MODULE (4)
assert_status "failing module install returns exit 4" 4 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"; export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules_failing"; source "$ATLAS_ROOT/internal/module.sh"; source "$ATLAS_ROOT/internal/runner.sh"; runner::run install core/fail'

# status reports installed/not-installed and NEVER fails on a not-installed module
assert_status "status exits 0 on not-installed modules" 0 \
  runner::run status core/alpha apps/beta
out="$(runner::run status core/alpha apps/beta 2>&1 || true)"
assert_contains "status reports 'not installed'" "$out" "not installed"

# Real implemented modules: fresh pre-install state is valid, so verify should
# not fail just because install has not created Atlas-managed state yet.
assert_status "runner verify succeeds on real modules before install" 0 \
  bash -c '
    set -uo pipefail
    HOME="$(mktemp -d)"; export HOME
    ATLAS_CONFIG_HOME="$HOME/.config/atlas"; export ATLAS_CONFIG_HOME
    ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
    GH_CONFIG_DIR="$HOME/.config/gh"; export GH_CONFIG_DIR
    GIT_CONFIG_GLOBAL="$HOME/.gitconfig"; export GIT_CONFIG_GLOBAL
    GIT_CONFIG_SYSTEM=/dev/null; export GIT_CONFIG_SYSTEM
    ATLAS_MODULES_DIR="$ATLAS_ROOT/modules"; export ATLAS_MODULES_DIR
    source "$ATLAS_ROOT/internal/log.sh"
    source "$ATLAS_ROOT/internal/error.sh"
    source "$ATLAS_ROOT/internal/env.sh"
    source "$ATLAS_ROOT/internal/os.sh"
    source "$ATLAS_ROOT/internal/module.sh"
    source "$ATLAS_ROOT/internal/runner.sh"
    os::has_cmd() {
      case "$1" in
        gh) return 1 ;;
        *) command -v "$1" >/dev/null 2>&1 ;;
      esac
    }
    runner::run verify core/git development/github-cli
  '
