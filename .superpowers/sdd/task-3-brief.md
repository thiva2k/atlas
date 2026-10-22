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

