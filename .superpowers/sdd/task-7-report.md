# Task 7 Report — the runner (`internal/runner.sh`)

## Status: DONE_WITH_CONCERNS

One deliberate, documented deviation from the brief's literal test text was required
to reach a genuinely-passing suite (see "Deviation from brief" below). Everything else
was transcribed exactly.

## TDD Evidence

### RED

Files created first, exactly as the brief specifies:
- `tests/fixtures/modules_satisfied/core/sat/module.sh` (Step 2 fixture, verbatim)
- `tests/test_runner.sh` (Step 1 test, verbatim from the brief)

Command:
```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Output (relevant tail):
```
test_runner.sh
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_runner.sh: line 7: //wsl.localhost/Ubuntu/home/thiva/atlas/internal/runner.sh: No such file or directory
  FAIL runner install succeeds on fixtures
       exit 127, wanted 0
  FAIL runner rejects unknown verb
       exit 127, wanted 2
  FAIL install reaches placeholder hook
       [...] does not contain [not yet implemented]
  FAIL satisfied module is skipped
       [...] does not contain [already satisfied]

== 29 passed, 4 failed ==
```

Why it failed: `internal/runner.sh` did not exist yet, so `runner::run` was undefined
(`command not found`) — exactly the failure mode the brief predicted for Step 3.

### GREEN

Implemented `internal/runner.sh` exactly as given in the brief (Step 4 — byte-for-byte
transcription verified with `diff` against the brief's code block, modulo the fence
line).

Command:
```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Output (tail):
```
test_runner.sh
  ok   runner install succeeds on fixtures
  ok   runner rejects unknown verb
  ok   install reaches placeholder hook
  ok   satisfied module is skipped

== 33 passed, 0 failed ==
```

New suite total: **33 passed, 0 failed** (up from 29/29 before this task). Re-ran the
full suite a second time to confirm stability (`exit: 0`).

## Deviation from brief (and why)

The brief's Step 1 test text includes, verbatim:
```bash
assert_status "runner rejects unknown verb" 2 runner::run frobnicate
```

Running this literally (in-process, no subshell) causes `runner::run` to call `die`,
which calls `exit 2` directly. `assert_status` invokes `"$@"` as a plain command in the
*current* shell (redirection alone does not fork a subshell in bash), and `tests/run.sh`
`source`s each `tests/test_*.sh` file into itself. So the `exit 2` does not just fail
this one assertion — it terminates the entire `tests/run.sh` process immediately,
before the suite summary line is ever printed. I verified this in isolation:

```bash
$ bash -c 'f() { exit 5; }; f >/dev/null 2>&1; echo "after: $?"; echo "still running"'
$ echo "outer exit: $?"
outer exit: 5   # "after:"/"still running" never printed — the whole process died
```

Running the brief's test text unmodified against my (brief-exact) `runner::run`
reproduced exactly this: the suite stopped after the first `ok` line with
`bash tests/run.sh` itself exiting 2, never reaching `== N passed, M failed ==`.

The existing codebase already has the fix for this exact hazard: `tests/test_error.sh`
tests `die`'s exit behavior by wrapping the call in `bash -c '...'` ("run in a subshell
so it doesn't kill the test"). The brief's `test_runner.sh` text applies that pattern to
every other `die`-reaching path (the fixture-satisfied case, the placeholder-hook case)
but missed it for the "unknown verb" assertion specifically.

I changed only that one assertion to match the established convention:
```bash
# unknown verb is a usage error (run in a subshell so die's exit doesn't kill the suite)
assert_status "runner rejects unknown verb" 2 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/runner.sh"; runner::run frobnicate'
```
No other line of `tests/test_runner.sh` was changed, and `internal/runner.sh` was
implemented exactly as given (this is purely a test-harness fix, not a behavior
change — `runner::run frobnicate` → `die "$ATLAS_EXIT_USAGE" ...` → exit 2 is still
exactly what happens; only *how the test observes it* changed, matching the pattern
already used elsewhere in the suite).

I did not have advisor access to sanity-check this call (the tool reported itself
unavailable), so I'm flagging it explicitly as the reason for `DONE_WITH_CONCERNS`
rather than plain `DONE`, in case the task owner wants the literal brief text kept
and the test-runner infra changed instead (e.g. running each test file as a separate
`bash` process in `tests/run.sh` rather than `source`d) — that would be a larger,
cross-cutting change I did not make unilaterally.

## Files changed

- `internal/runner.sh` (new) — verbatim transcription of the brief's Step 4 code.
- `tests/test_runner.sh` (new) — the brief's Step 1 test, with the one subshell-wrap
  fix described above.
- `tests/fixtures/modules_satisfied/core/sat/module.sh` (new) — verbatim Step 2
  fixture.

## Self-review

- **Faithful transcription:** `internal/runner.sh` matches the brief's code block
  exactly (diffed, only the markdown fence line differs). `module.sh` fixture matches
  exactly.
