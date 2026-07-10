### Task 3: Git module — fragment + `check`/`install`/`verify` + identity

**Files:**
- Create: `modules/core/git/config/gitconfig` (the managed fragment; delete the old `gitconfig.template`)
- Modify: `modules/core/git/module.sh` (real metadata + `check`/`install`/`verify` + helpers)
- Delete: `modules/core/git/config/gitconfig.template`
- Test: `tests/test_module_git.sh` (new)

**Interfaces:**
- Consumes: `os::has_cmd`, `os::dnf_install` (Task 1), `env::get` (Task 2), `log::*`.
- Produces: a git module whose required hooks work per RFC §4.7. Module-local helpers (leading `_git_`) compute the fragment path and apply identity. Uses `ATLAS_CONFIG_HOME`/`XDG_CONFIG_HOME`/`HOME` for the fragment location and `git config --global` for `~/.gitconfig` (respecting `GIT_CONFIG_GLOBAL` in tests).

- [ ] **Step 1: Write the managed fragment `modules/core/git/config/gitconfig`**

```ini
# Managed by Atlas (core/git). Included from ~/.gitconfig via include.path.
# Edit your own ~/.gitconfig to override any of these — your settings win.
[init]
	defaultBranch = main
[pull]
	rebase = true
[push]
	default = simple
	autoSetupRemote = true
[fetch]
	prune = true
[rebase]
	autostash = true
[color]
	ui = auto
```

- [ ] **Step 2: Delete the old placeholder template**

Run: `cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && git rm modules/core/git/config/gitconfig.template`

- [ ] **Step 3: Write the failing test `tests/test_module_git.sh`**

```bash
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
assert_eq "git init.defaultBranch resolves to main" \
  "$(bash -c "$PRE"' module::install >/dev/null 2>&1; git config --global --get init.defaultBranch')" "main"

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
```

- [ ] **Step 4: Run it — confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL — the placeholder `module::check` returns 1 always, `install`/`verify` call `not_implemented`, so nearly every git assertion fails.

- [ ] **Step 5: Implement `modules/core/git/module.sh`**

Replace the whole file with:
```bash
#!/usr/bin/env bash
MODULE_NAME="git"
MODULE_DESCRIPTION="Distributed version control: installs git and applies Atlas's global defaults."
MODULE_DEPENDS=()

# Absolute path to this module's directory (for its config/ fragment source).
_GIT_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- module-local helpers ----------------------------------------------------

_git_fragment_dir() {
  printf '%s\n' "${ATLAS_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/atlas}/git"
}
_git_fragment() { printf '%s\n' "$(_git_fragment_dir)/gitconfig"; }

# True if our fragment path is already an include.path in ~/.gitconfig.
_git_include_present() {
  git config --global --get-all include.path 2>/dev/null \
    | grep -qxF "$(_git_fragment)"
}

# Set user.name / user.email from env/atlas.env, only if currently unset.
# Never fails the install; always returns 0.
_git_apply_identity() {
  local name email
  name="$(env::get ATLAS_GIT_USER_NAME || true)"
  email="$(env::get ATLAS_GIT_USER_EMAIL || true)"
  if [ -z "$name" ] && [ -z "$email" ]; then
    log::warn "git identity not set — export ATLAS_GIT_USER_NAME/EMAIL or add them to ~/.config/atlas/atlas.env"
    return 0
  fi
  if [ -n "$name" ]; then
    if [ -n "$(git config --global --get user.name 2>/dev/null)" ]; then
      log::info "user.name already set — leaving it"
    else
      git config --global user.name "$name" && log::info "set user.name"
    fi
  fi
  if [ -n "$email" ]; then
    if [ -n "$(git config --global --get user.email 2>/dev/null)" ]; then
      log::info "user.email already set — leaving it"
    else
      git config --global user.email "$email" && log::info "set user.email"
    fi
  fi
  return 0
}

# --- required hooks ----------------------------------------------------------

module::check() {
  os::has_cmd git || return 1
  [ -r "$(_git_fragment)" ] || return 1
  _git_include_present || return 1
  return 0
}

module::install() {
  # 1. package
  if os::has_cmd git; then
    log::info "git already installed"
  else
    os::dnf_install git || { log::error "failed to install git"; return 1; }
  fi

  # 2. write the Atlas-owned fragment (Atlas owns it -> overwrite is idempotent)
  local frag_dir frag
  frag_dir="$(_git_fragment_dir)"; frag="$(_git_fragment)"
  mkdir -p "$frag_dir" || { log::error "cannot create $frag_dir"; return 1; }
  cp -f "$_GIT_MODULE_DIR/config/gitconfig" "$frag" || { log::error "cannot write $frag"; return 1; }
  log::info "wrote managed git config: $frag"

  # 3. ensure exactly one include.path line
  if _git_include_present; then
    log::info "include.path already present"
  else
    git config --global --add include.path "$frag" || { log::error "cannot add include.path"; return 1; }
    log::info "added include.path -> $frag"
  fi

  # 4. identity (optional, non-blocking, set-if-unset)
  _git_apply_identity
  return 0
}

module::verify() {
  os::has_cmd git || { log::error "git not installed"; return 1; }
  git --version >/dev/null 2>&1 || { log::error "git --version failed"; return 1; }
  [ -r "$(_git_fragment)" ] || { log::error "managed fragment missing"; return 1; }
  _git_include_present || { log::error "include.path not wired into ~/.gitconfig"; return 1; }
  [ "$(git config --global --get init.defaultBranch 2>/dev/null)" = "main" ] \
    || { log::error "managed config not effective (init.defaultBranch != main)"; return 1; }
  return 0
}
```

- [ ] **Step 6: Run tests — confirm pass**

Run: `bash tests/run.sh`
Expected: `test_module_git.sh` all `ok`; the existing `test_modules.sh` still passes (git still defines the 3 required hooks + README + metadata). Suite = 59 + 11 = **70 passed, 0 failed**.

- [ ] **Step 7: Commit**

```bash
git add modules/core/git/module.sh modules/core/git/config/gitconfig tests/test_module_git.sh
git -c commit.gpgsign=false commit -m "feat(git): implement check/install/verify with owned config fragment + identity

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

