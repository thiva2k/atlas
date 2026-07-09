#!/usr/bin/env bash
# The git module is exercised entirely inside sandboxes: each assertion runs in
# a child bash that points HOME / GIT_CONFIG_GLOBAL / ATLAS_CONFIG_HOME at a
# fresh temp dir and mocks os::dnf_install, so NO real ~/.gitconfig, ~/.config,
# or dnf is ever touched. GIT_CONFIG_SYSTEM=/dev/null isolates from system git
# config. Assertions live in the outer scope (via bash -c) so counters count.

# shared preamble: fresh sandbox + engine + mocked package install + the module
PRE='
set -uo pipefail
export HOME="$(mktemp -d)"; trap "rm -rf \"$HOME\"" EXIT
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export ATLAS_CONFIG_HOME="$HOME/.config/atlas"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/internal/env.sh"
os::dnf_install() { printf "DNF:%s\n" "$*"; return 0; }
source "$ATLAS_ROOT/modules/core/git/module.sh"
'

# check is unsatisfied before install, satisfied after
assert_status "git check unsatisfied before install" 1 bash -c "$PRE"' module::check'
assert_status "git check satisfied after install"    0 bash -c "$PRE"' module::install >/dev/null 2>&1; module::check'

# install creates the Atlas-owned fragment
assert_status "git install writes the managed fragment" 0 \
  bash -c "$PRE"' module::install >/dev/null 2>&1; [ -r "$ATLAS_CONFIG_HOME/git/gitconfig" ]'

# a managed value resolves through the include
# NOTE: `git config --global --get` alone does NOT expand include.path (real,
# documented git behavior: --includes defaults to off whenever an explicit
# scope selector like --global/--system/--local/--file is given, verified
# against git 2.43.0 here). `--includes` forces expansion for this read while
# keeping the read scoped to the global file, exactly matching this test's
# intent ("a managed value resolves through the include").
assert_eq "git init.defaultBranch resolves to main" \
  "$(bash -c "$PRE"' module::install >/dev/null 2>&1; git config --global --includes --get init.defaultBranch')" "main"

# install is idempotent: exactly one include.path line after running twice
assert_eq "git install is idempotent (one include line)" \
  "$(bash -c "$PRE"' module::install >/dev/null 2>&1; module::install >/dev/null 2>&1; git config --global --get-all include.path | wc -l | tr -d " "')" "1"

# identity is written from env/atlas.env
assert_eq "git identity set from env" \
  "$(bash -c "$PRE"' export ATLAS_GIT_USER_NAME="Ada Lovelace"; module::install >/dev/null 2>&1; git config --global --get user.name')" "Ada Lovelace"

# a pre-existing identity is never overwritten
assert_eq "git existing identity not clobbered" \
  "$(bash -c "$PRE"' git config --global user.name "Pre Existing"; export ATLAS_GIT_USER_NAME="Ada"; module::install >/dev/null 2>&1; git config --global --get user.name')" "Pre Existing"

# install succeeds even with no identity available (non-blocking)
assert_status "git install succeeds without identity" 0 bash -c "$PRE"' module::install'

# the package branch: when git is reported absent, os::dnf_install is invoked
assert_contains "git install calls dnf when git absent" \
  "$(bash -c "$PRE"' os::has_cmd() { [ "$1" = git ] && return 1; command -v "$1" >/dev/null 2>&1; }; module::install 2>&1')" \
  "DNF:git"

# verify: fails before install, passes after
assert_status "git verify fails before install" 1 bash -c "$PRE"' module::verify'
assert_status "git verify passes after install" 0 bash -c "$PRE"' module::install >/dev/null 2>&1; module::verify'
