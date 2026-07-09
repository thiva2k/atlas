# Git Module Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement `modules/core/git` — the first real Atlas module and the reference implementation for all future modules — per RFC-0001.

**Architecture:** A real, idempotent `os::dnf_install` primitive; a shared `atlas.env` reader (`internal/env.sh`); and the git module itself, which installs git, applies an Atlas-owned config fragment via a single `include.path` line in `~/.gitconfig`, and sets commit identity non-destructively. All behavior is tested against a sandboxed `HOME`/`GIT_CONFIG_GLOBAL` with the package step mocked — no test ever mutates the real machine or needs root.

**Tech Stack:** Bash + coreutils + git. Pure-Bash test harness (no framework).

## Global Constraints

- **Spec:** `docs/rfcs/RFC-0001-git-module.md` (Accepted). This plan implements it; do not deviate from its decisions.
- **Runtime deps:** Bash + coreutils + Git + Fedora. No new dependencies.
- Every shell script starts with `#!/usr/bin/env bash`.
- Module hooks run under `set -euo pipefail` (the runner's subshell); the `atlas` entrypoint uses `set -uo pipefail`. Write hook code that is safe under `set -e` (guard every fallible command with `|| { …; return 1; }` or use it in an `if`/`||` condition).
- User output via `log::*` only. Machine values may use `printf`/`echo`.
- Exit codes come from `internal/error.sh` (`ATLAS_EXIT_*`); fatal paths use `die`.
- **Config strategy (RFC §4.4):** Atlas owns `${ATLAS_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/atlas}/git/gitconfig` and adds exactly one `include.path` line to `~/.gitconfig` (add only if absent). Never rewrite the user's `~/.gitconfig` otherwise.
- **Identity (RFC §4.5):** resolve `ATLAS_GIT_USER_NAME` / `ATLAS_GIT_USER_EMAIL` via env var → `~/.config/atlas/atlas.env`. Non-blocking (missing identity → warn, still succeed). Set a key **only if currently unset** (never clobber the user).
- **Managed defaults (RFC §4.3), verbatim:** `init.defaultBranch=main`, `pull.rebase=true`, `push.default=simple`, `push.autoSetupRemote=true`, `fetch.prune=true`, `rebase.autostash=true`, `color.ui=auto`.
- **Idempotency:** every hook is safe to run repeatedly (install twice → identical state, one include line).
- **Testing rule (RFC §6):** tests sandbox `HOME`, `GIT_CONFIG_GLOBAL="$HOME/.gitconfig"`, `GIT_CONFIG_SYSTEM=/dev/null`, and `ATLAS_CONFIG_HOME` under the sandbox; mock `os::dnf_install` (and, for the package branch, `os::has_cmd`). **No automated test may touch the real `$HOME` or run real `dnf`.** Assertions run in the OUTER test scope (via `bash -c` children that print/exit results) so suite counters are never lost in a subshell.
- **Commits:** conventional; body ends with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; commit with `git -c commit.gpgsign=false`.
- **Env (Windows/WSL/UNC dev host):** repo at `//wsl.localhost/Ubuntu/home/thiva/atlas`, branch `feat/git-module`. Bash tool = Git Bash (MINGW64), cwd resets — prefix commands with `cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && …`. Write/Edit/Read use absolute `\\wsl.localhost\Ubuntu\home\thiva\atlas\…`. Run tests with `bash tests/run.sh`. Do NOT push. CRLF warning harmless.

**Current suite baseline:** 51 passed, 0 failed.

---

### Task 1: Real `os::dnf_install` package primitive

**Files:**
- Modify: `internal/os.sh` (replace the `os::dnf_install` placeholder with a real implementation)
- Test: `tests/test_os_dnf.sh` (new)

**Interfaces:**
- Produces: `os::dnf_install <pkg>...` — installs packages via dnf, idempotent (dnf is a no-op if already present), uses `sudo` only when not root, logs intent, returns non-zero on failure. Requires `dnf` (dies exit 5 via `os::require_cmd` if absent). `os::flatpak_install` is left as-is for now.

- [ ] **Step 1: Write the failing test `tests/test_os_dnf.sh`**

```bash
#!/usr/bin/env bash
# os::dnf_install is tested by shadowing `dnf` and `sudo` with shell FUNCTIONS
# (functions take precedence over PATH, so no real package manager is touched —
# safe on Fedora and non-Fedora alike). Each case runs in a child bash so the
# stubs never leak into the suite shell.

# success: dnf install is invoked with the packages, returns 0
out="$(bash -c '
  source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"
  dnf()  { printf "dnf-called: %s\n" "$*"; return 0; }
  sudo() { "$@"; }
  os::dnf_install git curl
' 2>/dev/null)"; rc=$?
assert_eq       "dnf_install returns 0 on success"      "$rc" "0"
assert_contains "dnf_install runs dnf install for pkgs" "$out" "dnf-called: install -y git curl"

# failure: dnf exits non-zero -> os::dnf_install returns non-zero
assert_status "dnf_install propagates dnf failure" 1 bash -c '
  source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"
  dnf()  { return 1; }
  sudo() { "$@"; }
  os::dnf_install git
'

# no args is a harmless no-op (exit 0)
assert_status "dnf_install no-op on empty args" 0 bash -c '
  source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"
  os::dnf_install
'
```

- [ ] **Step 2: Run it — confirm it fails**

Run: `bash tests/run.sh`
Expected: `test_os_dnf.sh` fails — the placeholder `os::dnf_install` only logs "would dnf install", so `dnf-called:` never appears and the failure case returns 0 instead of 1.

- [ ] **Step 3: Replace the placeholder in `internal/os.sh`**

Find:
```bash
# --- placeholder installers (real logic lands with the modules that need them) ---
os::dnf_install()     { log::info "would dnf install: $*"; }
os::flatpak_install() { log::info "would flatpak install: $*"; }
```
Replace with:
```bash
# Install one or more packages via dnf. Idempotent (dnf is a no-op for
# already-installed packages). Uses sudo only when not already root.
os::dnf_install() {
  [ "$#" -gt 0 ] || return 0
  os::require_cmd dnf
  local sudo=""
  os::is_root || sudo="sudo"
  log::info "installing packages: $*"
  if ! $sudo dnf install -y "$@"; then
    log::error "dnf install failed: $*"
    return 1
  fi
}

# flatpak install placeholder (promoted when the first flatpak module lands).
os::flatpak_install() { log::info "would flatpak install: $*"; }
```

- [ ] **Step 4: Run tests — confirm pass**

Run: `bash tests/run.sh`
Expected: `test_os_dnf.sh` all `ok`; suite total = 51 + 3 = **54 passed, 0 failed**.

- [ ] **Step 5: Commit**

```bash
git add internal/os.sh tests/test_os_dnf.sh
git -c commit.gpgsign=false commit -m "feat(os): make os::dnf_install a real idempotent package primitive

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Shared `atlas.env` reader (`internal/env.sh`)

**Files:**
- Create: `internal/env.sh`
- Modify: `atlas` (source `internal/env.sh` alongside the other engine files)
- Test: `tests/test_env.sh` (new)

**Interfaces:**
- Produces: `env::get <NAME>` — echoes the user-supplied value of `NAME`, resolved from the environment variable `NAME` first, then a `NAME=value` line in `${ATLAS_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/atlas}/atlas.env` (one layer of surrounding quotes stripped; `#` comments and blank lines ignored; last matching line wins). Prints nothing and returns 1 when unset in both. This is the standard source of user-specific config for all modules.

- [ ] **Step 1: Write the failing test `tests/test_env.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/env.sh"

# sandbox a config home with an atlas.env
sandbox="$(mktemp -d)"
export ATLAS_CONFIG_HOME="$sandbox"
printf '# a comment\nATLAS_GIT_USER_NAME="Ada Lovelace"\nATLAS_GIT_USER_EMAIL=ada@example.com\n' > "$sandbox/atlas.env"

# value read from atlas.env (quotes stripped)
assert_eq "env::get reads a quoted value from atlas.env" \
  "$(unset ATLAS_GIT_USER_NAME; env::get ATLAS_GIT_USER_NAME)" "Ada Lovelace"
assert_eq "env::get reads an unquoted value from atlas.env" \
  "$(unset ATLAS_GIT_USER_EMAIL; env::get ATLAS_GIT_USER_EMAIL)" "ada@example.com"

# environment variable wins over the file
assert_eq "env var overrides atlas.env" \
  "$(ATLAS_GIT_USER_EMAIL='env@x' env::get ATLAS_GIT_USER_EMAIL)" "env@x"

# missing key -> non-zero, empty output
assert_status "missing key returns non-zero" 1 env::get ATLAS_DEFINITELY_MISSING_XYZ
assert_eq     "missing key prints nothing"   "$(env::get ATLAS_DEFINITELY_MISSING_XYZ 2>/dev/null)" ""

# comment lines are ignored (no key named '# a comment')
rm -rf "$sandbox"; unset ATLAS_CONFIG_HOME
```

- [ ] **Step 2: Run it — confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`env::get: command not found` / `internal/env.sh` missing).

