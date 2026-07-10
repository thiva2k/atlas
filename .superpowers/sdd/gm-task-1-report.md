# Task 1 Report: Real `os::dnf_install` package primitive

## Status: DONE_WITH_CONCERNS

(Functionally complete, all green, but one file outside the brief's stated
list — `tests/test_os.sh` — had to be touched to keep the suite passing.
See "Deviation from brief" below.)

## TDD Evidence

### RED

Command:
```
bash tests/run.sh
```

Ran after creating `tests/test_os_dnf.sh` (exactly as given in the brief) but
before touching `internal/os.sh`. Relevant output:

```
test_os_dnf.sh
  ok   dnf_install returns 0 on success
  FAIL dnf_install runs dnf install for pkgs
       [] does not contain [dnf-called: install -y git curl]
  FAIL dnf_install propagates dnf failure
       exit 0, wanted 1
  ok   dnf_install no-op on empty args

== 53 passed, 2 failed ==
```

Why it fails: the placeholder `os::dnf_install() { log::info "would dnf
install: $*"; }` never calls the real (stubbed) `dnf` function, so the
`dnf-called: ...` marker never appears; it also always returns 0 (implicit
from `log::info`), so the "propagates dnf failure" case (which shadows `dnf`
to return 1) sees rc=0 instead of 1. The "no-op on empty args" and "returns 0
on success" cases pass trivially because the placeholder always returns 0 and
never touches `dnf`.

### GREEN

Command:
```
bash tests/run.sh
```

Ran after replacing the placeholder in `internal/os.sh` with the real
implementation from the brief. First run surfaced a collateral failure (see
Deviation section) — final run after fixing it:

```
test_os.sh
  ok   has_cmd true for bash
  ok   has_cmd false for nonesuch
  ok   require_cmd dies on missing

test_os_dnf.sh
  ok   dnf_install returns 0 on success
  ok   dnf_install runs dnf install for pkgs
  ok   dnf_install propagates dnf failure
  ok   dnf_install no-op on empty args

== 54 passed, 0 failed ==
```

Suite total: **54 passed, 0 failed** (baseline 51 + net +3 after removing the
one obsolete assertion and adding 4 new ones: 51 - 1 + 4 = 54).

## Files changed

- `internal/os.sh` — `os::dnf_install` replaced with the real implementation
  exactly as specified in the brief (guard on `$#`, `os::require_cmd dnf`,
  `sudo` only when not root, `log::info` intent, `dnf install -y "$@"`,
  `log::error` + `return 1` on failure). `os::flatpak_install` left untouched
  as a placeholder, per the brief.
- `tests/test_os_dnf.sh` (new) — written verbatim from the brief's Step 1.
- `tests/test_os.sh` (modified, **not listed in the brief's file list**) —
  removed the two lines that called the un-stubbed `os::dnf_install git curl`
  directly and asserted the old placeholder's log text. See deviation below.

## Deviation from brief: `tests/test_os.sh`

The brief's file list only names `internal/os.sh` (modify) and
`tests/test_os_dnf.sh` (new). Following the brief exactly through Step 4
produced **54 passed, 1 failed**, not the expected 54/0:

```
test_os.sh
  ok   has_cmd true for bash
  ok   has_cmd false for nonesuch
  ok   require_cmd dies on missing
  FAIL dnf_install logs intent
       [...ERROR... required command not found: dnf ...] does not contain [git curl]
```

Root cause: `tests/test_os.sh` (pre-existing, not part of this task) had:
```bash
out="$(os::dnf_install git curl 2>&1 || true)"
assert_contains "dnf_install logs intent" "$out" "git curl"
```
This called `os::dnf_install` **without stubbing `dnf`**, relying on the old
placeholder's harmless `log::info "would dnf install: ..."` behavior. Once
`os::dnf_install` is real, it calls `os::require_cmd dnf` first — and this
execution environment (WSL/Ubuntu, no `dnf` on PATH) dies with exit 5, so the
captured output is a "required command not found: dnf" error instead of the
package list. This isn't specific to my machine: the same failure would occur
on any non-Fedora machine (Debian/Ubuntu/macOS/etc.), so the pre-existing test
was implicitly assuming a placeholder that the task explicitly says to retire.

Fix: removed those two lines from `tests/test_os.sh` and left a one-line
comment pointing at `test_os_dnf.sh`, which already covers the same intent
(and more: success, failure, no-op) with proper `dnf`/`sudo` function-stubbing
so it never touches the real system, portable to any OS.

I judged this in-scope because leaving it in place means the suite is
permanently red on any machine without real `dnf` — inconsistent with the
task's own "watch it pass" success criterion (54 passed, 0 failed) and with
Atlas's cross-distro test philosophy (the new test's own header comment says
"safe on Fedora and non-Fedora alike"). I did not touch anything else in that
file. Flagging as a concern since it's a file the brief didn't list.

## Self-review

- Real implementation matches the brief byte-for-byte (guard, `os::require_cmd
  dnf`, conditional `sudo`, `log::info`/`log::error`, `dnf install -y "$@"`,
  `return 1` on failure). `os::flatpak_install` left as-is.
- `tests/test_os_dnf.sh` matches the brief's Step 1 verbatim.
- New test shadows `dnf` and `sudo` as shell **functions** inside `bash -c
  '...'` child processes — functions take precedence over PATH lookups, and
  each case runs in an isolated child bash, so stubs never leak into the
  suite shell and the real system package manager is never touched (verified:
  no `dnf` binary exists on this box at all, and the suite still passes,
  confirming the stubs are doing the work).
- Files touched: `internal/os.sh`, `tests/test_os_dnf.sh` (new),
  `tests/test_os.sh` (unplanned but necessary — see deviation above). No
  other files changed. `git status --short` confirms only these three are
  modified/added (plus a pre-existing untracked `.superpowers/` directory
  unrelated to this commit).
- Commit `cea00d1` includes all three files with a message documenting the
  `test_os.sh` deviation and rationale.

## Concerns

1. **Scope deviation**: `tests/test_os.sh` was modified even though the
   brief's file list didn't include it. Necessary to reach 54/0 (the brief's
   own stated target) on any non-Fedora dev box; flagging for reviewer
   awareness rather than silently going out of scope.
2. **Advisor tool was unavailable** during this session (`advisor()` returned
   "tool is unavailable. Do not try to use it again."), so the deviation
   above was resolved by direct investigation/judgment instead of a second
   opinion. Worth a human double-check given it touches a file outside the
   brief.
3. Not a concern but worth noting: this implementation is unverifiable
   end-to-end (real `dnf install`) on this WSL/Ubuntu machine since `dnf`
   doesn't exist here at all — correctness rests on the shadowed-function
   test technique plus code review of the 8-line implementation, not a live
   Fedora smoke test.
