# Task 9 Report: The eight placeholder modules

## Summary

Created the eight placeholder modules per the brief (`core/git`, `development/{docker,claude,codex}`,
`apps/{brave,ghostty}`, `desktop/{kde,fonts}`), each with `module.sh` (metadata + `check`/`install`/`verify`
hooks) and a `README.md`. `core/git` additionally ships `config/gitconfig.template`. Wrote
`tests/test_modules.sh` first (TDD), confirmed RED, implemented the modules, confirmed GREEN
(suite 42 → 44 passed, 0 failed). Ran the end-to-end smoke test; found and documented a pre-existing
runner/module-contract interaction that makes the literal `atlas status && atlas install && atlas verify`
chain from the brief's Step 8 stop after `status` (see Concerns).

## TDD Evidence

### RED (Step 2)

Wrote `tests/test_modules.sh` exactly as given in the brief. First run:

```
test_modules.sh
  FAIL all eight modules discovered
       expected [apps/brave apps/ghostty core/git desktop/fonts desktop/kde development/claude development/codex development/docker] got [apps/beta core/alpha core/cyc_a core/cyc_b]
missing README: apps/beta
missing README: core/alpha
missing README: core/cyc_a
missing README: core/cyc_b
  FAIL every module satisfies the contract + has a README
       expected [0] got [1]

== 42 passed, 2 failed ==
```

**Root cause discovered:** `tests/run.sh` sources every `tests/test_*.sh` file into the *same* shell
process (not a subshell per file). `test_module_discovery.sh` and `test_module_order.sh` (which run
alphabetically before `test_modules.sh`) `export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"`
and never restore it, so that value leaked into `test_modules.sh`, which discovered the *fixture*
modules (`apps/beta`, `core/alpha`, `core/cyc_a`, `core/cyc_b`) instead of an empty real `modules/` dir.
Also, `internal/module.sh` guards itself against being sourced twice (`ATLAS_MODULE_SH` flag), so a
bare `unset ATLAS_MODULES_DIR` at the top of the test does not let the file's own `:=` default
re-apply on the second `source` within the same process — it causes an "unbound variable" error
under `set -u` instead.

**Fix (in `tests/test_modules.sh`, before sourcing `internal/module.sh`):** pin the variable directly
instead of relying on the (now unreachable) default:

```bash
export ATLAS_MODULES_DIR="$ATLAS_ROOT/modules"
```

This is a one-line addition to the test scaffolding described in the brief's comment ("uses real
ATLAS_MODULES_DIR ($ATLAS_ROOT/modules)") — it makes that comment true given the suite's actual
sourcing behavior. No production code (`internal/*.sh`) was touched.

With that fix and no `modules/` directory yet created, the RED run became clean:

```
test_modules.sh
  FAIL all eight modules discovered
       expected [apps/brave apps/ghostty core/git desktop/fonts desktop/kde development/claude development/codex development/docker] got []
  ok   every module satisfies the contract + has a README

== 43 passed, 1 failed ==
```