- **`__SKIP__` token never leaks into a module's own hook output:** confirmed by
  design — `_runner_run_module` only ever `printf`s `__SKIP__` to stdout on the
  early-exit "already satisfied" branch, immediately followed by `exit 0`; the normal
  hook-invocation loop (`"module::$hook"`) never touches stdout itself, and module
  hooks (`not_implemented` → `log::warn`) write to stderr via `log::*`, not stdout. The
  captured `out="$(_runner_run_module ...)"` in `runner::run` is compared with
  `[ "$out" = "__SKIP__" ]` (exact match), so any incidental stdout from a real hook
  would *not* be misclassified as a skip unless a hook itself printed exactly
  `__SKIP__` to stdout, which none of the fixtures do.
- **Unknown verb exits 2:** confirmed — `runner::run frobnicate` → `die
  "$ATLAS_EXIT_USAGE" ...` → process exit 2, verified both by the (subshell-wrapped)
  automated test and by the earlier RED-phase raw failure text.
- **Satisfied module is skipped:** confirmed — the `core/sat` fixture (`module::check`
  returns 0) produces the `"already satisfied — skipping"` log line and is counted in
  `skip`, not `ok`.
- **Isolation subshell:** `_runner_run_module` wraps hook execution in
  `( set -euo pipefail; ATLAS_LOG_SCOPE="$id"; source "$(module::path "$id")"; ... )`,
  so a module's `set -e`/pipefail-triggered abort or stray variable leakage can't
  affect `runner::run`'s own shell state or other modules' runs.

## Concerns

1. The one test-line deviation described above (subshell-wrapping the "unknown verb"
   assertion) — flagging for task-owner awareness even though I believe it's the
   correct, minimal, convention-consistent fix and no implementation code was changed
   to accommodate it.
2. `advisor` tool was unavailable during this task ("The advisor tool is unavailable.
   Do not try to use it again."), so the deviation above did not get a second-opinion
   sanity check before I proceeded.

---

# Addendum — test-coverage gap closed: module-failure -> exit 4

## Status: DONE

## Gap

`internal/runner.sh`'s failure path is an explicit interface contract — "any module
hook failure → `runner::run` returns `ATLAS_EXIT_MODULE` (4)" — but no test exercised
it, because no fixture module failed a hook. This addendum adds a failing fixture and
one assertion so a regression in the failure-tally/return-4 path is caught.

## Files added/changed

- **New (fixture):** `tests/fixtures/modules_failing/core/fail/module.sh` — isolated
  fixture dir (mirrors `modules_satisfied/`, kept out of `tests/fixtures/modules/` so
  it can't affect other tests' discovery). `module::check()` returns 1,
  `module::install()` logs an error and returns 1, `module::verify()` is
  `not_implemented`.
- **Changed:** `tests/test_runner.sh` — appended one assertion after the existing
  "satisfied module is skipped" assertion, in the same `bash -c` subshell style (so
  `die`'s exit doesn't kill the whole suite process):
  ```bash
  # a module whose install hook fails makes runner::run return ATLAS_EXIT_MODULE (4)
  assert_status "failing module install returns exit 4" 4 \
    bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"; export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules_failing"; source "$ATLAS_ROOT/internal/module.sh"; source "$ATLAS_ROOT/internal/runner.sh"; runner::run install core/fail'
  ```

No changes were made to `internal/runner.sh` or any other file.

## Before -> after totals

- Before: `bash tests/run.sh` → **33 passed, 0 failed**.
- After: `bash tests/run.sh` → **34 passed, 0 failed** (`ok failing module install
  returns exit 4` appears under `test_runner.sh`).

## Meaningfulness proof

To prove the new assertion actually exercises the failure path (not passing for the
wrong reason), the fixture's `module::install()` was temporarily edited from
```bash
module::install() { log::error "deliberate failure"; return 1; }
```
to
```bash
module::install() { return 0; }
```
(install now succeeds, so the module should NOT fail). Re-running `bash tests/run.sh`
produced:
```
test_runner.sh
  ok   runner install succeeds on fixtures
  ok   runner rejects unknown verb
  ok   install reaches placeholder hook
  ok   satisfied module is skipped
  FAIL failing module install returns exit 4
       exit 0, wanted 4

== 33 passed, 1 failed ==
```
i.e. the new assertion FAILED (expected 4, got 0) and the suite reported 1 failed,
confirming the assertion is genuinely coupled to the failure-tally/return-4 behavior.

The fixture was then reverted to `log::error "deliberate failure"; return 1;`, and
`bash tests/run.sh` was re-run, confirming **34 passed, 0 failed** again.

## advisor note

`advisor` was unavailable in this session as well ("The advisor tool is unavailable.
Do not try to use it again.") — proceeded without a second-opinion check; the task was
narrow/mechanical (two files, exact text given) and the meaningfulness proof above
(deliberate-pass edit + revert) stands in as empirical verification.
