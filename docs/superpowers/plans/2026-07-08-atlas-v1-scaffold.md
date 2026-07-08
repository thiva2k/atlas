# Atlas v1 Scaffold — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Atlas v1 skeleton — a runnable, end-to-end workstation-lifecycle CLI with a reusable Bash engine and placeholder modules — with **no real installation logic yet**.

**Architecture:** A single `atlas` CLI parses a platform verb and dispatches it to modules through the runner. The reusable engine lives in `internal/` (logging, errors, OS helpers, module contract, runner). Capabilities live in `modules/<category>/<name>/`, each self-contained with `module.sh` (metadata + `module::` hooks), optional `config/`, and a `README.md`. Placeholder hooks log "not yet implemented" and return cleanly so the whole system runs while doing no work.

**Tech Stack:** Bash + GNU coreutils only. No external runtime dependencies. Tests use a tiny pure-Bash harness (no bats, no framework).

## Global Constraints

- **Runtime dependencies:** Bash, GNU coreutils, Git, Fedora base system — nothing else. No Ansible, Python, `jq`, `yq`, YAML parser, `just`, or `make` on the end-user path.
- **Every file that is a shell script** starts with `#!/usr/bin/env bash`.
- **Line endings are LF** (enforced by `.gitattributes`) — this repo is authored from Windows/WSL and CRLF silently breaks Bash.
- **No ad-hoc `echo` for user-facing output** — use the `log::*` API. (`echo` is fine for machine output like `--version` and internal string returns.)
- **Module hook namespace:** `module::check|install|verify|update|remove|backup|restore`. `check`/`install`/`verify` required.
- **Metadata is plain Bash:** `MODULE_NAME`, `MODULE_DESCRIPTION`, `MODULE_DEPENDS=()`. Category is the directory, never declared.
- **Exit codes:** `0` ok · `1` general · `2` usage · `3` dependency · `4` module-fatal · `5` unsupported-env.
- **Strict mode:** the `atlas` entrypoint uses `set -uo pipefail` with explicit exit-code propagation; **module hook subshells** use `set -euo pipefail`. Fatal paths go through `die`.
- **Commit style:** conventional commits; end each message body with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Commit with `git -c commit.gpgsign=false`.
- **Every module ships a README** answering: what it does, what it installs/configures, what it depends on.

**Repo:** `/home/thiva/atlas` (remote `origin` → `github.com/thiva2k/atlas`, private). `docs/architecture.md` already exists — treat it as the source of truth.

---

### Task 1: Repo hygiene + pure-Bash test harness

**Files:**
- Create: `.gitattributes`
- Create: `.gitignore`
- Create: `tests/lib/assert.sh`
- Create: `tests/run.sh`
- Create: `tests/test_harness.sh` (self-test of the harness)

**Interfaces:**
- Produces: assertion API used by every later test — `assert_eq <name> <actual> <expected>`, `assert_contains <name> <haystack> <needle>`, `assert_status <name> <expected_code> <cmd...>`; a runner `tests/run.sh` that sources every `tests/test_*.sh`, sums `ATLAS_TESTS_PASS`/`ATLAS_TESTS_FAIL`, and exits non-zero on any failure. `ATLAS_ROOT` is exported by `tests/run.sh` as the repo root.

- [ ] **Step 1: Write `.gitattributes`**

```gitattributes
* text=auto eol=lf
*.sh text eol=lf
atlas text eol=lf
bootstrap.sh text eol=lf
*.md text eol=lf
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
# Atlas runtime state (never committed)
.local/
*.log

# OS / editor noise
.DS_Store
__MACOSX/
*.swp
```

- [ ] **Step 3: Write the assertion library `tests/lib/assert.sh`**

```bash
#!/usr/bin/env bash
# Tiny pure-Bash assertion library. No external framework.
# Each test file increments ATLAS_TESTS_PASS / ATLAS_TESTS_FAIL via these.

_t_ok()   { ATLAS_TESTS_PASS=$((ATLAS_TESTS_PASS + 1)); printf '  ok   %s\n' "$1"; }
_t_fail() { ATLAS_TESTS_FAIL=$((ATLAS_TESTS_FAIL + 1)); printf '  FAIL %s\n' "$1"; }

assert_eq() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then _t_ok "$1"
  else _t_fail "$1"; printf '       expected [%s] got [%s]\n' "$3" "$2"; fi
}

assert_contains() { # <name> <haystack> <needle>
  case "$2" in
    *"$3"*) _t_ok "$1" ;;
    *) _t_fail "$1"; printf '       [%s] does not contain [%s]\n' "$2" "$3" ;;
  esac
}

assert_status() { # <name> <expected_code> <cmd...>
  local name="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then _t_ok "$name"
  else _t_fail "$name"; printf '       exit %s, wanted %s\n' "$got" "$want"; fi
}
```

- [ ] **Step 4: Write the test runner `tests/run.sh`**

```bash
#!/usr/bin/env bash
set -uo pipefail
ATLAS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ATLAS_ROOT
# keep test state out of the real state dir
export ATLAS_STATE_DIR="$ATLAS_ROOT/.local/state/atlas"

source "$ATLAS_ROOT/tests/lib/assert.sh"

total_pass=0 total_fail=0
for t in "$ATLAS_ROOT"/tests/test_*.sh; do
  [ -e "$t" ] || continue
  printf '\n%s\n' "$(basename "$t")"
  ATLAS_TESTS_PASS=0 ATLAS_TESTS_FAIL=0
  # shellcheck source=/dev/null
  source "$t"
  total_pass=$((total_pass + ATLAS_TESTS_PASS))
  total_fail=$((total_fail + ATLAS_TESTS_FAIL))
done

printf '\n== %d passed, %d failed ==\n' "$total_pass" "$total_fail"
[ "$total_fail" -eq 0 ]
```

- [ ] **Step 5: Write the harness self-test `tests/test_harness.sh`**

```bash
#!/usr/bin/env bash
# Proves the assertion library itself works.
assert_eq       "assert_eq matches equal strings"      "abc" "abc"
assert_contains "assert_contains finds a substring"    "hello world" "world"
assert_status   "assert_status reads true's exit code" 0 true
assert_status   "assert_status reads false's exit code" 1 false
```

