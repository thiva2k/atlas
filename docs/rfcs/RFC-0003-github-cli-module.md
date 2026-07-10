# RFC-0003: GitHub CLI Module

| | |
|---|---|
| **Status** | Proposed |
| **Author** | Claude Code (for thiva2k) |
| **Created** | 2026-07-09 |
| **Revised** | 2026-07-10 (empirical `gh` probe; owner rulings on config immutability and backup) |
| **Phase / order** | Phase 1 — Foundation · module 2 of 16 |
| **Depends on** | `core/git` (RFC-0001) |
| **Establishes** | How Atlas handles **credentials** and **unattended authentication** |

---

## 1. Summary

Implement `modules/development/github-cli` — install the `gh` CLI, initialise a
default configuration **only on a fresh `gh` install**, and (only when the user
has supplied a token) authenticate non-interactively. `gh auth login` is
interactive by design; Atlas must run unattended. This RFC decides exactly where
that line falls.

Git is a prerequisite because `gh` is useless without it and because `gh`'s
`git_protocol` setting only makes sense once Git exists.

Because GitHub CLI is the first module to touch **secrets**, this RFC sets the
precedent every later credentialed module inherits (Docker registries, Claude
Code, Codex): **Atlas never prompts, never stores a secret it was not given, and
never fails an install because a credential is absent.**

## 2. Motivation

The Definition of Done for the production sprint explicitly allows "minimal manual
authentication steps where security demands it (for example GitHub login)". This
RFC pins down what "minimal" means so it is a design decision rather than an
accident of implementation.

## 3. Goals / Non-goals

**Goals**
- Install `gh` on Fedora, idempotently.
- Initialise `git_protocol` **on a fresh `gh` configuration only**; never mutate
  an existing one.
- Authenticate from a token the user supplied out-of-band, if one exists.
- Report auth state clearly in `verify` / `doctor` without failing on its absence.
- Establish the credential-handling precedent (§4.4) and the secret-resolution
  primitive `env::get_secret` (§4.5).

**Non-goals**
- No interactive `gh auth login` (Atlas runs unattended).
- No writing, printing, or logging of the token value, ever.
- No management of GitHub Enterprise hosts in v1.
- No `gh extension` management.
- No migration or reset of an existing `gh` configuration (§4.6).

## 4. Design

### 4.1 Module layout

```
modules/development/github-cli/
├── module.sh
└── README.md
```

No `config/` directory: unlike `core/git`, this module owns no config *file* —
`gh` has no include mechanism and Atlas writes nothing of its own (§4.6).

Category `development/`, id **`development/github-cli`**. Binary is `gh`; the
module id is spelled out so `atlas install development/github-cli` reads clearly.

### 4.2 Metadata

```bash
MODULE_NAME="github-cli"
MODULE_DESCRIPTION="GitHub's official CLI: installs gh and configures it for this workstation."
MODULE_DEPENDS=("core/git")
```

`core/git` is a hard dependency: the runner's topological sort guarantees Git is
installed and configured before `gh` runs.

### 4.3 Package source

`gh` ships in Fedora's **official repositories**, verified 2026-07-09 against
`packages.fedoraproject.org`: Fedora 43 carries `gh` 2.87.3, Fedora 44 carries
2.94.0. Atlas therefore uses `os::dnf_install gh` and adds **no third-party
repo**. This keeps the zero-extra-trust posture and needs no new engine primitive.

If a future Fedora release drops the package, `install` fails the ordinary way —
the hook returns non-zero and `os::dnf_install`'s error surfaces. It does **not**
exit `5` (unsupported platform): Fedora *is* supported; a package is merely
missing. Nor does Atlas silently fall back to a third-party repo. Adding one is a
trust decision, and trust decisions belong in an RFC, not in an error path.

### 4.4 Credentials — the precedent (the important part)

`gh` stores auth in `$GH_CONFIG_DIR/hosts.yml` (default `~/.config/gh/`), written
by `gh auth login`. That command is interactive. Atlas resolves a token through
the existing `env::get` chain (RFC-0001 §4.5) — environment first, then
`$ATLAS_CONFIG_HOME/atlas.env` — hardened as `env::get_secret` (§4.5).

**Atlas's token key is `ATLAS_GH_TOKEN` and nothing else.** `GH_TOKEN` /
`GITHUB_TOKEN` are *gh's* variables, not Atlas's; their meaning is settled in the
next paragraph rather than by adding them to the resolution chain.

