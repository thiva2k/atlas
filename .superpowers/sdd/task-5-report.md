# Task 5 Report: Module discovery + contract helpers (`internal/module.sh`)

## Status: DONE

## Summary

Implemented the discovery portion of the module-contract engine per the brief:
`ATLAS_MODULES_DIR`, `module::discover`, `module::path`, `module::has_hook`, and
the `not_implemented` placeholder-hook helper. Two fixture modules were created
under `tests/fixtures/modules/` (`core/alpha`, `apps/beta`). Dependency ordering
(`module::deps_of`, `module::resolve_order`) was deliberately NOT added — that is
Task 6, and the file only carries a trailing comment noting it's deferred.

## TDD Evidence

### RED (Step 3)

Command:
```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Relevant output (before `internal/module.sh` existed):
```
test_module_discovery.sh
//wsl.localhost/.../tests/test_module_discovery.sh: line 5: //wsl.localhost/.../internal/module.sh: No such file or directory
//wsl.localhost/.../tests/test_module_discovery.sh: line 7: module::discover: command not found
  FAIL discovers alpha
       [] does not contain [core/alpha]
  FAIL discovers beta
       [] does not contain [apps/beta]
//wsl.localhost/.../tests/test_module_discovery.sh: line 11: module::path: command not found
  FAIL path points at module.sh
       expected [.../tests/fixtures/modules/core/alpha/module.sh] got []
//wsl.localhost/.../tests/test_module_discovery.sh: line 15: module::path: command not found
  FAIL alpha defines install hook
       exit 127, wanted 0
  FAIL alpha lacks backup hook
       exit 127, wanted 1
  FAIL not_implemented warns
       [...: line 19: not_implemented: command not found] does not contain [not yet implemented]

== 20 passed, 4 failed ==
```

Why it failed: `internal/module.sh` did not exist yet, so sourcing it errored and
every function it should define (`module::discover`, `module::path`,
`module::has_hook`, `not_implemented`) was undefined — matching the brief's
expected failure (`module::discover: command not found`).

### GREEN (Step 5)

Command:
```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Output:
```
test_module_discovery.sh
  ok   discovers alpha
  ok   discovers beta
  ok   path points at module.sh
  ok   alpha defines install hook
  ok   alpha lacks backup hook
  ok   not_implemented warns
...
== 24 passed, 0 failed ==
```

All prior suites (test_error.sh, test_harness.sh, test_log.sh, test_os.sh)
remained green; full suite went from 20/20 to 24/24 passed, 0 failed.

## Files Changed

- `internal/module.sh` (new) — discovery portion of the module contract engine.
- `tests/test_module_discovery.sh` (new) — TDD test per brief, verbatim.
- `tests/fixtures/modules/core/alpha/module.sh` (new) — fixture module, verbatim.
- `tests/fixtures/modules/apps/beta/module.sh` (new) — fixture module, verbatim.

## Commit

`4bde4b3` — `feat(internal): add module discovery and contract helpers`
(branch `feat/v1-scaffold`, not pushed).

Staged/committed exactly: `internal/module.sh`, `tests/test_module_discovery.sh`,
`tests/fixtures/` (both fixture modules).

## Self-Review

- Faithful transcription: `internal/module.sh`, the test, and both fixture
  modules were written byte-for-byte from the brief's code blocks (diffed
  mentally against the brief while writing; no deviations).
- Confirmed `internal/module.sh` does **not** define `module::deps_of` or
  `module::resolve_order` — `grep -n "deps_of\|resolve_order" internal/module.sh`
  only matches the trailing comment line, not a function definition. Dependency
  resolution is correctly deferred to Task 6.
- `ATLAS_MODULES_DIR` defaults to `${ATLAS_ROOT:-.}/modules` and is overridden by
  the test via `export ATLAS_MODULES_DIR=.../tests/fixtures/modules` before
  sourcing `internal/module.sh`, exactly as the brief's interface describes.