- [ ] **Step 6: Run the harness to verify it passes**

Run: `bash tests/run.sh`
Expected: ends with `== 4 passed, 0 failed ==` and exit code 0.

- [ ] **Step 7: Commit**

```bash
git add .gitattributes .gitignore tests/
git -c commit.gpgsign=false commit -m "test: add pure-Bash test harness and repo hygiene

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Logging engine (`internal/log.sh`)

**Files:**
- Create: `internal/log.sh`
- Test: `tests/test_log.sh`

**Interfaces:**
- Produces: `log::debug|info|warn|error|step <msg...>`. Honors `ATLAS_LOG_LEVEL` (`debug|info|warn|error`, default `info`). Writes user output to **stderr**, colored only when stderr is a TTY. Always appends a plain line to `$ATLAS_STATE_DIR/logs/atlas-<YYYYMMDD>.log`. Scope tag comes from `ATLAS_LOG_SCOPE` (default `atlas`). Format: `<ISO-8601-ts>  <LEVEL>  [<scope>]  <msg>`.

- [ ] **Step 1: Write the failing test `tests/test_log.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"

# info is emitted at default level
out="$(ATLAS_LOG_LEVEL=info log::info "hello" 2>&1 1>/dev/null)"
assert_contains "info line has level"   "$out" "INFO"
assert_contains "info line has message" "$out" "hello"
assert_contains "info line has scope"   "$out" "[atlas]"

# debug is suppressed when the floor is info
out="$(ATLAS_LOG_LEVEL=info log::debug "quiet" 2>&1 1>/dev/null)"
assert_eq "debug suppressed at info level" "$out" ""

# scope override is honored
out="$(ATLAS_LOG_SCOPE=git log::info "scoped" 2>&1 1>/dev/null)"
assert_contains "scope override applies" "$out" "[git]"

# every call persists to the logfile
logf="$ATLAS_STATE_DIR/logs/atlas-$(date +%Y%m%d).log"
log::warn "persist-me" 2>/dev/null
assert_contains "logfile captured the line" "$(cat "$logf")" "persist-me"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`internal/log.sh` does not exist / `log::info: command not found`).

- [ ] **Step 3: Implement `internal/log.sh`**

```bash
#!/usr/bin/env bash
[ -n "${ATLAS_LOG_SH:-}" ] && return 0; ATLAS_LOG_SH=1

: "${ATLAS_LOG_LEVEL:=info}"
: "${ATLAS_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/atlas}"

_log_level_num() {
  case "$1" in
    debug) echo 0 ;; info) echo 1 ;; warn) echo 2 ;; error) echo 3 ;; *) echo 1 ;;
  esac
}

_log_file() {
  local dir="$ATLAS_STATE_DIR/logs"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s/atlas-%s.log' "$dir" "$(date +%Y%m%d)"
}

_log_emit() { # <level> <color> <msg>
  local level="$1" color="$2" msg="$3"
  local ts scope line
  ts="$(date +%Y-%m-%dT%H:%M:%S)"
  scope="${ATLAS_LOG_SCOPE:-atlas}"
  line="$ts  $(printf '%s' "$level" | tr '[:lower:]' '[:upper:]')  [$scope]  $msg"
  printf '%s\n' "$line" >> "$(_log_file)" 2>/dev/null || true
  if [ "$(_log_level_num "$level")" -ge "$(_log_level_num "$ATLAS_LOG_LEVEL")" ]; then
    if [ -t 2 ] && [ -n "$color" ]; then
      printf '%b%s%b\n' "$color" "$line" '\033[0m' >&2
    else
      printf '%s\n' "$line" >&2
    fi
  fi
}

log::debug() { _log_emit debug '\033[2m'    "$*"; }
log::info()  { _log_emit info  ''           "$*"; }
log::warn()  { _log_emit warn  '\033[33m'   "$*"; }
log::error() { _log_emit error '\033[31m'   "$*"; }
log::step()  { _log_emit info  '\033[1;36m' "== $* =="; }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: the `test_log.sh` block shows all `ok`, suite still `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add internal/log.sh tests/test_log.sh
git -c commit.gpgsign=false commit -m "feat(internal): add reusable logging engine

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Error handling + exit codes (`internal/error.sh`)

**Files:**
- Create: `internal/error.sh`
- Test: `tests/test_error.sh`

**Interfaces:**
- Consumes: `log::error` from Task 2.
- Produces: readonly exit-code constants `ATLAS_EXIT_OK=0 ATLAS_EXIT_GENERAL=1 ATLAS_EXIT_USAGE=2 ATLAS_EXIT_DEPENDENCY=3 ATLAS_EXIT_MODULE=4 ATLAS_EXIT_UNSUPPORTED=5`; `die <code> <what> [why] [how]` which logs the three lines and exits `<code>`.

- [ ] **Step 1: Write the failing test `tests/test_error.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"

assert_eq "usage exit code constant" "$ATLAS_EXIT_USAGE" "2"
assert_eq "module exit code constant" "$ATLAS_EXIT_MODULE" "4"

# die exits with the given code (run in a subshell so it doesn't kill the test)
assert_status "die uses the provided code" 3 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; die 3 "boom"'

# die surfaces what / why / how
out="$(bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; die 1 "what-x" "why-y" "how-z"' 2>&1 || true)"
assert_contains "die prints what" "$out" "what-x"
assert_contains "die prints why"  "$out" "why-y"
assert_contains "die prints how"  "$out" "how-z"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`ATLAS_EXIT_USAGE: unbound` / `die: command not found`).

- [ ] **Step 3: Implement `internal/error.sh`**

```bash
#!/usr/bin/env bash
[ -n "${ATLAS_ERROR_SH:-}" ] && return 0; ATLAS_ERROR_SH=1

readonly ATLAS_EXIT_OK=0
readonly ATLAS_EXIT_GENERAL=1
readonly ATLAS_EXIT_USAGE=2
readonly ATLAS_EXIT_DEPENDENCY=3
readonly ATLAS_EXIT_MODULE=4
readonly ATLAS_EXIT_UNSUPPORTED=5

