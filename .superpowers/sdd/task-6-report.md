# Task 6 Report: Dependency resolution / topological order (`internal/module.sh`)

## Status: DONE

## Summary

Appended `module::deps_of` and `module::resolve_order` to `internal/module.sh`
(replacing the trailing "added in Task 6" placeholder comment), added two
cycle fixtures (`core/cyc_a`, `core/cyc_b`), and wrote
`tests/test_module_order.sh`, all transcribed verbatim from the task brief.
Followed strict TDD: fixtures + test written first, confirmed RED, then
implementation appended, confirmed GREEN.

## Files changed

- `internal/module.sh` — appended `module::deps_of` (reads `MODULE_DEPENDS`
  by sourcing the module file in a subshell) and `module::resolve_order`
  (DFS topological sort using nested function `_module_visit` and
  associative-array state `unset|temp|done`, cycle → `die "$ATLAS_EXIT_DEPENDENCY" ...`).
  Discovery code (`module::discover`, `module::path`, `module::has_hook`,
  `not_implemented`) left byte-for-byte untouched above the insertion point.
- `tests/fixtures/modules/core/cyc_a/module.sh` (new) — `MODULE_DEPENDS=("core/cyc_b")`
- `tests/fixtures/modules/core/cyc_b/module.sh` (new) — `MODULE_DEPENDS=("core/cyc_a")`
- `tests/test_module_order.sh` (new) — 3 assertions: `deps_of` reads
  `apps/beta`'s dep, `resolve_order apps/beta` orders `core/alpha` before
  `apps/beta`, and `resolve_order core/cyc_a` exits 3 on the cycle.

## TDD evidence

### RED

Command:
```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Relevant output (fixtures + test existed, functions did not yet exist in
`internal/module.sh`):
```
test_module_order.sh
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_module_order.sh: line 7: module::deps_of: command not found
  FAIL beta declares its dep
       expected [core/alpha] got []
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_module_order.sh: line 10: module::resolve_order: command not found
  FAIL dependency comes before dependent
       expected [core/alpha apps/beta ] got []
  FAIL cycle detected as exit 3
       exit 127, wanted 3

== 26 passed, 3 failed ==
```
Why it failed: `module::deps_of` and `module::resolve_order` were not yet
defined in `internal/module.sh` (only the placeholder comment existed), so
all three new assertions failed exactly as the brief predicted — command not
found, empty output, exit 127 (not the expected 3). This matches Step 3's
documented expectation.

### GREEN

Command (same, after appending the two functions):
```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Output:
```
test_module_order.sh
  ok   beta declares its dep
  ok   dependency comes before dependent
  ok   cycle detected as exit 3

== 29 passed, 0 failed ==
```
New suite total: **29 passed, 0 failed** (26 pre-existing + 3 new from
`test_module_order.sh`). All other pre-existing test files
(`test_error.sh`, `test_harness.sh`, `test_log.sh`,
`test_module_discovery.sh`, `test_os.sh`) still pass unchanged.

## Commit

```
c1ac19f feat(internal): resolve module dependencies with cycle detection

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```
4 files changed, 72 insertions(+), 1 deletion(-):
- `internal/module.sh`
- `tests/fixtures/modules/core/cyc_a/module.sh`
- `tests/fixtures/modules/core/cyc_b/module.sh`
- `tests/test_module_order.sh`

Not pushed (per instructions).

## Self-review

- **Faithful transcription:** `git diff` of `internal/module.sh` was
  compared line-by-line against the brief's Step 4 code block — identical,
  including comment text, variable names (`_state`, `_order`, nested
  function `_module_visit`), the `set +u` subshell trick in `deps_of`, and
  the `< <(module::deps_of "$id")` process substitution. No "improvements"
  were made.
- **Cycle test genuinely exits 3:** confirmed via the GREEN run —
  `assert_status "cycle detected as exit 3" 3 bash -c '...'` passed, and
  manually inspecting the harness (`die()` in `internal/error.sh` calls
  `exit "$code"` with `ATLAS_EXIT_DEPENDENCY=3`) confirms the mechanism is
  real, not a stubbed pass.
- **Discovery code untouched:** `git diff` shows only an addition after the
  existing `module::has_hook` line; lines 1-22 of the original file are
  unchanged (verified via `git show HEAD~1:internal/module.sh` shape vs.
  current file before the diff was applied — the diff hunk starts strictly
  after `module::has_hook`).
- Fixtures (`core/cyc_a`, `core/cyc_b`) are also picked up by
  `module::discover` (any `*/*/module.sh` under `ATLAS_MODULES_DIR`) —
  this did not break `test_module_discovery.sh`, which only asserts on
  `alpha`/`beta` specifically and still passes.

## Concerns

None. Implementation matches the brief exactly, TDD cycle was followed
(RED confirmed before GREEN), and the full suite is green at 29/29 with no
regressions to prior tasks' tests.