(`got []` — discovery empty, matching the brief's expected RED description.)

### GREEN (Step 7)

After creating all eight modules:

```
test_modules.sh
  ok   all eight modules discovered
  ok   every module satisfies the contract + has a README

== 44 passed, 0 failed ==
```

Full suite: 44 passed, 0 failed (was 42/42 before this task; +2 assertions from `test_modules.sh`).

## End-to-end smoke test (Step 8)

Ran each verb individually first (all exit codes captured):

```
$ bash atlas status ; echo STATUS_EXIT=$?
== atlas status (8 modules) ==
[apps/brave] check failed  ... (x8, one per module)
== done: 0 ok, 0 skipped, 8 failed ==
STATUS_EXIT=4

$ bash atlas install ; echo INSTALL_EXIT=$?
== atlas install (8 modules) ==
[each module] not yet implemented: <name> install
[each module] not yet implemented: <name> verify
== done: 8 ok, 0 skipped, 0 failed ==
INSTALL_EXIT=0

$ bash atlas verify ; echo VERIFY_EXIT=$?
== atlas verify (8 modules) ==
[each module] not yet implemented: <name> verify
== done: 8 ok, 0 skipped, 0 failed ==
VERIFY_EXIT=0
```

`install` and `verify` both print the expected `== atlas <verb> (8 modules) ==` step line and a
`done: 8 ok, 0 skipped, 0 failed` summary, and both exit 0, as the brief predicted.

`status` does **not** exit 0 — it exits 4 with `done: 0 ok, 0 skipped, 8 failed`. See Concerns for why,
and confirmation that the brief's literal chained command therefore stops after `status`:

```
$ bash atlas status && bash atlas install && bash atlas verify ; echo CHAIN_EXIT=$?
== atlas status (8 modules) ==
... (same 8 "check failed" lines) ...
== done: 0 ok, 0 skipped, 8 failed ==
CHAIN_EXIT=4
```

`install` and `verify` never ran under the literal `&&`-chained invocation because `status` returned
non-zero first.

## Files changed

- `tests/test_modules.sh` (new) — brief's TDD test verbatim, plus the one-line `ATLAS_MODULES_DIR`
  pin discussed above.
- `modules/core/git/module.sh`, `modules/core/git/config/gitconfig.template`, `modules/core/git/README.md`
- `modules/development/docker/module.sh`, `modules/development/docker/README.md`
- `modules/development/claude/module.sh`, `modules/development/claude/README.md`
- `modules/development/codex/module.sh`, `modules/development/codex/README.md`
- `modules/apps/brave/module.sh`, `modules/apps/brave/README.md`
- `modules/apps/ghostty/module.sh`, `modules/apps/ghostty/README.md`
- `modules/desktop/kde/module.sh`, `modules/desktop/kde/README.md`
- `modules/desktop/fonts/module.sh`, `modules/desktop/fonts/README.md`

## Self-review

- Exactly 8 modules, in the 4 categories specified: `core` (1), `development` (3), `apps` (2),
  `desktop` (2). Confirmed via `find modules -type f`.
- `module::discover` returns exactly the 8 expected ids, sorted: `apps/brave apps/ghostty core/git
  desktop/fonts desktop/kde development/claude development/codex development/docker`.
- All 8 `MODULE_DESCRIPTION` values verified verbatim against the brief via grep — exact match.
- Every module has `MODULE_NAME`, `MODULE_DESCRIPTION`, `MODULE_DEPENDS=()`, and the three hooks
  (`module::check` returns 1; `module::install`/`module::verify` call `not_implemented` and return 0
  via `not_implemented`'s own `return 0`).
- Every module has a `README.md` answering what it does / installs-configures / depends on, following
  the git template, ending with the "Status: placeholder" line.
- Only `modules/core/git/` has a `config/` directory (`gitconfig.template`, byte-for-byte from the
  brief). No other module has a `config/` dir.
- No production/internal engine files were modified — only `tests/test_modules.sh` (test) and the new
  `modules/` tree.

## Concerns

1. **`atlas status` does not exit 0 on a freshly-scaffolded (never-installed) system, contradicting
   the brief's Step 8 expectation.** `internal/runner.sh`'s `status` verb runs only the `check` hook,
   and — unlike the `install` verb, which special-cases `check` to mean "skip if already satisfied,
   otherwise continue" — the generic hook-execution path treats any non-zero `check` return as a hard
   failure (`log::error "$hook failed"; exit 1`). Since the brief's own module contract mandates
   `module::check() { return 1; }` for all eight placeholders (so the install path is exercised),
   `atlas status` necessarily reports all 8 modules as "failed" and exits 4 (`ATLAS_EXIT_MODULE`) —
   not 0. This means the brief's literal `bash atlas status && bash atlas install && bash atlas verify`
   stops after `status` and never runs `install`/`verify` in that one invocation (confirmed above).
   This is pre-existing behavior in `internal/runner.sh` from an earlier task, not something introduced
   by this task's modules, and `internal/runner.sh` is not listed in Task 9's `Files:` section — I did
   not modify it. Flagging for a decision: either (a) accept `status` reporting "not installed" modules
   as `failed`/non-zero-exit as intended semantics (in which case the brief's Step 8 wording needs
   correcting), or (b) file a follow-up task to make `status` a pure reporting verb (never a hard
   failure exit) separate from `install`'s pre-check semantics.
2. Ran each verb separately (not just via the `&&` chain) to get complete evidence for all three verbs
   despite the `status` exit code above; `install` and `verify` both behave exactly as the brief
   describes.
3. `advisor` tool was unavailable during this session (returned "advisor tool is unavailable, do not
   try to use it again"); proceeded on direct analysis of the runner/module contract instead.

## Addendum: follow-up fix — `status` no longer fails on not-installed modules

The Concern #1 above was resolved as its own targeted follow-up task. Fix applied to
`internal/runner.sh` (the only production file touched) plus a regression test in
`tests/test_runner.sh`.

### The change

In `_runner_run_module`'s hook loop, mirrored the existing `verb=install`+`hook=check`
special-case with a new `verb=status`+`hook=check` special-case, inserted immediately after
it and before the generic `module::has_hook "$hook" || ...` line:

```bash
      # status: report installed/not-installed via check; never a failure
      if [ "$verb" = "status" ] && [ "$hook" = "check" ]; then
        if module::has_hook check && module::check; then
          log::info "installed"
        else
          log::info "not installed"
          printf '__SKIP__'
        fi
        exit 0
      fi
```

An installed module now counts as "ok" (`module::check` succeeds, no `__SKIP__` token, hook
subshell exits 0). A not-installed module counts as "skipped" via the pre-existing `__SKIP__`
token contract the outer `runner::run` loop already understands. Either way the subshell
always exits 0 for the `status` verb, so `status` can never contribute to `fail` and
`runner::run status` always returns 0. No other verb's hook-failure semantics were touched —
`install`/`verify`/`update`/`backup`/`restore`/`doctor` still treat a failing hook as a real
failure.

### Regression test added (`tests/test_runner.sh`)

```bash
# status reports installed/not-installed and NEVER fails on a not-installed module
assert_status "status exits 0 on not-installed modules" 0 \
  runner::run status core/alpha apps/beta
out="$(runner::run status core/alpha apps/beta 2>&1 || true)"
assert_contains "status reports 'not installed'" "$out" "not installed"
```

Used explicit fixture ids (`core/alpha apps/beta`) rather than a no-args `runner::run status`,
per the brief, to avoid the `tests/fixtures/modules` directory's cyclic `core/cyc_a`/`core/cyc_b`
fixtures triggering the dependency-cycle die path unrelated to this fix.

### Suite totals: before → after

- Before this fix: **44 passed, 0 failed** (per the original Task 9 report above).
- After this fix: **46 passed, 0 failed** (+2 new assertions in `test_runner.sh`; no existing
  assertions changed or removed).

```
test_runner.sh
  ok   runner install succeeds on fixtures
  ok   runner rejects unknown verb
  ok   install reaches placeholder hook
  ok   satisfied module is skipped
  ok   failing module install returns exit 4
  ok   status exits 0 on not-installed modules
  ok   status reports 'not installed'

== 46 passed, 0 failed ==
```

### Step 8 end-to-end chain — now resolves the original Concern #1

```
$ bash atlas status && bash atlas install && bash atlas verify; echo "chain-exit=$?"
== atlas status (8 modules) ==
[apps/brave]  not installed
[apps/ghostty]  not installed
[core/git]  not installed
[desktop/fonts]  not installed
[desktop/kde]  not installed
[development/claude]  not installed
[development/codex]  not installed
[development/docker]  not installed
== done: 0 ok, 8 skipped, 0 failed ==
== atlas install (8 modules) ==
[apps/brave]  not yet implemented: brave install
[apps/brave]  not yet implemented: brave verify
[apps/ghostty]  not yet implemented: ghostty install
[apps/ghostty]  not yet implemented: ghostty verify
[core/git]  not yet implemented: git: dnf install git + apply config/gitconfig.template
[core/git]  not yet implemented: git: git --version and config sanity
[desktop/fonts]  not yet implemented: fonts install
[desktop/fonts]  not yet implemented: fonts verify
[desktop/kde]  not yet implemented: kde install
[desktop/kde]  not yet implemented: kde verify
[development/claude]  not yet implemented: claude install
[development/claude]  not yet implemented: claude verify
[development/codex]  not yet implemented: codex install
[development/codex]  not yet implemented: codex verify
[development/docker]  not yet implemented: docker install
[development/docker]  not yet implemented: docker verify
== done: 8 ok, 0 skipped, 0 failed ==
== atlas verify (8 modules) ==
[apps/brave]  not yet implemented: brave verify
[apps/ghostty]  not yet implemented: ghostty verify
[core/git]  not yet implemented: git: git --version and config sanity
[desktop/fonts]  not yet implemented: fonts verify
[desktop/kde]  not yet implemented: kde verify
[development/claude]  not yet implemented: claude verify
[development/codex]  not yet implemented: codex verify
[development/docker]  not yet implemented: docker verify
== done: 8 ok, 0 skipped, 0 failed ==
chain-exit=0
```

`atlas status` now prints per-module `not installed` lines, summarizes `done: 0 ok, 8 skipped,
0 failed`, and exits 0. The full `&&`-chained Step 8 command from the original brief now runs
all three verbs in one invocation and ends with `chain-exit=0`, resolving Concern #1 above.

### Commit

`internal/runner.sh` and `tests/test_runner.sh` committed together as
`fix(runner): status reports installed/not-installed instead of failing`.