# die <code> <what> [why] [how] — every fatal error answers what/why/how.
die() {
  local code="$1" what="$2" why="${3:-}" how="${4:-}"
  log::error "$what"
  [ -n "$why" ] && log::error "  why: $why"
  [ -n "$how" ] && log::error "  fix: $how"
  exit "$code"
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_error.sh` all `ok`; suite `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add internal/error.sh tests/test_error.sh
git -c commit.gpgsign=false commit -m "feat(internal): add exit codes and die() error helper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: OS / environment helpers (`internal/os.sh`)

**Files:**
- Create: `internal/os.sh`
- Test: `tests/test_os.sh`

**Interfaces:**
- Consumes: `log::*`, `die`, `ATLAS_EXIT_UNSUPPORTED`.
- Produces: `os::has_cmd <cmd>` (bool), `os::require_cmd <cmd>` (dies if missing), `os::is_fedora` (bool via `/etc/os-release`), `os::is_root` (bool). Placeholder install wrappers `os::dnf_install <pkgs...>` and `os::flatpak_install <pkgs...>` that only log intent for now.

- [ ] **Step 1: Write the failing test `tests/test_os.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"

assert_status "has_cmd true for bash"      0 os::has_cmd bash
assert_status "has_cmd false for nonesuch" 1 os::has_cmd this_command_does_not_exist_xyz
assert_status "require_cmd dies on missing" 5 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"; os::require_cmd nope_xyz'

out="$(os::dnf_install git curl 2>&1 || true)"
assert_contains "dnf_install logs intent" "$out" "git curl"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`os::has_cmd: command not found`).

- [ ] **Step 3: Implement `internal/os.sh`**

```bash
#!/usr/bin/env bash
[ -n "${ATLAS_OS_SH:-}" ] && return 0; ATLAS_OS_SH=1

os::has_cmd() { command -v "$1" >/dev/null 2>&1; }

os::require_cmd() {
  os::has_cmd "$1" && return 0
  die "$ATLAS_EXIT_UNSUPPORTED" \
    "required command not found: $1" \
    "Atlas needs '$1' on PATH to continue" \
    "install '$1' and re-run"
}

os::is_fedora() {
  [ -r /etc/os-release ] || return 1
  grep -qi '^ID=fedora$' /etc/os-release
}

os::is_root() { [ "$(id -u)" -eq 0 ]; }

# --- placeholder installers (real logic lands with the modules that need them) ---
os::dnf_install()     { log::info "would dnf install: $*"; }
os::flatpak_install() { log::info "would flatpak install: $*"; }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_os.sh` all `ok`; suite `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add internal/os.sh tests/test_os.sh
git -c commit.gpgsign=false commit -m "feat(internal): add OS detection and install placeholder helpers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Module discovery + contract helpers (`internal/module.sh`)

**Files:**
- Create: `internal/module.sh`
- Test: `tests/test_module_discovery.sh`
- Test fixtures: `tests/fixtures/modules/core/alpha/module.sh`, `tests/fixtures/modules/apps/beta/module.sh`

**Interfaces:**
- Consumes: `log::*`, `die`, exit codes, `$ATLAS_ROOT`.
- Produces: `ATLAS_MODULES_DIR` (default `$ATLAS_ROOT/modules`); `module::discover` → prints `category/name` per module, sorted; `module::path <id>` → path to its `module.sh`; `module::has_hook <hook>` → true if `module::<hook>` is defined in the current (sourced) shell; `not_implemented <what>` → logs a warning and returns 0 (used by placeholder hooks). Dependency ordering is added in Task 6.

- [ ] **Step 1: Write the fixture modules**

`tests/fixtures/modules/core/alpha/module.sh`:

```bash
#!/usr/bin/env bash
MODULE_NAME="alpha"
MODULE_DESCRIPTION="fixture module alpha"
MODULE_DEPENDS=()
module::check()   { return 1; }
module::install() { not_implemented "alpha install"; }
module::verify()  { not_implemented "alpha verify"; }
```

`tests/fixtures/modules/apps/beta/module.sh`:

```bash
#!/usr/bin/env bash
MODULE_NAME="beta"
MODULE_DESCRIPTION="fixture module beta (depends on alpha)"
MODULE_DEPENDS=("core/alpha")
module::check()   { return 1; }
module::install() { not_implemented "beta install"; }
module::verify()  { not_implemented "beta verify"; }
```

- [ ] **Step 2: Write the failing test `tests/test_module_discovery.sh`**

```bash
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
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`module::discover: command not found`).

- [ ] **Step 4: Implement discovery portion of `internal/module.sh`**

```bash
#!/usr/bin/env bash
[ -n "${ATLAS_MODULE_SH:-}" ] && return 0; ATLAS_MODULE_SH=1

: "${ATLAS_MODULES_DIR:=${ATLAS_ROOT:-.}/modules}"

# Placeholder-hook helper, available to modules once this file is sourced.
not_implemented() { log::warn "not yet implemented: $*"; return 0; }

# Print every module id ("category/name"), one per line, sorted.
module::discover() {
  local f id
  for f in "$ATLAS_MODULES_DIR"/*/*/module.sh; do
    [ -e "$f" ] || continue
    id="${f#"$ATLAS_MODULES_DIR"/}"
    id="${id%/module.sh}"
    printf '%s\n' "$id"
  done | sort
}

module::path() { printf '%s\n' "$ATLAS_MODULES_DIR/$1/module.sh"; }

module::has_hook() { declare -F "module::$1" >/dev/null 2>&1; }

# Dependency ordering (module::deps_of, module::resolve_order) is added in Task 6.
```

- [ ] **Step 5: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_module_discovery.sh` all `ok`; suite `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add internal/module.sh tests/test_module_discovery.sh tests/fixtures/
git -c commit.gpgsign=false commit -m "feat(internal): add module discovery and contract helpers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Dependency resolution / topological order (`internal/module.sh`)

**Files:**
- Modify: `internal/module.sh` (append `module::deps_of` and `module::resolve_order`)
- Test: `tests/test_module_order.sh`
- Test fixture: `tests/fixtures/modules/core/cyc_a/module.sh`, `tests/fixtures/modules/core/cyc_b/module.sh`

**Interfaces:**
- Consumes: `module::path`, `die`, `ATLAS_EXIT_DEPENDENCY`.
- Produces: `module::deps_of <id>` → prints each declared dependency id (reads `MODULE_DEPENDS` by sourcing the module in a subshell); `module::resolve_order <id...>` → prints the input ids plus their transitive deps in dependency-first order; a dependency **cycle** causes `die` with exit `3`.

- [ ] **Step 1: Write the cycle fixtures**

`tests/fixtures/modules/core/cyc_a/module.sh`:

```bash
#!/usr/bin/env bash
MODULE_NAME="cyc_a"
MODULE_DESCRIPTION="cycle fixture a"
MODULE_DEPENDS=("core/cyc_b")
module::check()   { return 1; }
module::install() { not_implemented "cyc_a"; }
module::verify()  { not_implemented "cyc_a"; }
```

`tests/fixtures/modules/core/cyc_b/module.sh`:

```bash
#!/usr/bin/env bash
MODULE_NAME="cyc_b"
MODULE_DESCRIPTION="cycle fixture b"
MODULE_DEPENDS=("core/cyc_a")
module::check()   { return 1; }
module::install() { not_implemented "cyc_b"; }
module::verify()  { not_implemented "cyc_b"; }
```

- [ ] **Step 2: Write the failing test `tests/test_module_order.sh`**

```bash
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
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`module::deps_of: command not found`).

