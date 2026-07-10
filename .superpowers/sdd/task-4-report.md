# Task 4 Report: OS / environment helpers (`internal/os.sh`)

## Status: DONE

## TDD Evidence

### RED — Step 2

Command:
```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Output (relevant excerpt):
```
test_os.sh
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_os.sh: line 4: //wsl.localhost/Ubuntu/home/thiva/atlas/internal/os.sh: No such file or directory
  FAIL has_cmd true for bash
       exit 127, wanted 0
  FAIL has_cmd false for nonesuch
       exit 127, wanted 1
  FAIL require_cmd dies on missing
       exit 127, wanted 5
  FAIL dnf_install logs intent
       [//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_os.sh: line 11: os::dnf_install: command not found] does not contain [git curl]

== 16 passed, 4 failed ==
```

Why it failed: `internal/os.sh` did not exist yet, so sourcing it failed and none
of the `os::*` functions were defined — all four new assertions failed with
exit 127 / "command not found", exactly as expected before implementation.
The other 16 pre-existing tests (test_error.sh, test_harness.sh, test_log.sh)
still passed, confirming no pre-existing regressions.

### GREEN — Step 4

Command:
```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Output:
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

test_os.sh
  ok   has_cmd true for bash
  ok   has_cmd false for nonesuch
  ok   require_cmd dies on missing
  ok   dnf_install logs intent

== 20 passed, 0 failed ==
```

Full suite: 20 passed, 0 failed (16 prior + 4 new, no regressions).

## Files Changed

- Created `internal/os.sh` — `os::has_cmd`, `os::require_cmd` (dies via
  `die "$ATLAS_EXIT_UNSUPPORTED" ...`), `os::is_fedora` (reads
  `/etc/os-release`), `os::is_root`, and placeholder installers
  `os::dnf_install` / `os::flatpak_install` (log intent only).
- Created `tests/test_os.sh` — covers `has_cmd` true/false, `require_cmd`
  dying with exit code 5 in a subshell, and `dnf_install` logging its
  argument list.

## Commit

`9b40cc4` — `feat(internal): add OS detection and install placeholder helpers`
(2 files changed, 35 insertions(+))

## Self-Review

- **Faithful transcription:** `git show HEAD` diff compared byte-for-byte
  against the brief's Step 1 test and Step 3 implementation — identical,
  no deviations.
- **No regressions:** all 16 previously-passing tests (test_error.sh,
  test_harness.sh, test_log.sh) still pass unchanged.
- **Pristine output:** final `tests/run.sh` run shows `== 20 passed, 0 failed ==`
  with no stray warnings besides the expected/harmless git CRLF notice seen
  during `git add`/`git commit` (not present in this run's output).
- **`os::is_fedora` on this host:** per environment notes, this Windows
  Git-Bash host over the WSL UNC path has no `/etc/os-release`, so
  `os::is_fedora` correctly short-circuits via `[ -r /etc/os-release ] || return 1`
  and returns false here. The brief's test suite does not assert `is_fedora`
  true, so this is expected and not a gap — real Fedora hosts will exercise
  the `grep -qi '^ID=fedora$'` branch.
- **Idempotent sourcing guard:** `ATLAS_OS_SH` guard at the top matches the
  pattern used by `internal/log.sh` / `internal/error.sh` from prior tasks,
  so `os.sh` can be safely re-sourced (as it is, redundantly, inside the
  `require_cmd` death-test subshell).

## Concerns

None. Task 4 is complete, tests pass cleanly, and the implementation is an
exact transcription of the brief with no scope creep (install wrappers are
intentionally placeholder-only per the task description, real dnf/flatpak
logic deferred to later milestones).
