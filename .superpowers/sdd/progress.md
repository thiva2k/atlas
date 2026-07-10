# Git module (RFC-0001) — progress ledger

Branch: feat/git-module
Plan: docs/superpowers/plans/2026-07-09-git-module.md
Baseline suite: 51 passed.

Task 1: os::dnf_install real (commit cea00d1). DONE_WITH_CONCERNS: also trimmed obsolete "dnf_install logs intent" assertion from pre-existing tests/test_os.sh (it tested placeholder behavior; real impl dies without dnf). Superseded by new stub-based test_os_dnf.sh. Review pending.
Task 1: COMPLETE (commit cea00d1, approved). Deviation OK: trimmed obsolete unsafe assertion from test_os.sh, superseded by test_os_dnf.sh; suite 51->54 verified. Note: brief file-list omitted test_os.sh (brief-authoring gap, reconciled).
Task 2: COMPLETE (commit 512ca51, approved; env.sh + entrypoint wiring, 54->59). Minors (plan-mandated, defer to final): unpaired-quote stripping can corrupt edge values; empty env var falls through to file; test does not cover last-wins/mismatched-quotes.
Task 3: git module core (commit 588796f). DONE_WITH_CONCERNS, both verified by controller:
  (1) REAL FIX: git config --global --get does NOT expand include.path without --includes; implementer added --includes to verify value-check + one test assertion (correct; _git_include_present reads the literal key so needs none). 
  (2) ENV DECISION: Git Bash/MSYS Windows-git mangles POSIX sandbox temp paths -> 3 git tests fail under Git Bash but PASS 70/70 under WSL native Linux. Atlas targets Fedora, so WSL is now the AUTHORITATIVE test env. Controller verified: git-bash 67/3, WSL 70/0, real ~/.gitconfig untouched. All future implementers/reviewers must verify via: wsl.exe -d Ubuntu -e bash -lc "cd /home/thiva/atlas && bash tests/run.sh".

## Task 3 review (Opus) — 2026-07-09
Verdict: **With fixes**. Confirmed strengths: idempotent install, set -e safe, airtight
sandbox, outer-scope assertions, `_GIT_MODULE_DIR` correct.
`--includes` deviation: **ACCEPTED AS-IS** — correct, minimal, applied only at the two
sites that read a value living inside the fragment; `_git_include_present` correctly
omits it; the two identity checks correctly omit it.
ONE BLOCKER: `git config --global --add include.path` APPENDS -> fragment read last ->
Atlas silently overrides a user's pre-existing `[pull] rebase = false`. Violates
RFC-0001 §4.4 ("near the top … the user always wins") and §9 decision 1's rationale,
and the fragment header comment lies to the user. Untested.

## BIG DECISION — include placement (reviewed by Fable) — 2026-07-09
**Verdict: Option A — prepend the `[include]` block at the top of
`${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}` via a guarded atomic rewrite.**
- Rejected B (invert the promise): hostile; destroys the reference-pattern value.
- Rejected C variants empirically: `~/.config/git/config` is invisible to
  `git config --global --list` when `~/.gitconfig` exists (verified, git 2.43.0), which
  would break `_git_include_present`, `verify`, and the `GIT_CONFIG_GLOBAL` sandbox; and
  it merely relocates the bug for XDG users. set-if-unset kills `update`/`remove`.
  `includeIf` has identical positional semantics.
- Verified on git 2.43.0: top-of-file `[include]` is legal and makes the user win;
  bottom-append makes Atlas win; `git config` through a symlinked `~/.gitconfig`
  preserves the symlink and edits the target; `--fixed-value --unset` works.

**RFC process ruling (Fable): NO RFC-0002.** RFC-0001 is internally inconsistent — its
§4.4 mechanism sketch (`--add`) cannot deliver its own §4.4 normative guarantee. The
guarantee is normative; the sketch is an example bug. Fix the code, add an **append-only
errata note** to RFC-0001 + a CHANGELOG entry. Superseding is for *changed decisions*;
no decision changed.

**Required implementation shape:** helper targets `${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}`
(never hardcode `~/.gitconfig`, or the sandbox breaks). Missing/empty file -> just create
it with the include block (no rewrite of user data). Otherwise: `readlink -f` to resolve
symlink; take git's own `<target>.lock` via `set -C` noclobber; write include block +
original content to a temp file **in the target's directory**; `chmod --reference`;
`mv -f` (atomic same-fs); release lock. Migration: if the include is present but the
Atlas `[include]` is not the first section, `--fixed-value --unset` it and re-prepend.

**Refuse-to-proceed (die, exit 4, what/why/how):** target not a regular file; dangling
symlink; `<target>.lock` already exists (never steal); target/dir unwritable;
`git config --file <target> --list` fails (unparseable — never textually edit it);
EUID 0 against a non-root-owned target.