- [ ] **Step 4: Append dependency resolution to `internal/module.sh`**

```bash
# --- dependency resolution -------------------------------------------------

# Print a module's declared dependencies (one per line), read in isolation.
module::deps_of() {
  local id="$1" p; p="$(module::path "$id")"
  [ -r "$p" ] || return 0
  ( set +u
    MODULE_DEPENDS=()
    # shellcheck source=/dev/null
    source "$p"
    local d
    for d in "${MODULE_DEPENDS[@]}"; do
      [ -n "$d" ] && printf '%s\n' "$d"
    done )
}

# Print ids + transitive deps in dependency-first order. Cycle => exit 3.
module::resolve_order() {
  local -a input=("$@")
  local -A _state=()          # unset | temp | done
  local -a _order=()

  _module_visit() {
    local id="$1" d
    case "${_state[$id]:-}" in
      done) return 0 ;;
      temp) die "$ATLAS_EXIT_DEPENDENCY" \
              "dependency cycle detected at '$id'" \
              "two or more modules depend on each other in a loop" \
              "break the loop by editing a module's MODULE_DEPENDS" ;;
    esac
    _state[$id]=temp
    while IFS= read -r d; do
      [ -n "$d" ] && _module_visit "$d"
    done < <(module::deps_of "$id")
    _state[$id]=done
    _order+=("$id")
  }

  local id
  for id in "${input[@]}"; do _module_visit "$id"; done
  printf '%s\n' "${_order[@]}"
}
```

- [ ] **Step 5: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_module_order.sh` all `ok`; suite `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add internal/module.sh tests/test_module_order.sh tests/fixtures/
git -c commit.gpgsign=false commit -m "feat(internal): resolve module dependencies with cycle detection

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: The runner (`internal/runner.sh`)

**Files:**
- Create: `internal/runner.sh`
- Test: `tests/test_runner.sh`

**Interfaces:**
- Consumes: `module::discover`, `module::resolve_order`, `module::path`, `module::has_hook`, `log::*`, `die`, exit codes.
- Produces: `runner::run <verb> [id...]` — validates the verb, selects modules (given ids or all discovered), orders them, and fans the verb's hook sequence across each module **in an isolated `set -euo pipefail` subshell** (`ATLAS_LOG_SCOPE` set to the module id). Verb→hook map: `install`→`check,install,verify` (a passing `check` skips the module), `update`→`update`, `verify`→`verify`, `backup`→`backup`, `restore`→`restore`, `status`→`check`, `doctor`→`verify`. Prints a summary and returns `ATLAS_EXIT_MODULE` if any module failed, else `0`. An unknown verb → `die` exit `2`.

- [ ] **Step 1: Write the failing test `tests/test_runner.sh`**

```bash
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

# unknown verb is a usage error
assert_status "runner rejects unknown verb" 2 runner::run frobnicate

# placeholder install path emits the not-implemented notice
out="$(runner::run install core/alpha 2>&1 || true)"
assert_contains "install reaches placeholder hook" "$out" "not yet implemented"

# a module whose check passes is skipped
out="$(ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules_satisfied" \
       bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"; source "$ATLAS_ROOT/internal/module.sh"; source "$ATLAS_ROOT/internal/runner.sh"; runner::run install core/sat' 2>&1 || true)"
assert_contains "satisfied module is skipped" "$out" "already satisfied"
```

- [ ] **Step 2: Add the "already satisfied" fixture `tests/fixtures/modules_satisfied/core/sat/module.sh`**

```bash
#!/usr/bin/env bash
MODULE_NAME="sat"
MODULE_DESCRIPTION="fixture whose check passes"
MODULE_DEPENDS=()
module::check()   { return 0; }
module::install() { not_implemented "sat install"; }
module::verify()  { not_implemented "sat verify"; }
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`runner::run: command not found`).

- [ ] **Step 4: Implement `internal/runner.sh`**

```bash
#!/usr/bin/env bash
[ -n "${ATLAS_RUNNER_SH:-}" ] && return 0; ATLAS_RUNNER_SH=1

# Ordered hook sequence for a verb (empty + return 1 => unknown verb).
_runner_hooks_for_verb() {
  case "$1" in
    install) echo "check install verify" ;;
    update)  echo "update"  ;;
    verify)  echo "verify"  ;;
    backup)  echo "backup"  ;;
    restore) echo "restore" ;;
    status)  echo "check"   ;;
    doctor)  echo "verify"  ;;
    *) return 1 ;;
  esac
}

# Run one module's part of a verb in an isolated subshell.
# stdout carries a control token (__SKIP__) only; logs go to stderr.
# Returns 0 on success/skip, non-zero on hook failure.
_runner_run_module() {
  local verb="$1" id="$2" hooks
  hooks="$(_runner_hooks_for_verb "$verb")" || return "$ATLAS_EXIT_USAGE"
  (
    set -euo pipefail
    ATLAS_LOG_SCOPE="$id"
    # shellcheck source=/dev/null
    source "$(module::path "$id")"
    local hook
    for hook in $hooks; do
      if [ "$verb" = "install" ] && [ "$hook" = "check" ]; then
        if module::has_hook check && module::check; then
          log::info "already satisfied — skipping"
          printf '__SKIP__'
          exit 0
        fi
        continue
      fi
      module::has_hook "$hook" || { log::debug "no $hook hook"; continue; }
      if ! "module::$hook"; then
        log::error "$hook failed"
        exit 1
      fi
    done
  )
}

