# Task 3 Report: Error handling + exit codes (`internal/error.sh`)

## Summary

Implemented `internal/error.sh` following strict TDD, exactly per the task
brief. Depends on `log::error` from Task 2 (`internal/log.sh`). Both new
files are byte-for-byte transcriptions of the brief's code blocks.

## TDD Evidence

### RED — Step 1 + 2

Wrote `tests/test_error.sh` (verbatim from brief), then ran:

```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Output (failure, as expected — `internal/error.sh` did not exist yet):

```
test_error.sh
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_error.sh: line 3: //wsl.localhost/Ubuntu/home/thiva/atlas/internal/error.sh: No such file or directory
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_error.sh: line 5: ATLAS_EXIT_USAGE: unbound variable
```

This matches the brief's expected RED exactly: the `source` of the
nonexistent `error.sh` fails, and the subsequent reference to
`$ATLAS_EXIT_USAGE` hits `set -u` (unbound variable) before `die` is even
reached — i.e., both "constants unbound" and "die: command not found"
failure modes are represented (the script aborts at the first one).

### GREEN — Step 3 + 4

Implemented `internal/error.sh` (verbatim from brief — source guard via
`ATLAS_ERROR_SH`, six readonly exit-code constants, and the `die` function
that calls `log::error` for what/why/how then `exit`s with the given code).

Ran:

```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Output (full suite, all green):

```
test_error.sh
  ok   usage exit code constant
  ok   module exit code constant
  ok   die uses the provided code
  ok   die prints what
  ok   die prints why
  ok   die prints how

test_harness.sh
  ok   assert_eq matches equal strings
  ok   assert_contains finds a substring
  ok   assert_status reads true's exit code
  ok   assert_status reads false's exit code

test_log.sh
  ok   info line has level
  ok   info line has message
  ok   info line has scope
  ok   debug suppressed at info level
  ok   scope override applies
  ok   logfile captured the line

== 16 passed, 0 failed ==
```

6 new tests (test_error.sh) + 10 prior tests (test_harness.sh, test_log.sh)
all pass. No regressions.

## Commit

```
git add internal/error.sh tests/test_error.sh
git -c commit.gpgsign=false commit -m "feat(internal): add exit codes and die() error helper

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

Result: `372f1a2 feat(internal): add exit codes and die() error helper`
(2 files changed, 34 insertions(+))

Branch `feat/v1-scaffold` history after commit:
```
372f1a2 feat(internal): add exit codes and die() error helper
36b7c19 feat(internal): add reusable logging engine
0f58379 test: add pure-Bash test harness and repo hygiene
```

Not pushed (per instructions).

## Files Changed

- `\\wsl.localhost\Ubuntu\home\thiva\atlas\internal\error.sh` (new, 18 lines)
- `\\wsl.localhost\Ubuntu\home\thiva\atlas\tests\test_error.sh` (new, 16 lines)

## Self-Review

- **Faithful transcription:** `git show 372f1a2` diff compared line-by-line
  against the brief's Step 1 and Step 3 code blocks — exact match, including
  the compact source-guard idiom
  (`[ -n "${ATLAS_ERROR_SH:-}" ] && return 0; ATLAS_ERROR_SH=1`), the six
  constant names/values, and the `die` body (local var defaults, the two
  conditional `log::error` calls for why/how, final `exit`).
- **Source guard correctness:** because the constants are `readonly`,
  double-sourcing `internal/error.sh` without the guard would throw
  `readonly variable` errors. The guard returns immediately on second
  source, matching Task 2's `log.sh` pattern (checked `internal/log.sh` uses
  the same idiom with `ATLAS_LOG_SH`).
- **No regressions:** full suite went from 10 passed/0 failed (Tasks 1-2
  baseline) to 16 passed/0 failed. No existing test output changed.
- **Pristine output:** `bash tests/run.sh` final line is
  `== 16 passed, 0 failed ==`, matching the required suite-summary format
  with no stray errors or warnings (the expected/harmless CRLF git warning
  did not appear in this run since these are new files, not converted
  existing ones).
- **Contract check for future tasks:** `die <code> <what> [why] [how]` is
  confirmed to (a) always log `what`, (b) conditionally log `  why: ...`
  when why is non-empty, (c) conditionally log `  fix: ...` when how is
  non-empty, (d) exit with the exact caller-supplied `code` — verified via
  `assert_status ... 3 ... die 3 "boom"` and the what/why/how
  `assert_contains` checks against captured stdout+stderr.

## Concerns

None. Implementation matches the brief exactly, TDD RED→GREEN cycle was
followed and evidenced, and the full suite passes with no regressions.