**Required regression tests (min 9):** pre-seeded `pull.rebase=false` survives while
`init.defaultBranch` still applies; user content preserved byte-for-byte; idempotent on a
pre-populated file (one include line, byte-identical across runs); fresh sandbox; symlink
preserved + precedence holds through it; mode 600 preserved; pre-existing `.lock` ->
non-zero, file unmodified; migration from the bottom-appended layout; `remove` restores
original content (when that task lands).

## Task 3b — include prepend (implemented by controller after 2 subagent API deaths)
- ddbe109  prepend the include block; atomic mode-preserving lock-guarded rewrite;
           check+verify require the block be FIRST (runner skips install when check
           passes, so this is what makes a mis-installed config migrate itself).
           RFC-0001 errata (append-only) + CHANGELOG. Tests 70 -> 81.
- Opus review of ddbe109: "with fixes". 3 Important findings, ALL REAL:
  1. verify false-failed for the very users the fix protects (probed
     `--includes --get init.defaultBranch = main`; a user setting `master` below the
     include now wins, so verify called the module broken). Reproduced. Fixed by
     probing `--get-all` and asserting our value is PRESENT among resolved values.
  2. migration was 2 writes (git config --unset-all, then prepend) with a die
     reachable in between. Now ONE atomic write: awk strips the stale include line
     (literal compare; handles the old unquoted form) inside the same rewrite.
     Taking the lock is now the last fallible step -> no die after modification.
  3. 5 of 6 refuse-to-proceed guards untested. Added 4 (unparseable + byte-unchanged,
     dangling symlink, non-regular file, unwritable). All 5 verified to fire with
     their own distinct message, before any modification, leaving no lock/temp.
- a700b93  the above. Tests 81 -> 88, 0 failed.
- NOTE: reviewer suggested `trap ... RETURN` to release the lock. Tried it: the RETURN
  trap outlives the function and fires under `set -u` with $lock out of scope -> broke
  12 tests. Deliberately NOT used; invariant documented in the code instead.
- Also quoted the include path (git own writer quotes; a `#`/`;` in the path would
  otherwise be read as a comment).

## Task 4+5 + final review (branch complete)
- 6e86fd8  update/remove hooks + module README + conventions (atlas.env + "owning
           config a module does not own") + CHANGELOG. Guards/lock/rewrite factored
           into _git_guard_config/_git_lock/_git_rewrite_config so remove shares them.
           Writing remove exposed a real defect: strip left an orphan [include] header
           + blank line, so remove was not a clean revert. Fixed. 92 -> 103.
- FINAL whole-branch Opus review found 3 Important things 4 prior reviews missed:
  1. module::remove is UNREACHABLE -- architecture §3 defines a `remove` hook but no
     `remove` platform verb; runner has no case. RFC-0001 §11 claims it works.
  2. _git_ensure_include hardcoded the verb `install`, so `atlas update` printed
     "re-run 'atlas install git'".
  3. Tests ran under `set -uo pipefail`; production hooks run under `set -euo`.
     No test ever went through runner::run.
- BIG DECISION (Fable): the `remove` verb -> **Option B, do not add it in this PR.**
  It edits the frozen architecture + engine, and it is the first DESTRUCTIVE verb:
  bare `atlas remove` would tear down the whole workstation; teardown needs REVERSE
  topological order (remove a module before its deps); a module with no remove hook
  must emit a visible skip, not count as "ok". Project rule: engine/architecture
  changes start as their own RFC, written before the code. So: keep the hook, make
  claims honest (README "Hook" not "Verb" + note; CHANGELOG qualified; RFC-0001
  second append-only errata), open RFC-0002 (Proposed stub + index entry).
  Fable: no superseding RFC needed -- errata records status + a discovered gap,
  changes no accepted decision. §11 is met AT HOOK LEVEL.
  Fable also flagged for RFC-0002: refuse bare invocation (exit 2); reverse topo
  order; refuse removing a dep another installed module needs (exit 3); visible
  __SKIP__ for a module with no remove hook.
- Controller also found: every die "how to fix" line said `atlas install git`, but
  ids are `category/name` -- that command exits 3. Now `atlas $verb core/git`.
- Fixed: env::get leaked a trailing CR from a Windows-written atlas.env; module::remove
  guarded only when the include was present, so on an unparseable config it deleted
  the fragment and left a dangling include.path (silent half-revert) -- guards first now.
- 13091b1. Tests 103 -> 111, 0 failed. Test preamble now `set -euo pipefail` (matches
  runner) + 5 assertions through the real runner::run.
- e2e via real CLI: install/verify/update/status/doctor all ok on a seeded config;
  user pull.rebase=false preserved; real ~/.gitconfig untouched (include.path: none).

## Still owed after this branch
- RFC-0002 (platform verb `remove`) is a Proposed stub; needs a full draft + engine work.
- The EUID-0/non-root-owned guard is the one refuse-condition still untested (needs
  root/fakeroot).
- CONTRIBUTING should say the suite is verified on Linux/WSL, not Git Bash.
