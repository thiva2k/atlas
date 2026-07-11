#!/usr/bin/env bash
# The git module is exercised entirely inside sandboxes: each assertion runs in
# a child bash that points HOME / GIT_CONFIG_GLOBAL / ATLAS_CONFIG_HOME at a
# fresh temp dir and mocks os::dnf_install, so NO real ~/.gitconfig, ~/.config,
# or dnf is ever touched. GIT_CONFIG_SYSTEM=/dev/null isolates from system git
# config. Assertions live in the outer scope (via bash -c) so counters count.

# shared preamble: fresh sandbox + engine + mocked package install + the module.
# `set -euo pipefail` mirrors the flags internal/runner.sh gives a hook subshell —
# a hook that aborts on an unguarded non-zero under -e must fail here too.
PRE='
set -euo pipefail
export HOME="$(mktemp -d)"; trap "rm -rf \"$HOME\"" EXIT
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
export GIT_CONFIG_SYSTEM=/dev/null
export ATLAS_CONFIG_HOME="$HOME/.config/atlas"
export ATLAS_STATE_DIR="$HOME/.local/state/atlas"
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

# verify: a clean pre-install workstation is valid, but adopted state must be healthy
assert_status "git verify passes before install (not installed)" 0 bash -c "$PRE"' module::verify'
assert_status "git verify passes after install" 0 bash -c "$PRE"' module::install >/dev/null 2>&1; module::verify'

assert_status "git verify fails when Atlas marker exists but fragment is missing" 1 bash -c "$PRE"'
  mkdir -p "$(dirname "$(_git_install_marker)")"
  : > "$(_git_install_marker)"
  module::verify'

assert_status "git verify fails when fragment exists but include is missing" 1 bash -c "$PRE"'
  mkdir -p "$ATLAS_CONFIG_HOME/git"
  cp "$_GIT_MODULE_DIR/config/gitconfig" "$ATLAS_CONFIG_HOME/git/gitconfig"
  module::verify'

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

# an emptied fragment is broken even if the user happens to set the same key
assert_status "git verify fails on an emptied fragment" 1 bash -c "$PRE"'
  module::install >/dev/null 2>&1
  : > "$ATLAS_CONFIG_HOME/git/gitconfig"
  git config --global init.defaultBranch main
  module::verify'

# the inline `[include] path = …` form git accepts but never writes itself
assert_eq "git migrates an inline include without duplicating it" \
  "$(bash -c "$PRE"'
    frag="$ATLAS_CONFIG_HOME/git/gitconfig"
    mkdir -p "$(dirname "$frag")"; : > "$frag"
    printf "[include] path = %s\n[pull]\n\trebase = false\n" "$frag" > "$GIT_CONFIG_GLOBAL"
    module::install >/dev/null 2>&1
    git config --global --get-all include.path | wc -l | tr -d " "')" "1"

# a user's own unrelated include must survive migration untouched
assert_eq "git migration leaves a foreign include alone" \
  "$(bash -c "$PRE"'
    frag="$ATLAS_CONFIG_HOME/git/gitconfig"
    mkdir -p "$(dirname "$frag")"; : > "$frag"; : > "$HOME/theirs"
    printf "[include]\n\tpath = %s\n\tpath = %s\n" "$HOME/theirs" "$frag" > "$GIT_CONFIG_GLOBAL"
    module::install >/dev/null 2>&1
    git config --global --get-all include.path | grep -cxF "$HOME/theirs"')" "1"

# `[includeIf]` is a different section and must never be stripped
assert_eq "git migration never strips an includeIf section" \
  "$(bash -c "$PRE"'
    frag="$ATLAS_CONFIG_HOME/git/gitconfig"
    mkdir -p "$(dirname "$frag")"; : > "$frag"; : > "$HOME/work"
    printf "[includeIf \"gitdir:~/w/\"]\n\tpath = %s\n" "$HOME/work" > "$GIT_CONFIG_GLOBAL"
    module::install >/dev/null 2>&1
    grep -c "includeIf" "$GIT_CONFIG_GLOBAL"')" "1"

# migrating must not leave the old, now-empty [include] header behind
assert_eq "git migration leaves no orphan include header" \
  "$(bash -c "$PRE"'
    frag="$ATLAS_CONFIG_HOME/git/gitconfig"
    mkdir -p "$(dirname "$frag")"; : > "$frag"
    printf "[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
    git config --global --add include.path "$frag"
    module::install >/dev/null 2>&1
    grep -cxF "[include]" "$GIT_CONFIG_GLOBAL"')" "1"

