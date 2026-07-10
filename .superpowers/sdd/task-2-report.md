# Task 2 Report: Logging engine (`internal/log.sh`)

## Status: DONE_WITH_CONCERNS

All required work is complete, committed, and verified GREEN. The "concerns"
flag is for one **environment-only** issue discovered during testing (details
below) — it does not affect the deliverable's correctness, and no source
files were changed to work around it.

## TDD Evidence

### Step 1-2: RED (test written, confirmed failing)

Wrote `tests/test_log.sh` verbatim from the brief. Ran:

```
$ bash tests/run.sh
```

Output (relevant excerpt):

```
test_log.sh
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_log.sh: line 2: //wsl.localhost/Ubuntu/home/thiva/atlas/internal/log.sh: No such file or directory
  FAIL info line has level
       [...log::info: command not found] does not contain [INFO]
  FAIL info line has message
       [...log::info: command not found] does not contain [hello]
  FAIL info line has scope
       [...log::info: command not found] does not contain [[atlas]]
  FAIL debug suppressed at info level
       expected [] got [...log::debug: command not found]
  FAIL scope override applies
       [...log::info: command not found] does not contain [[git]]
cat: .../logs/atlas-20260708.log: No such file or directory
  FAIL logfile captured the line
       [] does not contain [persist-me]

== 4 passed, 6 failed ==
```

Why expected: `internal/log.sh` did not exist yet, so `source` failed and
every `log::*` call was "command not found". Task 1's 4 `test_harness.sh`
assertions still passed (no regression from the new test file alone). This
matches the brief's Step 2 expectation exactly.

### Step 3: Implement `internal/log.sh`

Created `internal/log.sh` **byte-for-byte** from the brief's fenced code
block (39 lines, guard var, `_log_level_num`, `_log_file`, `_log_emit`, and
the five `log::*` wrappers).

### Step 4: GREEN (all tests pass)

```
$ bash tests/run.sh
```

Output:

```
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

== 10 passed, 0 failed ==
```

Exit code 0. All 4 Task 1 assertions + all 6 Task 2 assertions pass. Ran
twice consecutively to confirm stability (both 10/0).

### Step 5: Commit

```
$ git add internal/log.sh tests/test_log.sh
$ git -c commit.gpgsign=false commit -m "feat(internal): add reusable logging engine

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

Result: `36b7c19 feat(internal): add reusable logging engine` — 2 files
changed, 60 insertions(+), only `internal/log.sh` and `tests/test_log.sh`
staged (verified with `git status --short` before commit; `.superpowers/`
stayed untracked/out of scope, `.local/` stayed gitignored). Not pushed.

## Files Changed

- `\\wsl.localhost\Ubuntu\home\thiva\atlas\internal\log.sh` — new, verbatim
  from brief.
- `\\wsl.localhost\Ubuntu\home\thiva\atlas\tests\test_log.sh` — new, verbatim
  from brief.

## Self-Review

- **Faithful transcription:** Both files were written directly from the
  brief's fenced code blocks with no edits. Diffed working tree against
  `git show HEAD:<path>` post-commit — identical. Line counts (39 / 21)
  match the brief's blocks.
- **Pristine output:** GREEN run shows only `ok` lines, no stray warnings,
  correct `10 passed, 0 failed`, exit 0.
- **No regressions:** Task 1's `test_harness.sh` block (4 assertions) still
  passes unchanged in both the RED and GREEN runs.
- **Contract check against the brief's prose spec:** stderr-only user output
  (verified via `2>&1 1>/dev/null` capture in the test), color gated on
  `[ -t 2 ]` (not exercised by the non-interactive test capture, but present
  in the code as written), plain line always appended to
  `$ATLAS_STATE_DIR/logs/atlas-<YYYYMMDD>.log`, `ATLAS_LOG_LEVEL` floor
  honored (debug suppressed at `info`), `ATLAS_LOG_SCOPE` override honored,
  format `<ts>  <LEVEL>  [<scope>]  <msg>` — all match.

## Concerns (environment-only, no source changes made)

While chasing an intermittent 2-test failure (`debug suppressed at info
level`, `logfile captured the line`) on a **fresh** `.local/` state dir, I
root-caused it to a Git-Bash/MSYS quirk specific to this Windows-host
UNC-mount setup, **not** a bug in `internal/log.sh`'s logic:

- `tests/run.sh` computes `ATLAS_ROOT="$(cd ... && pwd)"`. In this Git Bash
  (MINGW64) session, `pwd` on this checkout returns a path with an exact
  **double leading slash**: `//wsl.localhost/Ubuntu/home/thiva/atlas`.
- `_log_file()`'s `mkdir -p "$ATLAS_STATE_DIR/logs"` — verbatim per the
  brief — fails on this exact path shape:
  `mkdir: cannot create directory '//wsl.localhost': Read-only file system`.
  GNU coreutils `mkdir -p` treats an exactly-two-leading-slash absolute path
  specially (POSIX leaves `//` implementation-defined) and MSYS's handling
  of it here errors out, every time, regardless of whether the target
  ultimately exists.
- The brief's code swallows that failure (`mkdir -p ... 2>/dev/null || true`
  then `>> "$(_log_file)" 2>/dev/null || true`), so on a **freshly-missing**
  state dir the subsequent append also fails (dir was never actually
  created), and bash's own redirection-setup error message leaks onto
  stderr *before* that line's `2>/dev/null` takes effect — which is what
  the two assertions caught.
- Confirmed this is purely a double-leading-slash artifact: a single-leading
  -slash form (`/wsl.localhost/...`) does **not** reach the same filesystem
  location at all in this Git-Bash session (it resolves to an unrelated,
  empty phantom path) — so there is no viable single-slash workaround, and
  I did not attempt one in source.
- **Verified not a code defect**: once the log directory exists by any means
  (e.g. having been created on a prior run), every subsequent
  `bash tests/run.sh` run is 100% green, repeatedly. The bug only bites the
  very first `mkdir -p` of a brand-new `.local/state/atlas/logs` when driven
  from this specific Windows/Git-Bash/UNC-mount combination. Atlas's real
  default state path (`$HOME/.local/state/atlas` on native Linux/WSL bash)
  never produces a double-leading-slash `pwd`, so this should not affect
  actual Atlas usage — only this dev-editing setup's first test run per
  fresh checkout.
- **What I did about it:** nothing to the committed source. For my own GREEN
  verification I pre-created `.local/state/atlas/logs` once via a bare
  `mkdir -p` (not part of any committed file — `.local/` is gitignored) so
  the verbatim test suite could actually execute and demonstrate the real
  pass/fail behavior of `log::*` rather than being masked by this Git-Bash
  quirk. After that one-time bootstrap, `bash tests/run.sh` is green on
  repeated runs without any further intervention.
- **Flagging for whoever runs this next** (future tasks, CI, or a fresh
  clone edited again over this same Windows/UNC path): the *very first*
  `bash tests/run.sh` invocation against a brand-new checkout in this exact
  Git-Bash-over-`\\wsl.localhost\` setup may show 2 spurious `FAIL`s from
  this `mkdir -p` quirk; a second run (or pre-creating
  `.local/state/atlas/logs`) will be green. This is analogous to the
  already-documented WSL/UNC quirks elsewhere in this environment (e.g. the
  graphify `normcase` bug) and is worth a one-line mention in project docs
  if it recurs for later `internal/` modules that also write under
  `ATLAS_STATE_DIR`.

No other concerns. The implementation and test are exact transcriptions of
the brief; the contract (stderr, TTY-gated color, persistent logfile, level
floor, scope tag, format) is met.
