# Task 3 report — Git module core: fragment + check/install/verify + identity

## Status: DONE_WITH_CONCERNS

One necessary, minimal deviation from the brief's literal text was required to make the suite
pass against a real git binary (see "Deviation from the brief" below). Everything else follows
the brief exactly.

## Environment note

The Bash tool in this session is Windows Git-Bash (MSYS), not WSL bash, even though the repo
lives at the UNC path `//wsl.localhost/Ubuntu/home/thiva/atlas`. Running the sandboxed tests
through Git-Bash's git.exe hit MSYS's automatic POSIX→Windows path mangling: `mktemp -d`
produces a path like `/tmp/tmp.XXXX`, but MSYS git rewrites that to `C:/Users/.../Temp/tmp.XXXX`
when it's stored as an `include.path` config value, so the module's own POSIX-path comparison in
`_git_include_present` never matched what `git config --get-all include.path` returned. This is
a property of running an MSYS git binary against POSIX-style temp paths, not a bug in the module
or the test.

I switched to invoking the suite via real WSL (`wsl.exe -d Ubuntu -e bash -lc '...'`, native git
2.43.0, native `/tmp`) for all test runs from Step 4 onward. That is the correct environment for
this project (Fedora/dnf-oriented Bash tool) and matches what `bash tests/run.sh` is meant to
mean here. All RED/GREEN evidence below is from that real-WSL run.

## TDD evidence

### RED (Step 4, real WSL, placeholder hooks)

```
test_module_git.sh
  ok   git check unsatisfied before install
  FAIL git check satisfied after install
       exit 1, wanted 0
  FAIL git install writes the managed fragment
       exit 1, wanted 0
  FAIL git init.defaultBranch resolves to main
       expected [main] got []
  FAIL git install is idempotent (one include line)
       expected [1] got [0]
  FAIL git identity set from env
       expected [Ada Lovelace] got []
  ok   git existing identity not clobbered
  FAIL git install succeeds without identity
       exit 127, wanted 0
  FAIL git install calls dnf when git absent
       [...module.sh: line 7: not_implemented: command not found] does not contain [DNF:git]
  FAIL git verify fails before install
       exit 127, wanted 1
  FAIL git verify passes after install
       exit 127, wanted 0

== 61 passed, 9 failed ==
```

9 failures, exactly matching the brief's expectation that "nearly every git assertion fails."
(2 pass vacuously: `check` returns 1 unconditionally so "unsatisfied before install" trivially
holds, and "existing identity not clobbered" only asserts a value nothing in the placeholder
touches.)

### Deviation from the brief

Real git (`git config --global --get`/`--get-all`) does **not** expand `include.path` by
default. Per `git-config(1)`, include expansion (`--includes`) defaults to **on** only when
reading the merged/unscoped config; it defaults to **off** the moment an explicit file/scope
selector (`--global`, `--system`, `--local`, `--file`) is given, unless `--includes` is passed
explicitly. I verified this empirically and repeatedly against the real git binary in WSL
(git 2.43.0-1ubuntu7.3), including with `GIT_CONFIG_GLOBAL` explicitly set:

```
$ git config --global --get user.name        # user.name lives only in an included file
(empty, exit 1)
$ git config --global --includes --get user.name
Test User                                    # exit 0
$ git config --get user.name                 # unscoped resolution: includes on by default
Test User                                    # exit 0
```

This means:
- The brief's test assertion `git config --global --get init.defaultBranch` — meant to check
  "a managed value resolves through the include" — cannot pass for *any* correct
  implementation, because the value only exists in the included fragment.
- The brief's own `module::verify()` has the identical defect: its
  `git config --global --get init.defaultBranch` check would never see "main" even when the
  config is genuinely effective.

I fixed both by adding `--includes` (`git config --global --includes --get init.defaultBranch`)
in `module::verify()` (`modules/core/git/module.sh`) and in the one test assertion that reads a
value through the include (`tests/test_module_git.sh`, "git init.defaultBranch resolves to
main"). This is the minimal change that realizes the stated intent of both the test's own
comment and `verify()`'s own error message ("managed config not effective"), without touching
anything else — the mandatory sandbox preamble (`PRE`, HOME/GIT_CONFIG_GLOBAL/
GIT_CONFIG_SYSTEM/ATLAS_CONFIG_HOME isolation + `os::dnf_install` mock) is untouched, and no
assertion's pass/fail semantics changed. `_git_include_present` (which reads `include.path`
itself, a top-level key, not a value living inside the included file) needed no such fix and
was unaffected.