# --- through the real runner --------------------------------------------------
# Every assertion above calls the hooks directly. These drive the module the way
# `atlas` actually does: runner::run sources it into its own `set -euo pipefail`
# subshell and fans the verb out. Nothing else exercises that seam.
#
# `set +e; set -uo pipefail` mirrors the `atlas` entrypoint (note `set -uo pipefail`
# alone would NOT clear the `-e` PRE turned on).
# It matters: runner::run tallies failures via `out="$(_runner_run_module …)"`, so
# under a caller's `set -e` the shell would die on the first failing module and
# never reach the tally. Hooks still get `set -euo pipefail` from runner::run's
# own subshell.
RUN="$PRE"'
set +e; set -uo pipefail
source "$ATLAS_ROOT/internal/module.sh"
source "$ATLAS_ROOT/internal/runner.sh"
'
assert_status "git installs cleanly through runner::run" 0 bash -c "$RUN"' runner::run install core/git'
assert_status "git verifies through runner::run"         0 bash -c "$RUN"' runner::run install core/git >/dev/null 2>&1; runner::run verify core/git'
assert_status "git verifies cleanly through runner::run before install" 0 bash -c "$RUN"' runner::run verify core/git'
assert_status "git updates through runner::run"          0 bash -c "$RUN"' runner::run install core/git >/dev/null 2>&1; runner::run update core/git'

# a second install is skipped by the runner, not re-run
assert_contains "runner skips an already-satisfied git" \
  "$(bash -c "$RUN"' runner::run install core/git >/dev/null 2>&1; runner::run install core/git 2>&1')" \
  "already satisfied"

# a module failure surfaces as exit 4 through the runner, not a stack trace
assert_status "runner reports git install failure as exit 4" 4 bash -c "$RUN"'
  printf "[pull\n" > "$GIT_CONFIG_GLOBAL"
  runner::run install core/git'

# --- optional hooks: update / remove (RFC-0001 §4.7) --------------------------

# update re-applies the managed fragment (picks up changes to Atlas's defaults)
assert_status "git update restores a tampered fragment" 0 bash -c "$PRE"'
  module::install >/dev/null 2>&1
  : > "$ATLAS_CONFIG_HOME/git/gitconfig"
  module::update >/dev/null 2>&1
  module::verify'

# update never sets identity and never installs a package
assert_eq "git update does not touch identity" \
  "$(bash -c "$PRE"'
    module::install >/dev/null 2>&1
    export ATLAS_GIT_USER_NAME="Ada"
    module::update >/dev/null 2>&1
    git config --global --get user.name')" ""

# remove: the include goes, the fragment goes, the user's file survives intact
assert_status "git remove restores the config byte-for-byte" 0 bash -c "$PRE"'
  printf "# mine\n[user]\n\tname = Zed\n[pull]\n\trebase = false\n" > "$GIT_CONFIG_GLOBAL"
  cp "$GIT_CONFIG_GLOBAL" "$HOME/orig"
  module::install >/dev/null 2>&1
  module::remove  >/dev/null 2>&1
  cmp -s "$HOME/orig" "$GIT_CONFIG_GLOBAL"'

assert_status "git remove deletes the managed fragment" 0 bash -c "$PRE"'
  module::install >/dev/null 2>&1
  module::remove  >/dev/null 2>&1
  [ ! -e "$ATLAS_CONFIG_HOME/git/gitconfig" ]'

assert_status "git remove clears the installed-state marker" 0 bash -c "$PRE"'
  module::install >/dev/null 2>&1
  module::remove  >/dev/null 2>&1
  [ ! -e "$(_git_install_marker)" ]'

assert_status "git check is unsatisfied after remove" 1 bash -c "$PRE"'
  module::install >/dev/null 2>&1
  module::remove  >/dev/null 2>&1
  module::check'

# remove is safely re-runnable and never touches the user's identity
assert_status "git remove is idempotent" 0 bash -c "$PRE"'
  module::install >/dev/null 2>&1
  module::remove  >/dev/null 2>&1
  module::remove'

assert_eq "git remove leaves identity alone" \
  "$(bash -c "$PRE"'
    git config --global user.name "Zed"
    module::install >/dev/null 2>&1
    module::remove  >/dev/null 2>&1
    git config --global --get user.name')" "Zed"

# remove on a machine Atlas never touched is a clean no-op
assert_status "git remove is a no-op when nothing is installed" 0 bash -c "$PRE"' module::remove'

# install after remove restores everything (full lifecycle round-trip)
assert_status "git install -> remove -> install round-trips" 0 bash -c "$PRE"'
  module::install >/dev/null 2>&1
  module::remove  >/dev/null 2>&1
  module::install >/dev/null 2>&1
  module::verify'

# remove refuses a locked config rather than half-editing it
assert_status "git remove refuses when config is locked" 4 bash -c "$PRE"'
  module::install >/dev/null 2>&1
  : > "$GIT_CONFIG_GLOBAL.lock"
  module::remove'

# on a config git cannot read, remove must refuse -- not delete the fragment and
# leave a dangling include.path behind (a silent half-revert)
assert_status "git remove refuses an unparseable config" 4 bash -c "$PRE"'
  module::install >/dev/null 2>&1
  printf "[pull\n" > "$GIT_CONFIG_GLOBAL"
  module::remove'

assert_status "git remove keeps the fragment when it refuses" 0 bash -c "$PRE"'
  module::install >/dev/null 2>&1
  printf "[pull\n" > "$GIT_CONFIG_GLOBAL"
  ( module::remove ) >/dev/null 2>&1 || true
  [ -r "$ATLAS_CONFIG_HOME/git/gitconfig" ]'

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