# runner::run <verb> [id...]
runner::run() {
  local verb="${1:-}"; shift || true
  _runner_hooks_for_verb "$verb" >/dev/null 2>&1 || \
    die "$ATLAS_EXIT_USAGE" "unknown command: $verb" "" "run 'atlas --help'"

  local -a ids
  if [ "$#" -gt 0 ]; then ids=("$@"); else mapfile -t ids < <(module::discover); fi
  if [ "${#ids[@]}" -eq 0 ]; then log::warn "no modules found"; return 0; fi
  mapfile -t ids < <(module::resolve_order "${ids[@]}")

  log::step "atlas $verb (${#ids[@]} modules)"
  local id out rc ok=0 skip=0 fail=0
  for id in "${ids[@]}"; do
    out="$(_runner_run_module "$verb" "$id")"; rc=$?
    if [ "$rc" -ne 0 ]; then
      fail=$((fail + 1)); log::error "[$id] failed"
    elif [ "$out" = "__SKIP__" ]; then
      skip=$((skip + 1))
    else
      ok=$((ok + 1))
    fi
  done
  log::step "done: $ok ok, $skip skipped, $fail failed"
  [ "$fail" -eq 0 ] || return "$ATLAS_EXIT_MODULE"
  return 0
}
```

- [ ] **Step 5: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_runner.sh` all `ok`; suite `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add internal/runner.sh tests/test_runner.sh tests/fixtures/
git -c commit.gpgsign=false commit -m "feat(internal): add runner that fans verbs across modules

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: The CLI entrypoint (`atlas`)

**Files:**
- Create: `atlas` (executable, no extension)
- Test: `tests/test_cli.sh`

**Interfaces:**
- Consumes: everything in `internal/`.
- Produces: the `atlas` executable. Resolves `ATLAS_ROOT` from its own location (following symlinks), sources the engine, sets `set -uo pipefail`, parses global flags (`-v/--verbose`, `-q/--quiet`, `--version`, `-h/--help`), takes the first non-flag as the verb and the rest as module ids, and dispatches: `help`/`version` handled locally, the seven platform verbs go to `runner::run`, no verb → help, unknown verb/option → exit `2`. Runner exit codes propagate.

- [ ] **Step 1: Write the failing test `tests/test_cli.sh`**

```bash
#!/usr/bin/env bash
ATLAS="$ATLAS_ROOT/atlas"
# point the CLI at the fixture modules so it runs without real ones
export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"

assert_status "help exits 0"          0 bash "$ATLAS" --help
assert_status "version exits 0"       0 bash "$ATLAS" --version
assert_status "unknown verb exits 2"  2 bash "$ATLAS" frobnicate
assert_status "unknown option exits 2" 2 bash "$ATLAS" --nope
assert_status "install on fixtures 0" 0 bash "$ATLAS" install core/alpha apps/beta

out="$(bash "$ATLAS" --help 2>&1)"
assert_contains "help shows usage"    "$out" "Usage: atlas"
assert_contains "help lists install"  "$out" "install"

out="$(bash "$ATLAS" --version 2>&1)"
assert_contains "version prints a number" "$out" "0.1.0"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`atlas` file not found).

- [ ] **Step 3: Implement `atlas`**

```bash
#!/usr/bin/env bash
# Atlas — workstation lifecycle manager. CLI entrypoint.
set -uo pipefail

# Resolve ATLAS_ROOT = directory of this script, following symlinks.
_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" >/dev/null 2>&1 && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
ATLAS_ROOT="$(cd -P "$(dirname "$_src")" >/dev/null 2>&1 && pwd)"
export ATLAS_ROOT

ATLAS_VERSION="0.1.0-dev"

source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/internal/module.sh"
source "$ATLAS_ROOT/internal/runner.sh"

usage() {
  cat <<EOF
Atlas — workstation lifecycle manager (v$ATLAS_VERSION)

Usage: atlas <command> [modules...] [options]

Commands:
  install    ensure modules are present & configured
  update     bring modules to their latest desired state
  verify     check that modules are healthy
  backup     capture irreplaceable module state
  restore    re-apply previously captured state
  doctor     diagnose the workstation
  status     show what is / isn't installed
  help       show this help
  version    show the version

Options:
  -v, --verbose   more output (debug level)
  -q, --quiet     less output (errors only)
      --version   print version and exit
  -h, --help      print this help and exit
EOF
}

main() {
  local verb="" ; local -a rest=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -v|--verbose) ATLAS_LOG_LEVEL=debug ;;
      -q|--quiet)   ATLAS_LOG_LEVEL=error ;;
      --version)    echo "$ATLAS_VERSION"; return 0 ;;
      -h|--help)    usage; return 0 ;;
      -*)           die "$ATLAS_EXIT_USAGE" "unknown option: $1" "" "run 'atlas --help'" ;;
      *)            if [ -z "$verb" ]; then verb="$1"; else rest+=("$1"); fi ;;
    esac
    shift
  done
  export ATLAS_LOG_LEVEL

  case "${verb:-help}" in
    help)    usage ;;
    version) echo "$ATLAS_VERSION" ;;
    install|update|verify|backup|restore|doctor|status)
      runner::run "$verb" "${rest[@]}" ;;
    *) die "$ATLAS_EXIT_USAGE" "unknown command: $verb" "" "run 'atlas --help'" ;;
  esac
}

main "$@"
```

- [ ] **Step 4: Make it executable and run tests**