- Idempotent source guard (`ATLAS_MODULE_SH`) mirrors the pattern from prior
  tasks' `internal/*.sh` files.
- `not_implemented` uses `log::warn`, consuming the already-completed
  `internal/log.sh` from Task 2 as specified in "Consumes".

## Concerns

None. The RED failure matched the brief's expected message, the GREEN run
shows the full suite at 0 failed, and the fixture modules / test file are
verbatim from the brief. `.superpowers/` remains untracked (pre-existing,
out of scope for this task's `git add`), and nothing was pushed.

---

## Follow-up Fix: subshell dropped `has_hook` assertions from suite totals

### Defect

The two `has_hook` assertions were run inside a `( … )` subshell:

```bash
( source "$(module::path core/alpha)"
  assert_status "alpha defines install hook" 0 module::has_hook install
  assert_status "alpha lacks backup hook"    1 module::has_hook backup )
```

`assert_status` increments `ATLAS_TESTS_PASS`/`ATLAS_TESTS_FAIL`, which are
plain shell variables owned by the process `tests/run.sh` sources each test
file into. Since `( … )` forks a real subshell, those increments happened in
the subshell's copy and were discarded on exit — the two assertions printed
`ok`/`FAIL` but contributed nothing to `ATLAS_TESTS_PASS`/`ATLAS_TESTS_FAIL`.
A regression in `module::has_hook` would print `FAIL` while the suite still
reported 0 failed and exited 0 (false green).

### Fix

Rewrote the block so `assert_status` runs in the outer scope (where the
counters live), while the module is still sourced in an isolated child
`bash -c` (inheriting the exported `ATLAS_ROOT`/`ATLAS_MODULES_DIR`) so its
hook definitions don't leak into the test runner:

```bash
# has_hook works after sourcing a module. Assert in the OUTER scope so the
# suite counters see the result; source the module inside a child bash -c so
# its hook definitions don't leak into the test runner.
_hh='source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/module.sh"; source "$ATLAS_MODULES_DIR/core/alpha/module.sh";'
assert_status "alpha defines install hook" 0 bash -c "$_hh"' module::has_hook install'
assert_status "alpha lacks backup hook"    1 bash -c "$_hh"' module::has_hook backup'
```

Only `tests/test_module_discovery.sh` changed; nothing else in the file was
touched.

### Before → After suite totals

- Before: `== 24 passed, 0 failed ==` (the two `has_hook` assertions ran but
  were not counted).
- After: `== 26 passed, 0 failed ==`, `exit=0` — the two recovered
  assertions now count toward the total.

### False-green proof

Command: `bash tests/run.sh` with `module::has_hook install` temporarily
changed to `module::has_hook bogus` (a hook that does not exist on the alpha
fixture, so the expected exit code 0 now mismatches):

```
test_module_discovery.sh
  ok   discovers alpha
  ok   discovers beta
  ok   path points at module.sh
  FAIL alpha defines install hook
       exit 1, wanted 0
  ok   alpha lacks backup hook
  ok   not_implemented warns
...
== 25 passed, 1 failed ==
exit=1
```

This confirms the fix is no longer false-green: a `module::has_hook`
regression is now caught by the suite total and a non-zero exit code.

The temporary change was then reverted (`bogus` → `install`), and the suite
was re-run to confirm it returned to green:

```
test_module_discovery.sh
  ok   discovers alpha
  ok   discovers beta
  ok   path points at module.sh
  ok   alpha defines install hook
  ok   alpha lacks backup hook
  ok   not_implemented warns
...
== 26 passed, 0 failed ==
exit=0
```

### Covering command

```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh; echo "exit=$?"
```

### Follow-up Fix Commit

`41257c9` — `fix(test): count has_hook assertions in the suite total
(subshell dropped them)` (branch `feat/v1-scaffold`, not pushed). Staged and
committed exactly `tests/test_module_discovery.sh`.
