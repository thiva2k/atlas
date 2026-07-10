# Task 3b — Git module: prepend the include block (fix the precedence defect)

## Why this task exists

Task 3 (`588796f`) shipped `modules/core/git/module.sh` with a real merge-blocking defect,
confirmed by an independent Opus review and adjudicated by a Fable architecture review.

`git config --global --add include.path "$frag"` **appends** — git writes a new
`[include]` section at the **bottom** of `~/.gitconfig`. Git resolves config positionally
(last value wins) and expands an include *at the position of the directive*. So the Atlas
fragment is read **last** and **overrides** anything the user set above it.

Concrete failure, verified on git 2.43.0: a user with

```ini
[pull]
	rebase = false
```

already in `~/.gitconfig` runs `atlas install`; afterwards `git config pull.rebase` → `true`.
Atlas silently reversed the user's explicit preference — while
`modules/core/git/config/gitconfig:2` tells them "your settings win".

This violates **RFC-0001 §4.4** ("the include is added near the top … Atlas provides
defaults, **the user always wins**") and the §9 decision-1 rationale that *chose*
`include.path` for exactly that property.

**Process ruling (Fable): this is an implementation defect, not a design change.**
RFC-0001 §4.4's mechanism sketch (`--add`) cannot deliver §4.4's own normative guarantee.
The guarantee is normative; the sketch is a bug in the example. **Do not write RFC-0002.**
Add an append-only errata note to RFC-0001 instead (see Step 5).

## Scope

`modules/core/git/module.sh`, `tests/test_module_git.sh`, `docs/rfcs/RFC-0001-git-module.md`
(errata note only — do NOT edit its accepted decisions), `CHANGELOG.md`.
Do **not** touch `internal/`, other modules, or `docs/architecture.md`.

## Environment — READ THIS FIRST

- Repo: WSL path `/home/thiva/atlas`. Work there.
- **WSL native Linux is the AUTHORITATIVE test environment.** Windows Git-Bash mangles
  POSIX sandbox temp paths (MSYS) and produces 3 spurious failures. Always verify with:
  `wsl.exe -d Ubuntu -e bash -lc 'cd /home/thiva/atlas && bash tests/run.sh'`
  (or, if you are already inside WSL, just `bash tests/run.sh`).
- Baseline: **70 passed, 0 failed.** Expect ~78–80 after this task.
- **No automated test may touch the real `$HOME` or run real `dnf`/`sudo`.** The existing
  `PRE` preamble in `tests/test_module_git.sh` sandboxes `HOME`, `GIT_CONFIG_GLOBAL`,
  `GIT_CONFIG_SYSTEM=/dev/null`, `ATLAS_CONFIG_HOME`, and mocks `os::dnf_install`. Keep it.
- **Assertions must run in the outer scope.** Atlas's harness has a known false-green bug:
  `assert_*` inside a `( … )` subshell silently loses the pass/fail counters. Pattern: run
  the thing under test in a child `bash -c`, assert on its exit status / stdout outside.
- Hooks run in a `set -euo pipefail` subshell. Every command that may legitimately return
  non-zero must sit on the left of `||`, inside an `if` condition, or be `|| true`'d.
- Commit with `git -c commit.gpgsign=false`, trailer
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Do not push.** The controller merges.

## TDD — write the failing tests first

Add to `tests/test_module_git.sh`. Run the suite and confirm the **new** tests fail (RED)
before writing implementation. Then implement, then confirm GREEN.

### Required regression tests (minimum)

1. **The reported failure (merge-blocking).** Pre-seed the sandbox `~/.gitconfig` with
   `[pull]\n\trebase = false`. Run `module::install`. Assert
   `git config --global --includes --get pull.rebase` = `false` (user preserved) **and**
   `git config --global --includes --get init.defaultBranch` = `main` (an unclaimed
   managed key still applies).
2. **User content preserved byte-for-byte.** Pre-seeded config → install → the file equals
   the `[include]` block followed by the *original* content, exactly (comments, ordering,
   whitespace intact).
3. **Idempotency on a pre-populated file.** Install twice → exactly one `include.path`
   line, and the file is byte-identical between run 1 and run 2.
4. **Fresh sandbox (no `~/.gitconfig`).** File is created, include present, managed keys
   resolve. (The existing tests already cover most of this — keep them passing.)
5. **Symlinked `~/.gitconfig`.** The symlink is preserved (still a symlink afterwards), the
   resolved target is rewritten, and the precedence assertion from test 1 holds through it.
6. **Mode preservation.** Pre-seeded config `chmod 600` → still `600` after install.
7. **Lock contention.** A pre-existing `<resolved-target>.lock` → `module::install` returns
   non-zero and the config file is **unmodified**.
8. **Migration from the appended layout.** Build a config where a user value sits *above* a
   bottom-appended Atlas `include.path` (i.e. the currently-shipped bad state) → run
   `module::install` → the include is relocated to the top, the user's value now wins, and
   there is still exactly **one** include line.

## Implementation

Replace step 3 of `module::install` (`module.sh:73-79`) with a helper, e.g.
`_git_ensure_include`, that guarantees the Atlas `[include]` block is the **first section**
of the effective global config.

**Target file:** `${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}`. **Never hardcode `~/.gitconfig`**
— doing so breaks the test sandbox and diverges from git's own file selection.

Algorithm:

1. Resolve the target. If it is a symlink, `readlink -f` it and operate on the resolved
   path (git does the same — it preserves the symlink and edits the target).
2. **Missing or empty target** → simply create it containing the `[include]` block. No
   rewrite of user data; skip the machinery below.
3. **Already correct** → if the Atlas include is present *and* the Atlas `[include]` is the
   first section (ignoring leading blank lines / comments), log and return 0. This keeps
   `install` idempotent and byte-stable.
4. **Present but not first** (migration) → `git config --global --fixed-value --unset
   include.path "$frag"` first, then prepend.
5. **Prepend, atomically:**
   - Take git's own lock: create `<resolved-target>.lock` with `set -C` (noclobber). If it
     already exists → die (never steal it). Release it (`rm -f`) on every exit path — use a
     `trap`.
   - Write `[include]` + `\tpath = <frag>` + a blank line + the original file content into a
     temp file **in the target's directory** (`mktemp` there, so `mv` is same-filesystem and
     therefore atomic).
   - `chmod --reference="$target" "$tmp"` to preserve mode (users keep 600 on gitconfigs).
   - `mv -f "$tmp" "$target"`.