Auth resolution, in order:

1. **`GH_TOKEN` or `GITHUB_TOKEN` is exported in the environment** → `gh` is
   already authenticated, from the environment, for the life of that environment.
   Atlas logs this and **does nothing else**. This is not a preference: `gh auth
   login --with-token` *refuses to run* in this state ("The value of the GH_TOKEN
   environment variable is being used for authentication"). Ephemeral env-based
   auth counts as authenticated for `check` and `verify`, and the README says
   plainly that it vanishes with the shell.
2. **Already authenticated on disk** (`gh auth token >/dev/null 2>&1` succeeds) →
   log it, change nothing. A working login is user-owned state and is never
   overwritten.
3. **Not authenticated, `ATLAS_GH_TOKEN` resolvable** → `gh auth login
   --with-token` reading the token **from stdin**, never from a command-line
   argument (argv is world-readable in `/proc`) and never echoed to a log.
4. **Not authenticated, no token** → `log::warn` with the exact command to run
   (`gh auth login`), and **return success**. A missing credential is not an
   install failure, exactly as a missing Git identity is not (RFC-0001 §4.5).

`verify` mirrors this: unauthenticated is a **warning**, not a failure. `gh` is
installed and healthy without a login; only the user can grant it access.

Consequences adopted as the standing rule for every credentialed module:

- Atlas never prompts for a secret.
- Atlas never writes a secret into a file it owns, and never into the repo.
- A secret reaches Atlas only via the environment or `atlas.env` (mode `600`,
  gitignored, the user's file).
- A secret is never passed as a command-line argument and never logged.
- **No Atlas code path may run under `set -x`.** Tracing expands arguments and
  would print a secret straight to stderr; modules must not enable xtrace, and
  `env::get_secret` disables it for its own duration (§4.5).
- Absent credentials degrade to a warning, never a failed install.

#### The `gh auth token` hazard

`gh auth token` **prints the token on stdout**. It is used here solely as an
*offline predicate*, and must only ever be invoked as:

```sh
gh auth token >/dev/null 2>&1
```

Its output is never captured, never interpolated, never logged. `gh auth status`
is not used at all: its exit code is version-dependent (observed rc `0` when
logged out on gh 2.45.0, rc `1` on 2.93.0), so it cannot be a reliable probe.

### 4.5 `env::get_secret` — a hardened resolver

Reading a secret is not the same as reading a preference, so it gets its own
primitive rather than a comment on `env::get`. This mirrors RFC-0001's precedent
of landing a shared engine primitive (`os::dnf_install`) inside the module branch
that first needs it.

```
env::get_secret <NAME>
```

Identical resolution to `env::get`, plus:

- **xtrace is disabled** for the function body and restored on exit, so a caller
  running under `set -x` cannot leak the value.
- **When the value would come from `atlas.env`, that file's mode is checked.** If
  it is group- or world-readable, the secret is **not consumed**: `env::get_secret`
  logs a warning naming the file and the fix (`chmod 600`) and returns non-zero,
  i.e. the secret is treated as absent. Atlas refuses to make a leaked credential
  load-bearing. A value taken from the *environment* is not mode-checked; the
  environment is the caller's problem.
- The value is returned on stdout and nowhere else.

`env::get` is untouched; non-secret keys (`ATLAS_GIT_USER_EMAIL`) keep using it.

### 4.6 Managed configuration — fresh-init only

`gh` has **no include mechanism**. Unlike Git, there is no way to layer an
Atlas-owned fragment beneath the user's `config.yml`, so RFC-0001 §4.4's pattern
cannot be reused. Atlas will not hand-edit YAML it does not own, and Atlas's
dependency policy forbids pulling in `yq`.

The original design was "set the key if unset". **A probe against real `gh`
disproved it** (gh 2.45.0 on Ubuntu/WSL, gh 2.93.0 on Windows, 2026-07-09):

| Observation | Consequence |
|---|---|
| `gh config get git_protocol` on a fresh `GH_CONFIG_DIR` prints `https`, rc `0` | "unset" is **not observable**. `gh` reports its default indistinguishably from a user's explicit choice. Set-if-unset is unimplementable. |
| `gh config get` does not create `config.yml`; `gh config set` does | The **existence of `config.yml`** is an observable "this user has configured gh" signal. |

The owner's ruling, adopted here:

> Atlas configures GitHub CLI only when initializing a fresh GitHub CLI
> configuration. Existing user configuration is immutable unless the user
> explicitly requests migration or reset.

Therefore:

- `install` applies the managed key **iff `$GH_CONFIG_DIR/config.yml` does not
  exist**, using `gh`'s own writer (`gh config set git_protocol ssh`). Atlas
  never parses or edits the YAML itself.
- If `config.yml` exists, `install` logs that `gh` is already configured and
  leaves it alone. Every subsequent run — including the run immediately after
  Atlas's own first — takes this branch, because Atlas's own `gh config set`
  created the file.
- `update` therefore does **no** configuration work. There is no re-apply, and no
  reconciliation loop.
- No migration or reset path exists in v1. Adding one is a behaviour change and
  needs its own RFC.

*Considered and dropped:* an Atlas-owned stamp file recording what `install` set,
so `update` could re-apply the value when it still matched the stamp. Under the
immutability ruling nothing reads the stamp, and the frozen architecture forbids
new abstractions that no requirement needs.

The managed set is exactly one key. See §9 decision 3.

### 4.7 `gh auth setup-git` — deliberately NOT run

`gh auth setup-git` writes `credential.helper` entries into the user's global Git
config, through `gh`'s own writer. Two independent reasons to decline:

1. It is **configuration this module does not own**. `docs/conventions.md` permits
   editing a file another module owns only under the validate-then-write, atomic,
   revertible discipline `core/git` implements. An edit made by `gh`'s writer is
   none of those things: Atlas cannot validate it, cannot track it, and cannot
   revert it. It would also mean `development/github-cli` mutating `core/git`'s
   owned file — the explicit safety rule against modifying another module's
   configuration.
2. It is **unnecessary** under `git_protocol=ssh` (§9 decision 3): Git pushes over
   SSH and needs no credential helper.

HTTPS users can run `gh auth setup-git` themselves; the README says so.

This is the reference example of a module **declining** to do something convenient
because it would cross a module boundary.

### 4.8 Hook contracts

**`check`** — satisfied iff:

```
os::has_cmd gh  AND NOT ( token-resolvable AND not-authenticated )
```

where "not-authenticated" is the offline probe `gh auth token >/dev/null 2>&1`
failing. Read the second clause as: *if there is work `install` can do, `check`
must fail.* When the user has supplied a token and `gh` is not logged in, Atlas
can and should act, so `check` fails and the runner runs `install`. When no token
exists, `install` cannot help, so `check` passes and the runner skips it — the
warning is emitted by `verify` instead.

Managed configuration is **deliberately excluded** from `check`, in explicit
contrast to `core/git`. There, `check` asserts the include is *first* precisely
so a stale config re-migrates on the next run — anything `check` asserts must be
something `install` can fix. Here, an existing `config.yml` is immutable by
ruling: `install` *cannot* fix a `git_protocol` the user changed, so asserting it
would fail `check` forever with no path to green.

**`install`** —
1. `os::has_cmd gh` || `os::dnf_install gh`
2. if `config.yml` is absent → `gh config set git_protocol ssh`; else log and skip
3. authenticate per §4.4; a resolvable token that `gh` *rejects* is a hard failure

Returns non-zero only on a real failure (package install, or a rejected token).

**`verify`** — `gh --version` succeeds. Auth state is *reported*: authenticated →
`info`; not → `warn`. Never fails on auth.

> **Engine gap.** The runner's per-module outcome is `ok` / `skip` / `fail`; a
> warning is invisible in the summary line. "Installed but unauthenticated" is
> exactly the state a `doctor` run should surface. This is a whole-system defect,
> not a `github-cli` one, and needs its own RFC. Noted, not worked around.

**`update`** — no-op beyond a log line. Package currency is the OS's job
(RFC-0001 §3); configuration is immutable (§4.6); auth is user-granted.

**`remove`** — **no hook.** There is nothing to revert: Atlas wrote no file it
owns, and it must not delete a credential the user granted, a `config.yml` it
cannot prove it authored, or a package other tools depend on. The runner skips a
hook a module does not define. The reasoning lives in the README, where a reader
looking for it will actually be; a hook body that only logs "I do nothing" is
noise in the module contract. (No `remove` platform verb exists yet in any case —
RFC-0002.)

**`backup` / `restore`** — explicit **no-op hooks**, each logging why. `gh`'s only
persistent state is `hosts.yml`, which contains a live OAuth token. Atlas will not
copy credentials around: regenerating a token is cheap, leaking one is not.

Per the owner's ruling this is scoped, not universal:

> Keep the generic `backup` / `restore` platform verbs. Implement real
> backup/restore in the SSH module as the first concrete implementation, but do
> not special-case SSH in the runner. The runner remains generic and fans out to
> every module. Modules without persistent state implement no-op hooks. The backup
> artifact must contain only module-owned state and should be encrypted locally.

So the precedent this RFC sets is narrow: **a module may decline to back up state
only when that state is a cheaply-regenerable credential.** `core/ssh` (RFC-0004)
holds state that is *not* regenerable — a lost private key is a lost identity —
and will implement real, locally-encrypted backup/restore as the reference for
every stateful module after it. A module that omits `backup` because backing up
is *awkward* is a bug, not a precedent.

> *Follow-up:* `core/git` (RFC-0001) omits `backup`/`restore` entirely rather than
> defining no-op hooks. That predates this ruling and is a documentation-level
> inconsistency, not a behavioural one — the runner treats an undefined optional
> hook and a no-op hook identically. It is folded into RFC-0004's branch, where
> the backup contract is written.

## 5. Idempotency & fail-safety

- Re-running `install` on a configured, authenticated box changes nothing and
  logs why.
- A rejected token fails `install` loudly (non-zero) rather than leaving the user
  believing they are logged in.
- No hook ever writes to `~/.gitconfig`, `~/.ssh`, or any other module's files.
- No hook parses or rewrites `config.yml`; `gh` is the only writer.

## 6. Testing

Same sandbox discipline as RFC-0001, extended for a binary Atlas does not own:

- `HOME`, `GH_CONFIG_DIR`, `ATLAS_CONFIG_HOME` → fresh `mktemp -d`.
- `GH_TOKEN` and `GITHUB_TOKEN` explicitly unset unless a test is exercising §4.4
  case 1.
- `os::dnf_install` mocked.
- **`gh` is mocked as a shell function** (functions take precedence over `PATH`),
  recording both its **argv** and its **stdin** to files, so tests can assert what
  was asked of it *and* that the token arrived intact on stdin.
- Tests run under `set -euo pipefail` (the runner's flags) and drive the module
  through `runner::run`, per the precedent set at the end of RFC-0001's branch.
- No test may run real `dnf`, real `gh`, or touch the real `$HOME`.

Required assertions:

- token reaches `gh` on **stdin**, and appears **nowhere** in recorded argv;
- token absent → `install` succeeds, warns, exit 0;
- `GH_TOKEN` exported → no `gh auth login` invocation at all; treated as authed;
- already authenticated on disk → auth untouched;
- `config.yml` present → no `gh config set` invocation;
- `config.yml` absent → exactly one `gh config set git_protocol ssh`;
- second `install` run → no `gh config set` (the file Atlas's own run created);
- `atlas.env` mode `640` → secret not consumed, warning emitted, install still
  succeeds;
- `gh auth token` is never invoked with its stdout captured;
- `verify` warns but passes when unauthenticated;
- `check` fails when a token is resolvable and `gh` is logged out; passes when no
  token is resolvable.

### 6.1 Assumptions about `gh`'s contract

The mock encodes behaviour observed on **gh 2.45.0 (Ubuntu/WSL)** and **gh 2.93.0
(Windows)**, 2026-07-09:

1. `gh config get <key>` prints the default and returns `0` for an unset key.
2. `gh config get` does not create `config.yml`; `gh config set` does.
3. `gh auth token` returns non-zero, offline, when no credential is stored — and
   **prints the token** when one is.
4. `gh auth status` exit code is not stable across versions.
5. `gh auth login --with-token` refuses when `GH_TOKEN` is exported.

A mocked `gh` proves Atlas's logic, not `gh`'s. **Named follow-up gate before the
v1.1 tag:** one manual pass of `atlas install development/github-cli` against real
`gh` on the clean Fedora acceptance box, recorded in the production-readiness
report. If any assumption above breaks on Fedora's `gh`, the mock and this section
are wrong together and must be corrected together.

## 7. Documentation

`modules/development/github-cli/README.md`, plus a `docs/conventions.md` section
codifying §4.4's credential rules and `env::get_secret` for all future modules.

## 8. Alternatives considered

- **Upstream `gh` dnf repo.** Rejected: Fedora packages `gh`; a third-party repo
  adds trust and an engine primitive for nothing (§4.3).
- **Atlas-owned `config.yml` fragment.** Impossible: `gh` has no include.
- **Hand-merging the user's YAML.** Rejected: needs a YAML parser; Atlas's
  dependency policy forbids `yq`.
- **Set-if-unset via `gh config get`.** Rejected: empirically impossible (§4.6).
- **Atlas-owned stamp file + reconcile on `update`.** Rejected: no consumer under
  the immutability ruling (§4.6).
- **`gh auth status` as the auth probe.** Rejected: version-dependent exit code.
- **Running `gh auth login` interactively.** Rejected: Atlas must run unattended.
- **Storing the token in an Atlas-owned file.** Rejected outright (§4.4).
- **Backing up `hosts.yml`.** Rejected: it is a live OAuth token (§4.8).

## 9. Decisions requiring approval

1. **Package source = Fedora's `gh`, no third-party repo, no `exit 5` fallback.**
   (Recommended.)

2. **Auth = non-blocking, token-only, from stdin; absent token is a warning;
   `ATLAS_GH_TOKEN` is the only Atlas key; an exported `GH_TOKEN` is deferred to,
   not overridden.** Adopted as the standing credential precedent (§4.4), with
   `env::get_secret` (§4.5) as its enforcement. (Recommended.)

3. **Managed config set = `git_protocol=ssh`, applied only when `config.yml` is
   absent — and nothing else.**

   Rationale: it is the one setting that materially changes behaviour (`gh repo
   clone` uses SSH), it aligns with `core/ssh` landing next, and the user can
   change it back with one command.

   **Ordering hazard, stated plainly.** `git_protocol=ssh` presumes a key
   registered on GitHub. `core/ssh` is module 3, and *no Atlas module can push a
   key to GitHub without an authenticated `gh`*. So `install` emits a warning
   naming the manual step, verbatim:

   > `gh` will clone over SSH. Register a key with GitHub before cloning:
   > `gh ssh-key add ~/.ssh/id_ed25519.pub` (after `atlas install core/ssh`), or
   > add it at https://github.com/settings/keys

   **Forward note:** RFC-0004 (`core/ssh`) will attempt `gh ssh-key add` on a
   best-effort basis — succeeding when `gh` is authenticated, warning when it is
   not. That closes the loop without reordering anything.

   **The owner's Phase-1 order was reviewed and stands: Git → GitHub CLI → SSH.**
   It is uniquely enabling. `gh` needs Git; registering an SSH key with GitHub
   needs an authenticated `gh`. Reversing modules 2 and 3 would leave the key
   unregistered *and* leave `gh` unable to register it later without a second
   pass. Do not reorder.

   *Alternative:* manage nothing at all and let `gh`'s `https` default stand,
   deferring protocol choice entirely to the user.

4. **`gh auth setup-git` is never run (§4.7); no `remove` hook (§4.8);
   `backup`/`restore` are explicit no-ops because `hosts.yml` holds a live,
   cheaply-regenerable token — a precedent scoped to regenerable credentials
   only, with `core/ssh` implementing the real, encrypted reference.**
   (Recommended.)

## 10. Implementation plan

1. Create the module skeleton + `README.md`.
2. Write failing tests (mocked `gh` recording argv **and** stdin, mocked `dnf`,
   runner-level).
3. Land `env::get_secret` in `internal/env.sh` with its own tests.
4. Implement `check` / `install` / `verify` / `update` / `backup` / `restore`.
5. Full suite green; module verification via `runner::run`.
6. Implementation + architecture + RFC-compliance + documentation review (Opus).
7. Merge.

## 11. Acceptance criteria

- On a fresh Fedora box, `atlas install development/github-cli` installs `gh`,
  sets `git_protocol=ssh`, and either authenticates from a supplied token or warns
  clearly — with no prompt and no manual step inside Atlas.
- On a box where `gh` was already configured, `config.yml` is byte-for-byte
  unchanged.
- Re-running is a clean no-op.
- `verify` passes on an unauthenticated box and says so.
- The token never appears in argv, in a log line, or in any Atlas-owned file.
- A group-readable `atlas.env` yields a warning and an unconsumed secret, not a
  leak and not a failure.
- No hook writes to any file owned by another module.
- Every behaviour above is covered by tests needing neither root, real `dnf`, nor
  real `gh`.
