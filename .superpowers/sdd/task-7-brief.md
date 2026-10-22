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

