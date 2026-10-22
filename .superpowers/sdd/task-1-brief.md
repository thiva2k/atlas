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