Run: `chmod +x atlas && bash tests/run.sh`
Expected: `test_cli.sh` all `ok`; suite `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add atlas tests/test_cli.sh
git -c commit.gpgsign=false commit -m "feat(cli): add atlas entrypoint dispatching platform verbs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: The eight placeholder modules

**Files:**
- Create per module: `modules/<category>/<name>/module.sh` + `README.md`
  - `modules/core/git/` (+ `config/gitconfig.template`)
  - `modules/development/docker/`
  - `modules/development/claude/`
  - `modules/development/codex/`
  - `modules/apps/brave/`
  - `modules/apps/ghostty/`
  - `modules/desktop/kde/`
  - `modules/desktop/fonts/`
- Test: `tests/test_modules.sh`

**Interfaces:**
- Consumes: the module contract; `not_implemented`.
- Produces: eight real modules with metadata + `check`/`install`/`verify` placeholder hooks (`check` returns 1 so the install path is exercised; `install`/`verify` call `not_implemented` and return 0). `modules/core/git` additionally ships a `config/` directory and declares no dependencies; `development/docker` depends on `core/git` only if genuinely needed — for v1 all `MODULE_DEPENDS=()` to keep the graph flat. Every module has a README answering the three standard questions.

- [ ] **Step 1: Write the failing test `tests/test_modules.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/module.sh"   # uses real ATLAS_MODULES_DIR ($ATLAS_ROOT/modules)

expected="apps/brave apps/ghostty core/git desktop/fonts desktop/kde development/claude development/codex development/docker"
got="$(module::discover | tr '\n' ' ' | sed 's/ *$//')"
assert_eq "all eight modules discovered" "$got" "$expected"

# every module satisfies the contract: metadata + three required hooks + README
fail=0
while IFS= read -r id; do
  p="$(module::path "$id")"
  ( source "$p"
    [ -n "${MODULE_NAME:-}" ]        || exit 1
    [ -n "${MODULE_DESCRIPTION:-}" ] || exit 1
    declare -F module::check   >/dev/null || exit 1
    declare -F module::install >/dev/null || exit 1
    declare -F module::verify  >/dev/null || exit 1 ) || { fail=1; printf 'contract miss: %s\n' "$id"; }
  [ -r "${p%/module.sh}/README.md" ] || { fail=1; printf 'missing README: %s\n' "$id"; }
done < <(module::discover)
assert_eq "every module satisfies the contract + has a README" "$fail" "0"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (no modules under `modules/`; discovery empty).

- [ ] **Step 3: Write the git module** — `modules/core/git/module.sh`

```bash
#!/usr/bin/env bash
MODULE_NAME="git"
MODULE_DESCRIPTION="Distributed version control: installs git and applies global config."
MODULE_DEPENDS=()

module::check()   { return 1; }               # TODO: os::has_cmd git && gitconfig applied
module::install() { not_implemented "git: dnf install git + apply config/gitconfig.template"; }
module::verify()  { not_implemented "git: git --version and config sanity"; }
```

- [ ] **Step 4: Write git's config template** — `modules/core/git/config/gitconfig.template`

```ini
# Applied by the git module (placeholder — not yet wired up).
[init]
	defaultBranch = main
[pull]
	rebase = true
```

- [ ] **Step 5: Write git's README** — `modules/core/git/README.md`

```markdown
# git

**What it does:** Installs Git and applies a global configuration.

**Installs / configures:** the `git` package; a global `~/.gitconfig` derived
from `config/gitconfig.template`.

**Depends on:** nothing.

> Status: placeholder. Hooks log "not yet implemented"; real logic lands later.
```

- [ ] **Step 6: Write the remaining seven modules** (same shape; adjust name/description/paths)

For each of `development/docker`, `development/claude`, `development/codex`, `apps/brave`, `apps/ghostty`, `desktop/kde`, `desktop/fonts`, create `module.sh`:

```bash
#!/usr/bin/env bash
MODULE_NAME="<name>"
MODULE_DESCRIPTION="<one-line description>"
MODULE_DEPENDS=()

module::check()   { return 1; }
module::install() { not_implemented "<name> install"; }
module::verify()  { not_implemented "<name> verify"; }
```

Use these descriptions verbatim:
- `development/docker` → "Container runtime: installs Docker Engine and enables the service."
- `development/claude` → "Claude Code CLI: installs the CLI and restores its configuration."
- `development/codex` → "Codex CLI: installs the CLI and restores its configuration."
- `apps/brave` → "Brave browser: installs Brave via its official repository."
- `apps/ghostty` → "Ghostty terminal: installs the Ghostty terminal emulator."
- `desktop/kde` → "KDE Plasma: installs and configures the KDE Plasma desktop."
- `desktop/fonts` → "Developer fonts: installs Nerd Fonts and common typefaces."

And a `README.md` for each, following the git template (What it does / Installs-configures / Depends on / placeholder status).

- [ ] **Step 7: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_modules.sh` all `ok`; suite `0 failed`.

- [ ] **Step 8: Smoke-test the whole system end-to-end**

Run: `bash atlas status && bash atlas install && bash atlas verify`
Expected: each exits 0, prints a `== atlas <verb> (8 modules) ==` step line and a `done: … ok, … skipped, … failed` summary with `0 failed`.

- [ ] **Step 9: Commit**

```bash
git add modules/ tests/test_modules.sh
git -c commit.gpgsign=false commit -m "feat(modules): add eight placeholder modules across four categories

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Bootstrap script (`bootstrap.sh`)

**Files:**
- Create: `bootstrap.sh`
- Test: `tests/test_bootstrap.sh`

**Interfaces:**
- Produces: `bootstrap.sh` — the zero-dependency first touch on a fresh machine. It ensures Git is present (logs the `dnf install git` it would run if missing), ensures the repo is present at `${ATLAS_HOME:-$HOME/atlas}` (clones if absent, otherwise leaves it), and hands off by printing the next command (`atlas install`). For v1 it must be **syntactically valid**, support `--help`, and must not perform destructive actions when run in a repo that already exists. Actual `dnf`/`git clone` calls are guarded behind a presence check so running it in CI/tests is safe.

- [ ] **Step 1: Write the failing test `tests/test_bootstrap.sh`**

