# Atlas — final whole-branch review fixes (feat/v1-scaffold)

## FIX A — runner must surface a resolve_order failure (cycle) instead of swallowing it

**File:** `internal/runner.sh`, inside `runner::run`.

Before:
```bash
  mapfile -t ids < <(module::resolve_order "${ids[@]}")
```

After:
```bash
  local _ordered
  _ordered="$(module::resolve_order "${ids[@]}")" || return $?
  mapfile -t ids <<<"$_ordered"
```

Why: `mapfile < <(...)` runs the producer in a process-substitution subshell whose
exit status is discarded, so a `die` (exit 3) inside `module::resolve_order` on a
dependency cycle never reached the caller — `runner::run` returned 0 regardless.
Command substitution (`$(...)`) preserves the subshell's exit status via `$?`, so
the failure now propagates through `runner::run` to the caller.

## FIX B — an unmet (missing/typo'd) dependency must be a fatal dependency error (exit 3)

**File:** `internal/module.sh`, inside `module::resolve_order`'s nested
`_module_visit` function.

Before: `_module_visit` went straight from `local id="$1" d` into the
`case "${_state[$id]:-}" in` cycle-detection logic, treating a nonexistent
module id as an ordinary (unvisited) leaf node — it would resolve into the
order list, and the failure would only surface later as a confusing "no such
file" error when the runner tried to source it.

After: added, immediately after `local id="$1" d` and before the `case` line:
```bash
    if [ ! -r "$(module::path "$id")" ]; then
      die "$ATLAS_EXIT_DEPENDENCY" \
        "unknown module: $id" \
        "a requested module or a declared dependency does not exist" \
        "check the id (category/name) and any MODULE_DEPENDS entries"
    fi
```

Why: this makes both a bogus explicit id and a bogus transitive dependency die
with the documented exit code 3 (`ATLAS_EXIT_DEPENDENCY`) at the point of
resolution, instead of degrading into an unrelated source/failure error later.
Combined with Fix A, this exit 3 now reaches the user through `runner::run`.

## FIX C — test isolation: stop env leaking across the single-shell harness

**Files:** `tests/run.sh`, `CONTRIBUTING.md`.

`tests/run.sh` sources every `test_*.sh` into one shell process. A test file
that does `export ATLAS_MODULES_DIR=<fixtures>` leaves that value in the
environment for every subsequent file, making correctness depend on
alphabetical test-file ordering.

Added to `tests/run.sh`, inside the `for t in "$ATLAS_ROOT"/tests/test_*.sh; do`
loop, right after the `printf '\n%s\n' "$(basename "$t")"` line and before
`ATLAS_TESTS_PASS=0 ATLAS_TESTS_FAIL=0`:
```bash
  # each test file starts from the real modules dir; files needing fixtures
  # override ATLAS_MODULES_DIR in their own body (sourced after this reset).
  export ATLAS_MODULES_DIR="$ATLAS_ROOT/modules"
```

Added to `CONTRIBUTING.md`, under "## Tests":
```markdown
> Test files are `source`d into one shell by `tests/run.sh`. `run.sh` resets
> `ATLAS_MODULES_DIR` to the real `modules/` dir before each file; a test that
> needs a fixtures dir must `export ATLAS_MODULES_DIR` itself (do not rely on a
> value left by another test file).
```

## FIX D — two documentation drifts in docs/architecture.md

1. §5 repository-layout tree — `error.sh` comment claimed traps that are not
   implemented.
   - Before: `# error handling, traps, exit codes (§8)`
   - After: `# error handling + exit codes (§8)`
2. §10 step 1 — flag example listed `--dry-run`, which is not implemented.
   - Before: `` parses global flags (`--verbose`, `--dry-run`, …) ``
   - After: `` parses global flags (`--verbose`, `--quiet`, …) ``

## New tests (prove Fix A and Fix B)

1. New fixture `tests/fixtures/modules_unmetdep/core/needy/module.sh` —
   declares `MODULE_DEPENDS=("core/ghost")`, a dependency that does not exist.
2. Appended to `tests/test_module_order.sh` two assertions that go through
   `runner::run` (the real user path):
   - `runner surfaces a dependency cycle as exit 3` — runs
     `runner::run install core/cyc_a` against `tests/fixtures/modules` and
     asserts exit status 3.
   - `runner surfaces an unmet dependency as exit 3` — runs
     `runner::run install core/needy` against
     `tests/fixtures/modules_unmetdep` and asserts exit status 3.

## Full suite result

```
== 51 passed, 0 failed ==
```
(49 pre-existing + 2 new; 0 failed.)

## End-to-end verification (real `atlas` CLI, not just tests)

**Cycle (Fix A):**
```
$ ATLAS_MODULES_DIR="tests/fixtures/modules" bash atlas install core/cyc_a; echo "cycle-exit=$?"
...ERROR  [atlas]  dependency cycle detected at 'core/cyc_a'
...ERROR  [atlas]    why: two or more modules depend on each other in a loop
...ERROR  [atlas]    fix: break the loop by editing a module's MODULE_DEPENDS
cycle-exit=3
```
Before Fix A this printed no cycle error and exited 0.

**Unmet dependency (Fix B):**
```
$ ATLAS_MODULES_DIR="tests/fixtures/modules_unmetdep" bash atlas install core/needy; echo "unmet-exit=$?"
...ERROR  [atlas]  unknown module: core/ghost
...ERROR  [atlas]    why: a requested module or a declared dependency does not exist
...ERROR  [atlas]    fix: check the id (category/name) and any MODULE_DEPENDS entries
unmet-exit=3
```

**Normal path sanity check:**
```
$ bash atlas install; echo "install-exit=$?"
...INFO  [atlas]  == atlas install (8 modules) ==
... (8 placeholder-hook warnings)
...INFO  [atlas]  == done: 8 ok, 0 skipped, 0 failed ==
install-exit=0
```

## Files changed

- `internal/runner.sh` (Fix A)
- `internal/module.sh` (Fix B)
- `tests/run.sh` (Fix C)
- `CONTRIBUTING.md` (Fix C)
- `docs/architecture.md` (Fix D)
- `tests/fixtures/modules_unmetdep/core/needy/module.sh` (new fixture)
- `tests/test_module_order.sh` (new tests)