The advisor tool was unavailable this session ("The advisor tool is unavailable. Do not try to
use it again."), so I made this call directly, backed by the reproducible empirical evidence
above, and am flagging it explicitly as the reason for DONE_WITH_CONCERNS rather than DONE.

### GREEN (Step 6, real WSL, after fix)

```
test_module_git.sh
  ok   git check unsatisfied before install
  ok   git check satisfied after install
  ok   git install writes the managed fragment
  ok   git init.defaultBranch resolves to main
  ok   git install is idempotent (one include line)
  ok   git identity set from env
  ok   git existing identity not clobbered
  ok   git install succeeds without identity
  ok   git install calls dnf when git absent
  ok   git verify fails before install
  ok   git verify passes after install

== 70 passed, 0 failed ==
```

All 11 new git assertions pass; `test_modules.sh` ("all eight modules discovered" / "every
module satisfies the contract + has a README") still passes, confirming git still exposes the 3
required hooks + README + metadata. Suite total: 59 (pre-existing) + 11 (new) = **70 passed, 0
failed**, matching the brief's target exactly.

## Sandbox isolation confirmed (real HOME untouched)

After the full test run:

```
$ md5sum /home/thiva/.gitconfig
63d2251978c175f5a75ba42c9bf6975a  /home/thiva/.gitconfig
$ grep -i atlas /home/thiva/.gitconfig
no atlas references in real .gitconfig - confirmed clean
$ ls /home/thiva/.config/atlas/
ls: cannot access '/home/thiva/.config/atlas/': No such file or directory
```

No Atlas `include.path` line, no `~/.config/atlas/` directory — the real user environment was
never touched. Every git assertion in `tests/test_module_git.sh` runs inside `bash -c "$PRE..."`
with a fresh `mktemp -d` `HOME`, `GIT_CONFIG_GLOBAL="$HOME/.gitconfig"`,
`GIT_CONFIG_SYSTEM=/dev/null`, and `ATLAS_CONFIG_HOME="$HOME/.config/atlas"`, cleaned up via
`trap "rm -rf \"$HOME\"" EXIT`; `os::dnf_install` is mocked to a no-op printf, so no real `dnf`
ever ran.

## Files changed

- `modules/core/git/config/gitconfig` (new) — the managed fragment, exact content/tabs from the
  brief's Step 1 (verified with `cat -A`: `defaultBranch`, `rebase`, `default`,
  `autoSetupRemote`, `prune`, `autostash`, `ui` all tab-indented).
- `modules/core/git/config/gitconfig.template` (deleted via `git rm`, brief Step 2).
- `modules/core/git/module.sh` (rewritten) — brief's Step 5 implementation verbatim, except the
  one `--includes` addition in `module::verify()` described above.
- `tests/test_module_git.sh` (new) — brief's Step 3 test verbatim, except the one `--includes`
  addition in the "git init.defaultBranch resolves to main" assertion, with an added comment
  explaining why.

## Self-review

- Fragment content: byte-exact match to the brief, tabs preserved (confirmed via `cat -A`
  showing `^I` before every key line, not spaces).
- Template deleted via `git rm` as instructed; commit shows `delete mode 100644
  modules/core/git/config/gitconfig.template`.
- Sandbox never touches real `HOME`/`~/.gitconfig`/`~/.config/atlas`/dnf — confirmed above by
  hash comparison and directory-absence check post-run, and by construction (every assertion
  runs in a `bash -c` child with fresh `mktemp -d` HOME + mocked `os::dnf_install`).
- Hooks match the brief exactly: `module::check`/`module::install`/`module::verify` with the
  same structure, log messages, and control flow, aside from the one `--includes` fix in
  `verify()`.
- `set -e` safety: the module itself relies on explicit `||` short-circuits (`... || { log::error
  ...; return 1; }`) rather than `set -e`, matching the brief's style; the test's `PRE` preamble
  sets `set -uo pipefail` (not `-e`) per the brief, unchanged.
- Idempotency verified directly by the "git install is idempotent (one include line)" assertion
  (calls `module::install` twice, asserts exactly one `include.path` line) and by the fragment
  write being an unconditional `cp -f` (Atlas owns the file, so overwrite is safe and
  idempotent) while the `include.path` add is guarded by `_git_include_present`.
- Identity handling verified non-blocking (installs succeed with no `ATLAS_GIT_USER_NAME/EMAIL`
  set) and set-only-if-unset (pre-existing `user.name` is never clobbered) by the corresponding
  assertions, both passing.

## Concerns

1. **The `--includes` deviation** (above) is the main concern — it is a deliberate, minimal,
   well-evidenced fix to a real defect in the brief's own test and reference `module::verify()`
   code (both would be permanently broken against real git without it), not a shortcut or
   weakening. It does not touch the mandated sandbox preamble. Worth a second pair of eyes/an
   advisor pass in a follow-up session given the advisor tool was down for this one.
2. Test execution had to go through real WSL (`wsl.exe -d Ubuntu -e bash -lc ...`) rather than
   the Bash tool's default Git-Bash, because Git-Bash's MSYS git mangles POSIX temp paths into
   Windows paths, breaking the sandboxed git-config comparisons in a way unrelated to the module
   under test. Future tasks in this repo that touch `git config` from the Bash tool should route
   through `wsl.exe -d Ubuntu` the same way to avoid re-discovering this.
3. `.superpowers/` is untracked in the working tree (pre-existing, unrelated to this task) and
   was intentionally left out of the commit.

## Commit

`588796f` — `feat(git): implement check/install/verify with owned config fragment + identity`
(4 files changed: `modules/core/git/config/gitconfig` new, `modules/core/git/config/
gitconfig.template` deleted, `modules/core/git/module.sh` modified, `tests/test_module_git.sh`
new). Not pushed.