```bash
#!/usr/bin/env bash
BOOT="$ATLAS_ROOT/bootstrap.sh"

assert_status "bootstrap parses (bash -n)" 0 bash -n "$BOOT"
assert_status "bootstrap --help exits 0"   0 bash "$BOOT" --help

out="$(bash "$BOOT" --help 2>&1)"
assert_contains "help mentions atlas install" "$out" "atlas install"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`bootstrap.sh` not found).

- [ ] **Step 3: Implement `bootstrap.sh`**

```bash
#!/usr/bin/env bash
# Atlas bootstrap — the only thing you run on a truly fresh machine.
# Ensures Git, fetches Atlas, and hands off to `atlas install`.
set -uo pipefail

ATLAS_REPO="${ATLAS_REPO:-https://github.com/thiva2k/atlas.git}"
ATLAS_HOME="${ATLAS_HOME:-$HOME/atlas}"

usage() {
  cat <<EOF
Atlas bootstrap

Prepares a fresh machine, then hands off to Atlas:
  1. ensure Git is installed
  2. clone Atlas into $ATLAS_HOME (if not already there)
  3. run:  cd $ATLAS_HOME && ./atlas install

Usage: bootstrap.sh [--help]
EOF
}

main() {
  case "${1:-}" in -h|--help) usage; return 0 ;; esac

  if ! command -v git >/dev/null 2>&1; then
    echo "git not found — installing (requires sudo)…"
    if command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y git
    else
      echo "no dnf available; install git manually and re-run" >&2
      return 1
    fi
  fi

  if [ ! -d "$ATLAS_HOME/.git" ]; then
    echo "cloning Atlas into $ATLAS_HOME…"
    git clone "$ATLAS_REPO" "$ATLAS_HOME"
  else
    echo "Atlas already present at $ATLAS_HOME — leaving it as is."
  fi

  echo
  echo "Bootstrap complete. Next:"
  echo "  cd $ATLAS_HOME && ./atlas install"
}

main "$@"
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_bootstrap.sh` all `ok`; suite `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh tests/test_bootstrap.sh
git -c commit.gpgsign=false commit -m "feat(bootstrap): add zero-dependency bootstrap entrypoint

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: Top-level docs + conventions + architecture reconciliation

**Files:**
- Create: `README.md`
- Create: `LICENSE` (MIT, 2026, thiva2k)
- Create: `CONTRIBUTING.md`
- Create: `CHANGELOG.md`
- Create: `docs/conventions.md`
- Create: `docs/module-authoring.md`
- Modify: `docs/architecture.md` (reconcile testing note: pure-Bash harness, not bats; and strict-mode wording)

**Interfaces:**
- Produces: the reader-facing documentation set. No code; the deliverable is that a new contributor can read `README.md` → `docs/architecture.md` → `docs/module-authoring.md` and understand the system and how to extend it in ~10 minutes.

- [ ] **Step 1: Write `README.md`**

```markdown
# Atlas

**Atlas is a workstation lifecycle manager.** It takes a fresh Fedora machine to
a fully configured engineering workstation — and keeps it that way: installing
and configuring tooling, verifying health, and backing up and restoring the
irreplaceable bits.

Atlas is not a migration script, a dotfiles repo, or a package installer.
Those are *capabilities*, expressed as modules.

## Quick start

```bash
# on a fresh machine
curl -fsSL https://raw.githubusercontent.com/thiva2k/atlas/main/bootstrap.sh | bash
cd ~/atlas
./atlas install
```

## Commands

| Command | Does |
|---|---|
| `atlas install` | ensure modules are present & configured |
| `atlas update`  | bring modules to their latest desired state |
| `atlas verify`  | check modules are healthy |
| `atlas backup`  | capture irreplaceable module state |
| `atlas restore` | re-apply captured state |
| `atlas doctor`  | diagnose the workstation |
| `atlas status`  | show what is / isn't installed |

## How it works

Everything is a **module** under `modules/<category>/<name>/`, and every module
implements the same lifecycle hooks. The `atlas` CLI dispatches a **platform
verb** to those modules through a small engine in `internal/`. Read
[`docs/architecture.md`](docs/architecture.md) for the full picture and
[`docs/module-authoring.md`](docs/module-authoring.md) to add one.

## Requirements

Bash, GNU coreutils, Git, and a Fedora base system. Nothing else.

## Status

v1 is the **skeleton**: the architecture, CLI, runner, and placeholder modules
are in place; real installation logic lands module by module. See
[`CHANGELOG.md`](CHANGELOG.md).

## License

MIT — see [`LICENSE`](LICENSE).
```

- [ ] **Step 2: Write `LICENSE`** — standard MIT text, `Copyright (c) 2026 thiva2k`.

- [ ] **Step 3: Write `CONTRIBUTING.md`**

```markdown
# Contributing to Atlas

## Principles

Simplicity over cleverness. One responsibility per file. Explicit over implicit.
Zero runtime dependencies beyond Bash + coreutils + Git. Documentation is part
of the change, not an afterthought.

## Ground rules

- Every shell file starts with `#!/usr/bin/env bash`.
- User-facing output goes through the `log::*` API — never bare `echo`.
- Shared helpers live in `internal/`; capabilities live in `modules/`.
- The runner must never reach inside a module — only call contract hooks.
- Line endings are LF (enforced by `.gitattributes`).

## Adding a module

See [`docs/module-authoring.md`](docs/module-authoring.md).

## Tests

Run the whole suite with:

```bash
bash tests/run.sh
```

Tests are pure Bash (no framework). Add `tests/test_<area>.sh` and use the
assertions in `tests/lib/assert.sh`. Every behavioural change ships with a test.

## Commits

Conventional commits (`feat:`, `fix:`, `docs:`, `test:`, …). Keep them small and
focused.
```

- [ ] **Step 4: Write `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to Atlas are documented here. Format loosely follows
[Keep a Changelog]; Atlas uses semantic versioning once it hits 1.0.

## [Unreleased]

### Added
- v1 skeleton: architecture, `atlas` CLI, module runner, and the `internal/`
  engine (logging, errors, OS helpers, module contract, dependency resolution).
- Eight placeholder modules across core / development / apps / desktop.
- Zero-dependency `bootstrap.sh`.
- Pure-Bash test harness under `tests/`.

[Keep a Changelog]: https://keepachangelog.com/
```

- [ ] **Step 5: Write `docs/conventions.md`**

```markdown
# Coding Conventions

These keep Atlas readable enough to understand in ten minutes.

## Bash

