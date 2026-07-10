# Task 8 Report — CLI entrypoint (`atlas`)

## Status: DONE

## TDD Evidence

### RED (Step 2)

Command:
```
cd "//wsl.localhost/Ubuntu/home/thiva/atlas" && bash tests/run.sh
```

Relevant output (before `atlas` existed):
```
test_cli.sh
  FAIL help exits 0
       exit 127, wanted 0
  FAIL version exits 0
       exit 127, wanted 0
  FAIL unknown verb exits 2
       exit 127, wanted 2
  FAIL unknown option exits 2
       exit 127, wanted 2
  FAIL install on fixtures 0
       exit 127, wanted 0
  FAIL help shows usage
       [bash: //wsl.localhost/Ubuntu/home/thiva/atlas/atlas: No such file or directory] does not contain [Usage: atlas]
  FAIL help lists install
       [bash: //wsl.localhost/Ubuntu/home/thiva/atlas/atlas: No such file or directory] does not contain [install]
  FAIL version prints a number
       [bash: //wsl.localhost/Ubuntu/home/thiva/atlas/atlas: No such file or directory] does not contain [0.1.0]

== 34 passed, 8 failed ==
```

Why it failed: `atlas` did not exist yet, so `bash "$ATLAS"` (`$ATLAS_ROOT/atlas`) returned exit 127 ("No such file or directory") for every invocation — exactly the expected RED state ("atlas file not found").

### GREEN (Step 4)

Commands:
```
chmod +x atlas
bash tests/run.sh
```

Output:
```
test_cli.sh
  ok   help exits 0
  ok   version exits 0
  ok   unknown verb exits 2
  ok   unknown option exits 2
  ok   install on fixtures 0
  ok   help shows usage
  ok   help lists install
  ok   version prints a number

... (all prior 34 tests still ok, unchanged) ...

== 42 passed, 0 failed ==
```

New suite total: **42 passed, 0 failed** (up from 34/34 before this task; all 8 new `test_cli.sh` assertions pass, no regressions in `test_error.sh`, `test_harness.sh`, `test_log.sh`, `test_module_discovery.sh`, `test_module_order.sh`, `test_os.sh`, `test_runner.sh`).

## Hand smoke-check outputs (Step 5 in the task instructions)

```
$ ATLAS_MODULES_DIR=tests/fixtures/modules bash atlas --help
Atlas — workstation lifecycle manager (v0.1.0-dev)

Usage: atlas <command> [modules...] [options]

Commands:
  install    ensure modules are present & configured
  update     bring modules to their latest desired state
  verify     check that modules are healthy
  backup     capture irreplaceable module state
  restore    re-apply previously captured state
  doctor     diagnose the workstation
  status     show what is / isn't installed
  help       show this help
  version    show the version

Options:
  -v, --verbose   more output (debug level)
  -q, --quiet     less output (errors only)
      --version   print version and exit
  -h, --help      print this help and exit
exit=0

$ bash atlas --version
0.1.0-dev
exit=0

$ bash atlas frobnicate
2026-07-08T22:45:52  ERROR  [atlas]  unknown command: frobnicate
2026-07-08T22:45:53  ERROR  [atlas]    fix: run 'atlas --help'
exit=2
```

All three match the expected behavior: `--help` exits 0 and prints usage, `--version` exits 0 and prints `0.1.0-dev`, and an unknown verb exits 2 via `die`.

## Files changed

- `\\wsl.localhost\Ubuntu\home\thiva\atlas\atlas` — new file, the CLI entrypoint. Transcribed verbatim from the brief's Step 3 code block (resolves `ATLAS_ROOT` by following symlinks from `BASH_SOURCE[0]`, sources the five `internal/*.sh` engine files, defines `usage()`, and `main()` which parses `-v/--verbose`, `-q/--quiet`, `--version`, `-h/--help`, takes the first non-flag token as the verb and the rest as module ids, and dispatches `help`/`version` locally, the seven platform verbs (`install|update|verify|backup|restore|doctor|status`) to `runner::run`, defaults to `help` when no verb is given, and calls `die "$ATLAS_EXIT_USAGE" ...` (exit 2) for unknown options/verbs).
- `\\wsl.localhost\Ubuntu\home\thiva\atlas\tests\test_cli.sh` — new file, transcribed verbatim from the brief's Step 1 code block.

Committed as `452c816` — "feat(cli): add atlas entrypoint dispatching platform verbs" (2 files changed, 89 insertions). Only `atlas` and `tests/test_cli.sh` were staged; the untracked `.superpowers/` directory (containing this report and the task brief) was left alone as instructed.

Note: `git show --stat` reports `atlas` created as mode `100644` (not `100755`) — as flagged in the task's Environment section, the executable bit does not persist through this Windows/UNC filesystem checkout. This is expected and harmless: `chmod +x atlas` was run locally (confirmed `-rwxr-xr-x` via `ls -la` before the commit), and both the test suite and the hand smoke-checks invoke the script via `bash "$ATLAS"` / `bash atlas`, never `./atlas`, so the missing exec bit in git does not affect functionality.

## Self-review

- **`set -uo pipefail` intact, no `-e`:** confirmed via `grep -n "set -" atlas` → line 3 reads exactly `set -uo pipefail`. Not "hardened" with `-e`, as required so `runner::run`'s failure-tally-and-return-4 contract keeps working (an `out=$(...)` capture under `-e` would abort on a failing module instead of letting the runner tally and return 4).
- **Unknown verb/option → exit 2:** both paths call `die "$ATLAS_EXIT_USAGE" ...`; `test_cli.sh`'s `assert_status "unknown verb exits 2" 2 ...` and `assert_status "unknown option exits 2" 2 ...` both pass, and the hand smoke-check of `atlas frobnicate` printed the `die` error lines and returned exit 2.
- **help/version work:** both `--help`/`-h` and `--version` return 0 immediately inside the flag-parsing loop (before any verb dispatch), and the no-verb case (`${verb:-help}` defaulting to `help`) also routes to `usage`. Confirmed by both the test suite and the hand smoke-checks.
- **`ATLAS_ROOT` symlink resolution transcribed correctly:** the `while [ -h "$_src" ]; do ... done` loop plus the final `cd -P "$(dirname "$_src")" ... && pwd` matches the brief's Step 3 block character-for-character; diffed mentally against the brief while writing and no deviation was introduced.
- Runner exit codes propagate untouched: `install|update|verify|backup|restore|doctor|status)` calls `runner::run "$verb" "${rest[@]}"` as the final statement in that `case` arm, so `main`'s return code — and thus the script's exit code — is whatever `runner::run` returns (verified indirectly: `test_runner.sh`'s exit-4 test still passes, and `test_cli.sh`'s `install on fixtures 0` smoke test exercises the full path through `atlas` → `runner::run` → fixture modules).

## Concerns

None. Implementation is a verbatim transcription of the brief's Step 1 and Step 3 code blocks; TDD RED→GREEN evidence is clean (34→42 passed, 0 failed); all specified hand smoke-checks match expected output/exit codes; commit contains only the two intended files.