- [ ] **Step 3: Implement `internal/env.sh`**

```bash
#!/usr/bin/env bash
[ -n "${ATLAS_ENV_SH:-}" ] && return 0; ATLAS_ENV_SH=1

: "${ATLAS_CONFIG_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/atlas}"

# env::get <NAME> — echo the user-supplied value of NAME.
# Resolution order: environment variable NAME, then NAME=value in atlas.env.
# Prints nothing and returns 1 if NAME is set in neither.
env::get() {
  local name="$1"
  if [ -n "${!name:-}" ]; then
    printf '%s\n' "${!name}"
    return 0
  fi
  local file="${ATLAS_CONFIG_HOME}/atlas.env"
  [ -r "$file" ] || return 1
  local line val=""
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    case "$line" in
      \#*) continue ;;
      "$name="*) val="${line#*=}" ;;
    esac
  done < "$file"
  [ -n "$val" ] || return 1
  # strip one layer of surrounding double or single quotes
  val="${val%\"}"; val="${val#\"}"
  val="${val%\'}"; val="${val#\'}"
  printf '%s\n' "$val"
}
```

- [ ] **Step 4: Wire it into the `atlas` entrypoint**

In `atlas`, find the engine-sourcing block:
```bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/internal/module.sh"
source "$ATLAS_ROOT/internal/runner.sh"
```
Add the `env.sh` source after `os.sh` (so module hooks running in the runner's subshell inherit `env::get`):
```bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/internal/env.sh"
source "$ATLAS_ROOT/internal/module.sh"
source "$ATLAS_ROOT/internal/runner.sh"
```

- [ ] **Step 5: Run tests — confirm pass**

Run: `bash tests/run.sh`
Expected: `test_env.sh` all `ok`; suite = 54 + 5 = **59 passed, 0 failed**. Also confirm `bash atlas --help` still exits 0 (entrypoint still sources cleanly).

- [ ] **Step 6: Commit**

```bash
git add internal/env.sh atlas tests/test_env.sh
git -c commit.gpgsign=false commit -m "feat(env): add atlas.env reader for user-specific config

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

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

### Task 4: Git module — optional `update` and `remove` hooks

**Files:**
- Modify: `modules/core/git/module.sh` (append `module::update` and `module::remove`)
- Modify: `tests/test_module_git.sh` (append update/remove assertions)

**Interfaces:**
- Consumes: the helpers from Task 3 (`_git_fragment`, `_git_include_present`, `_GIT_MODULE_DIR`).
- Produces: `module::update` (re-applies the managed fragment + ensures the include line; does not touch identity or the package) and `module::remove` (drops the include line and deletes the fragment; leaves the git package and the user's identity untouched).

- [ ] **Step 1: Append failing tests to `tests/test_module_git.sh`**

```bash
# update re-applies the fragment and keeps exactly one include line
assert_eq "git update keeps one include line" \
  "$(bash -c "$PRE"' module::install >/dev/null 2>&1; module::update >/dev/null 2>&1; git config --global --get-all include.path | wc -l | tr -d " "')" "1"

# remove deletes the fragment
assert_status "git remove deletes the fragment" 0 \
  bash -c "$PRE"' module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; [ ! -e "$ATLAS_CONFIG_HOME/git/gitconfig" ]'

# remove drops the include line (grep finds nothing -> exit 1)
assert_status "git remove drops the include line" 1 \
  bash -c "$PRE"' module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; git config --global --get-all include.path 2>/dev/null | grep -qxF "$ATLAS_CONFIG_HOME/git/gitconfig"'

# remove leaves the user's identity untouched
assert_eq "git remove leaves identity intact" \
  "$(bash -c "$PRE"' git config --global user.name "Keep Me"; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; git config --global --get user.name')" "Keep Me"
```

- [ ] **Step 2: Run — confirm the new assertions fail**

Run: `bash tests/run.sh`
Expected: the 4 new git assertions fail (`module::update`/`module::remove` not defined → the module subshell errors / grep still finds the include).

- [ ] **Step 3: Append `update` and `remove` to `modules/core/git/module.sh`**

Add after `module::verify`:
```bash
# --- optional hooks ----------------------------------------------------------

module::update() {
  # Re-apply the latest managed fragment and ensure the include line.
  # Does not touch identity or the git package.
  local frag_dir frag
  frag_dir="$(_git_fragment_dir)"; frag="$(_git_fragment)"
  mkdir -p "$frag_dir" || { log::error "cannot create $frag_dir"; return 1; }
  cp -f "$_GIT_MODULE_DIR/config/gitconfig" "$frag" || { log::error "cannot write $frag"; return 1; }
  _git_include_present || git config --global --add include.path "$frag" \
    || { log::error "cannot add include.path"; return 1; }
  log::info "re-applied managed git config"
  return 0
}

module::remove() {
  # Drop Atlas's include line and delete Atlas's fragment. Leaves the git
  # package installed (shared) and the user's identity untouched.
  local frag esc
  frag="$(_git_fragment)"
  if _git_include_present; then
    esc="$(printf '%s' "$frag" | sed -e 's/[][\\.^$*+?(){}|/]/\\&/g')"
    git config --global --unset-all include.path "^${esc}$" 2>/dev/null || true
    log::info "removed include.path -> $frag"
  fi
  if [ -e "$frag" ]; then
    rm -f "$frag" && log::info "deleted $frag"
  fi
  log::info "git package left installed (shared); identity untouched"
  return 0
}
```

- [ ] **Step 4: Run tests — confirm pass**

Run: `bash tests/run.sh`
Expected: all git assertions `ok`; suite = 70 + 4 = **74 passed, 0 failed**.

- [ ] **Step 5: Commit**

```bash
git add modules/core/git/module.sh tests/test_module_git.sh
git -c commit.gpgsign=false commit -m "feat(git): add update and remove hooks

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Documentation — module README, CHANGELOG, conventions

**Files:**
- Modify: `modules/core/git/README.md` (real behavior)
- Modify: `CHANGELOG.md` (Unreleased entry)
- Modify: `docs/conventions.md` (establish the `atlas.env` user-config convention)

**Interfaces:**
- Produces: documentation matching the shipped module. No code; deliverable is accurate, consistent docs.

- [ ] **Step 1: Rewrite `modules/core/git/README.md`**

```markdown
# git

**What it does:** Installs Git and applies Atlas's opinionated global defaults,
without ever overwriting your own `~/.gitconfig`.

**What it installs / configures:**
- The `git` package (via `dnf`, only if not already present).
- An Atlas-owned config fragment at `~/.config/atlas/git/gitconfig` holding the
  managed defaults: `init.defaultBranch=main`, `pull.rebase=true`,
  `push.default=simple`, `push.autoSetupRemote=true`, `fetch.prune=true`,
  `rebase.autostash=true`, `color.ui=auto`.
- A single `include.path` line added to `~/.gitconfig` pointing at that fragment.
  Anything you set directly in `~/.gitconfig` overrides these defaults.
- Your commit identity (`user.name` / `user.email`), taken from
  `ATLAS_GIT_USER_NAME` / `ATLAS_GIT_USER_EMAIL` (env var or
  `~/.config/atlas/atlas.env`) — set only if not already configured. If you
  provide neither, install still succeeds and logs a reminder.

**Depends on:** nothing (Atlas modules). Uses the engine's `os::dnf_install` and
`env::get`.

**Lifecycle:** `check` (is git installed + config wired?), `install`, `verify`,
`update` (re-apply the managed fragment), `remove` (drop the include line and the
fragment; the git package and your identity are left untouched). `backup` /
`restore` are intentionally not implemented — nothing here is both irreplaceable
and Atlas-owned.
```

- [ ] **Step 2: Add a `CHANGELOG.md` entry**

Under `## [Unreleased]` → `### Added`, append:
```markdown
- **core/git module** (RFC-0001): installs Git, applies Atlas's managed global
  defaults via an owned `include.path` fragment, and sets commit identity from
  `ATLAS_GIT_USER_*` / `atlas.env` (non-destructively). Real, idempotent
  `os::dnf_install` package primitive and the shared `env::get` (`atlas.env`)
  reader landed alongside it.
```

- [ ] **Step 3: Add the `atlas.env` convention to `docs/conventions.md`**

Append a new section:
```markdown
## User-specific configuration

Values that belong to the user, not the machine (git identity, tokens, etc.)
are **never** hard-coded or committed. A module reads them with `env::get NAME`
(`internal/env.sh`), which resolves:

1. the environment variable `NAME`, then
2. `NAME=value` in `~/.config/atlas/atlas.env` (a gitignored, machine-local file
   the user fills in once).

Modules apply such values **non-destructively** — set them only if unset, never
clobber a value the user already configured — and treat their absence as
non-fatal (log a reminder, continue).
```

- [ ] **Step 4: Verify docs + suite**

Run: `bash tests/run.sh` (still **74 passed, 0 failed**) and confirm the files exist and read correctly:
`ls modules/core/git/README.md CHANGELOG.md docs/conventions.md`

- [ ] **Step 5: Commit**

```bash
git add modules/core/git/README.md CHANGELOG.md docs/conventions.md
git -c commit.gpgsign=false commit -m "docs(git): document the git module + atlas.env convention

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (completed by plan author)

**1. Spec coverage vs RFC-0001:**
- §4.3 managed defaults → fragment content (Task 3 Step 1). ✔
- §4.4 include.path owned-fragment strategy → install/check/verify/update/remove (Tasks 3–4). ✔
- §4.5 identity env→atlas.env, non-blocking, set-if-unset → `env::get` (Task 2) + `_git_apply_identity` (Task 3). ✔
- §4.6 real `os::dnf_install` → Task 1. ✔
- §4.7 hook contracts incl. backup/restore intentionally omitted → Tasks 3–4 (omission is explicit; `test_modules.sh` only requires the 3 required hooks). ✔
- §5 idempotency table → Task 3/4 mechanisms + idempotency test. ✔
- §6 testing pattern (mock the primitive, sandbox HOME, assert twice) → all test files. ✔
- §7 documentation plan → Task 5. ✔

**2. Placeholder scan:** none — every step has complete code/content. The module's `backup`/`restore` absence is spec-mandated, not a placeholder.

**3. Type/name consistency:** verified across tasks — `os::dnf_install`, `env::get`, `_git_fragment`/`_git_fragment_dir`/`_git_include_present`/`_git_apply_identity`/`_GIT_MODULE_DIR`, `module::check|install|verify|update|remove`, env keys `ATLAS_GIT_USER_NAME`/`ATLAS_GIT_USER_EMAIL`, `ATLAS_CONFIG_HOME`. Names match between definition and use.

**4. Safety:** no automated test touches the real `$HOME` or runs real `dnf` — every git assertion sandboxes `HOME`/`GIT_CONFIG_GLOBAL`/`GIT_CONFIG_SYSTEM`/`ATLAS_CONFIG_HOME` in a child bash and mocks `os::dnf_install`. Real end-to-end (`atlas install core/git` on a live Fedora box) is an integration check, out of automated scope.