- `#!/usr/bin/env bash` on every script.
- Entry points: `set -uo pipefail`. Module hook subshells: `set -euo pipefail`.
- Quote expansions: `"$var"`, `"${array[@]}"`.
- Small functions, one job each. If a function needs a comment to explain a
  second responsibility, split it.
- No global mutable state beyond documented `ATLAS_*` variables.
- Prefer Bash builtins and coreutils; never add a runtime dependency.

## Naming

- Modules: `lower-kebab` directory names under a category.
- Functions: `snake_case`; namespaced APIs use `::` (`log::info`, `module::path`,
  `os::has_cmd`, `runner::run`). Module hooks are `module::<hook>`.
- Environment / globals: `UPPER_SNAKE`, prefixed `ATLAS_`.
- Private helpers: leading underscore (`_log_emit`, `_runner_run_module`).

## Output & errors

- All user output via `log::*`. Machine output (`--version`) may use `echo`.
- Fatal failures go through `die <code> <what> [why] [how]`.
- Exit codes are defined once in `internal/error.sh`.

## Files

- `internal/` = the engine, shared, module-agnostic.
- `modules/<category>/<name>/` = one capability, self-contained.
- Files that change together live together.
```

- [ ] **Step 6: Write `docs/module-authoring.md`**

````markdown
# Authoring a Module

A module is a self-contained capability. Adding one needs **no** change to the
runner — discovery is automatic.

## 1. Create the directory

```
modules/<category>/<name>/
```

Categories in v1: `core`, `development`, `apps`, `desktop`. The category is the
directory — nothing declares it.

## 2. Write `module.sh`

```bash
#!/usr/bin/env bash
MODULE_NAME="example"
MODULE_DESCRIPTION="One line: what this capability is."
MODULE_DEPENDS=()            # e.g. ("core/git"); ids are "category/name"

# Required hooks --------------------------------------------------------------

# 0 = already present & configured (install is skipped); non-0 = work needed.
module::check() {
  os::has_cmd example
}

# Make it so. Safe to run repeatedly.
module::install() {
  os::dnf_install example
}

# 0 = healthy; non-0 = broken (surfaced by `atlas verify` / `doctor`).
module::verify() {
  os::has_cmd example
}

# Optional hooks: module::update, module::remove, module::backup, module::restore
```

## 3. Add `config/` (optional)

Any files the module owns live in `config/` beside it — never in a shared
top-level directory.

## 4. Write `README.md`

Answer three questions: what it does, what it installs/configures, what it
depends on.

## 5. Test it

```bash
bash atlas status <category>/<name>
bash atlas install <category>/<name>
bash tests/run.sh
```

That's the whole contract. If you ever feel the need to reach into another
module's internals, the contract is missing something — extend the contract
instead.
````

- [ ] **Step 7: Reconcile `docs/architecture.md`**

In §5 change the `tests/` comment and in §9/§8 wording to match the built reality. Replace the line:

```
├── tests/                # contributor test suite (dev-only dependency)
```

with:

```
├── tests/                # pure-Bash test harness (no external framework)
```

And in §8 replace "Every entry point runs under `set -euo pipefail` plus an `ERR` trap installed by `internal/error.sh`." with:

```
- The `atlas` entrypoint runs under `set -uo pipefail` and propagates exit
  codes explicitly; each **module hook subshell** runs under `set -euo
  pipefail`. Fatal paths go through `die`.
```

Also update §12's bats-free reality if any mention remains (there is none — confirm).

- [ ] **Step 8: Verify the docs render and links resolve**

Run: `bash tests/run.sh` (still green) and manually confirm the referenced files exist:
`ls README.md LICENSE CONTRIBUTING.md CHANGELOG.md docs/conventions.md docs/module-authoring.md docs/architecture.md`
Expected: all listed, suite `0 failed`.

- [ ] **Step 9: Commit**

```bash
git add README.md LICENSE CONTRIBUTING.md CHANGELOG.md docs/
git -c commit.gpgsign=false commit -m "docs: add README, license, contributing, changelog, and guides

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 10: Push everything**

```bash
git push -u origin main
```

---

## Self-Review (completed by plan author)

**1. Spec coverage** — architecture.md §-by-§:
- §3 verbs + hooks → Tasks 7 (runner verb→hook map), 8 (CLI verbs), 9 (module hooks). ✔
- §4 zero-dep policy → Global Constraints + pure-Bash harness (Task 1), no framework. ✔
- §5 layout (`atlas bootstrap.sh internal/ modules/ docs/ tests/ assets/` + root docs) → Tasks 1–11. `assets/` has no content in v1 (nothing needs it yet — YAGNI); created lazily when a module ships an asset. Noted, not silently dropped.
- §6 module anatomy (module.sh/config/README) → Task 9. ✔
- §7 contract (metadata vars, `module::` hooks, return codes, subshell isolation) → Tasks 5, 6, 7, 9. ✔
- §8 error handling + exit codes → Task 3; reconciled wording Task 11. ✔
- §9 logging → Task 2. ✔
- §10 command flow → realized by Tasks 7–9; smoke-tested Task 9 Step 8. ✔
- §11 extension path → `docs/module-authoring.md` Task 11. ✔
- §12 v1 scope (skeleton, placeholders) → whole plan. ✔

**2. Placeholder scan** — module hooks intentionally call `not_implemented`; that is the *specified* v1 behaviour (§12), not a plan placeholder. No "TBD"/"implement later" as plan instructions; every code step has complete content.

**3. Type/name consistency** — verified across tasks: `log::debug|info|warn|error|step`, `die`, `ATLAS_EXIT_*`, `os::has_cmd|require_cmd|is_fedora|is_root|dnf_install|flatpak_install`, `module::discover|path|has_hook|deps_of|resolve_order`, `not_implemented`, `_runner_hooks_for_verb|_runner_run_module|runner::run`, `ATLAS_ROOT|ATLAS_MODULES_DIR|ATLAS_STATE_DIR|ATLAS_LOG_LEVEL|ATLAS_LOG_SCOPE`. Names match between definition and use.

**Note:** `assets/` is created only when a module first needs it (YAGNI). If you want the empty directory present now for structural completeness, add a `assets/.gitkeep` in Task 1.