`_git_include_present` stays as-is (it reads the literal `include.path` key from the file
git's `--global` scope reads, so it correctly does **not** pass `--includes`).

### Refuse-to-proceed conditions (`die`, exit `$ATLAS_EXIT_MODULE` = 4)

Every message must say **what** failed, **why**, and **how** to fix it (architecture §8).
Die rather than touch the file when:

1. The resolved target exists but is **not a regular file** (directory, FIFO, socket).
2. It is a **dangling symlink** whose target directory does not exist.
3. `<resolved-target>.lock` **already exists** — another writer is active, or a crash left
   it stale. Tell the user to remove it if stale. Never auto-steal.
4. The target, or its directory, is **unwritable**.
5. `git config --file <target> --list` **fails** — the file is unparseable by git. Atlas must
   never textually edit a file whose semantics it cannot verify.
6. **`EUID` is 0 and the target is not owned by root** (`sudo atlas install`) — rewriting
   would silently chown the user's config to root. Die with the correct invocation.

Note the hook contract: `die` from inside a hook subshell is fine — the runner catches the
exit status. But make sure the `trap` releases the lock before dying.

## Step 5 — docs

- `docs/rfcs/RFC-0001-git-module.md`: **append-only errata note** at the very bottom, under
  a new `## Errata` heading. One short paragraph: §4.4's `git config --add` sketch cannot
  satisfy §4.4's own placement guarantee, because `--add` appends and git resolves
  positionally; the implementation therefore prepends the `[include]` block. The guarantee
  ("the user always wins") is unchanged and normative. **Do not modify any existing line of
  the RFC**, and do not change its status.
- `CHANGELOG.md`: add an entry under `## [Unreleased]` → `### Fixed` describing the
  precedence defect and the fix in user-facing terms.

## Definition of done

- New tests written first and observed RED, then GREEN.
- `wsl.exe -d Ubuntu -e bash -lc 'cd /home/thiva/atlas && bash tests/run.sh'` → **0 failed**,
  total ≥ 78.
- Real `~/.gitconfig` provably untouched (`git config --global --get-all include.path` on the
  real user still returns nothing / its prior value).
- One focused commit. Do not push.

## Report back

Write `.superpowers/sdd/gm-task-3b-report.md` and end your final message with `DONE`,
`DONE_WITH_CONCERNS`, or `BLOCKED`. Include: final test counts, the exact commit SHA, any
deviation from this brief and why, and anything the reviewer should look at hardest.
