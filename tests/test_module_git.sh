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

# --- include placement: Atlas provides defaults, the user always wins ---------
# RFC-0001 §4.4. git resolves config positionally (last value wins) and expands
# an include at the position of the directive, so the Atlas [include] block must
# be the FIRST section of the global config. `git config --add` appends, which
# would make Atlas silently override the user's own settings.

# a user's pre-existing value survives; an unclaimed managed key still applies
assert_eq "git user's pull.rebase survives install" \
  "$(bash -c "$PRE"'
    printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
    module::install >/dev/null 2>&1
    git config --global --includes --get pull.rebase')" "false"

assert_eq "git unclaimed managed key still applies" \
  "$(bash -c "$PRE"'
    printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
    module::install >/dev/null 2>&1
    git config --global --includes --get init.defaultBranch')" "main"

# the user's file is preserved byte-for-byte below the include block
assert_status "git install preserves user content byte-for-byte" 0 bash -c "$PRE"'
  printf "# my config\n[user]\n\tname = Zed\n\n[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
  cp "$GIT_CONFIG_GLOBAL" "$HOME/orig"
  module::install >/dev/null 2>&1
  tail -n +4 "$GIT_CONFIG_GLOBAL" > "$HOME/after"
  cmp -s "$HOME/orig" "$HOME/after"'

# idempotent against a pre-populated file: one include line, byte-stable
assert_eq "git install idempotent on pre-populated config (one include)" \
  "$(bash -c "$PRE"'
    printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
    module::install >/dev/null 2>&1; module::install >/dev/null 2>&1
    git config --global --get-all include.path | wc -l | tr -d " "')" "1"

assert_status "git second install leaves config byte-identical" 0 bash -c "$PRE"'
  printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
  module::install >/dev/null 2>&1
  cp "$GIT_CONFIG_GLOBAL" "$HOME/first"
  module::install >/dev/null 2>&1
  cmp -s "$HOME/first" "$GIT_CONFIG_GLOBAL"'

# a symlinked ~/.gitconfig (chezmoi/stow) stays a symlink; the target is rewritten
assert_status "git symlinked config preserved and target rewritten" 0 bash -c "$PRE"'
  mkdir -p "$HOME/dots"
  printf "[pull]\n\trebase = false\n" > "$HOME/dots/gitconfig"
  ln -s "$HOME/dots/gitconfig" "$GIT_CONFIG_GLOBAL"
  module::install >/dev/null 2>&1
  [ -L "$GIT_CONFIG_GLOBAL" ] || exit 1
  [ "$(git config --global --includes --get pull.rebase)" = false ] || exit 1
  head -n 1 "$HOME/dots/gitconfig" | grep -qxF "[include]"'

# file mode is preserved (users keep 600 on configs holding credentials)
assert_eq "git install preserves config file mode" \
  "$(bash -c "$PRE"'
    printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
    chmod 600 "$GIT_CONFIG_GLOBAL"
    module::install >/dev/null 2>&1
    stat -c %a "$GIT_CONFIG_GLOBAL"')" "600"

# a pre-existing lock means another writer: refuse, and do not touch the file
assert_status "git install refuses when config is locked" 4 bash -c "$PRE"'
  printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
  : > "$GIT_CONFIG_GLOBAL.lock"
  module::install'

# die() exits, so contain the hook in a subshell exactly as the runner does
assert_status "git locked config left unmodified" 0 bash -c "$PRE"'
  printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
  cp "$GIT_CONFIG_GLOBAL" "$HOME/orig"
  : > "$GIT_CONFIG_GLOBAL.lock"
  ( module::install ) >/dev/null 2>&1 || true
  cmp -s "$HOME/orig" "$GIT_CONFIG_GLOBAL"'

# migration: an include appended at the BOTTOM by an older Atlas is relocated
assert_eq "git migrates a bottom-appended include (user wins)" \
  "$(bash -c "$PRE"'
    frag="$ATLAS_CONFIG_HOME/git/gitconfig"
    mkdir -p "$(dirname "$frag")"; : > "$frag"
    printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
    git config --global --add include.path "$frag"
    module::install >/dev/null 2>&1
    git config --global --includes --get pull.rebase')" "false"

assert_eq "git migration leaves exactly one include line" \
  "$(bash -c "$PRE"'
    frag="$ATLAS_CONFIG_HOME/git/gitconfig"
    mkdir -p "$(dirname "$frag")"; : > "$frag"
    printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
    git config --global --add include.path "$frag"
    module::install >/dev/null 2>&1
    git config --global --get-all include.path | wc -l | tr -d " "')" "1"

assert_eq "git migration puts the include block at the very top" \
  "$(bash -c "$PRE"'
    frag="$ATLAS_CONFIG_HOME/git/gitconfig"
    mkdir -p "$(dirname "$frag")"; : > "$frag"
    printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
    git config --global --add include.path "$frag"
    module::install >/dev/null 2>&1
    head -n 1 "$GIT_CONFIG_GLOBAL"')" "[include]"

# health is "the fragment resolves", not "Atlas'"'"'s value wins": a user who
# deliberately overrides a managed key must not be told the module is broken
assert_status "git verify passes when user overrides a managed key" 0 bash -c "$PRE"'
  printf "[init]\n\tdefaultBranch = master\n" > "$GIT_CONFIG_GLOBAL"
  module::install >/dev/null 2>&1
  [ "$(git config --global --includes --get init.defaultBranch)" = master ] || exit 1
  module::verify'

# --- refuse to proceed rather than damage a config we cannot safely rewrite ---
# Each asserts BOTH the exit code and that the file was left untouched. die()
# exits, so the hook is contained in a subshell exactly as internal/runner.sh does.

assert_status "git install refuses an unparseable config" 4 bash -c "$PRE"'
  printf "[pull\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
  module::install'

assert_status "git unparseable config left unmodified" 0 bash -c "$PRE"'
  printf "[pull\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
  cp "$GIT_CONFIG_GLOBAL" "$HOME/orig"
  ( module::install ) >/dev/null 2>&1 || true
  cmp -s "$HOME/orig" "$GIT_CONFIG_GLOBAL"'

assert_status "git install refuses a dangling symlink config" 4 bash -c "$PRE"'
  ln -s "$HOME/nowhere/gitconfig" "$GIT_CONFIG_GLOBAL"
  module::install'

assert_status "git install refuses a non-regular-file config" 4 bash -c "$PRE"'
  mkdir -p "$GIT_CONFIG_GLOBAL"
  module::install'

assert_status "git install refuses an unwritable config" 4 bash -c "$PRE"'
  printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
  chmod 444 "$GIT_CONFIG_GLOBAL"
  module::install'
