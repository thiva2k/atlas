# RFC-0003: GitHub CLI Module

| | |
|---|---|
| **Status** | Accepted |
| **Author** | Claude Code (for thiva2k) |
| **Created** | 2026-07-09 |
| **Revised** | 2026-07-10 — empirical `gh` probe; owner rulings; architecture review |
| **Phase / order** | Phase 1 — Foundation · module 2 of 16 |
| **Depends on** | `core/git` (RFC-0001) |
| **Establishes** | How Atlas handles **credentials** and **unattended authentication** |

---

## 1. Summary

Implement `modules/development/github-cli` — install the `gh` CLI and, only when
the user has supplied a token, authenticate non-interactively. `gh auth login` is
interactive by design; Atlas must run unattended. This RFC decides exactly where
that line falls.

**The module owns no `gh` configuration.** That is a decision, arrived at through
§4.6, not an omission.

Git is a prerequisite: `gh` is useless without it.

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
- Authenticate from a token the user supplied out-of-band, if one exists.
- Report auth state clearly in `verify` / `doctor` without failing on its absence.
- Establish the credential-handling precedent (§4.4) and the secret-resolution
  primitive `env::get_secret` (§4.5).

**Non-goals**
- **No management of `gh` configuration at all** (§4.6). Atlas never runs
  `gh config set`, never reads `config.yml`, never creates it.
- No interactive `gh auth login` (Atlas runs unattended).
- No writing, printing, or logging of the token value, ever.
- No management of GitHub Enterprise hosts in v1.
- No `gh extension` management.

## 4. Design

### 4.1 Module layout

```
modules/development/github-cli/
├── module.sh
└── README.md
```

No `config/` directory. `core/git` has one because it owns a config fragment;
this module owns no file at all.

Category `development/`, id **`development/github-cli`**. The binary is `gh`; the
module id is spelled out so `atlas install development/github-cli` reads clearly.

### 4.2 Metadata

```bash
MODULE_NAME="github-cli"
MODULE_DESCRIPTION="GitHub's official CLI: installs gh and authenticates it non-interactively."
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

`gh` stores auth in `hosts.yml` under its config directory, written by
`gh auth login`. That command is interactive. Atlas resolves a token through the
existing `env::get` chain (RFC-0001 §4.5) — environment first, then
`$ATLAS_CONFIG_HOME/atlas.env` — hardened as `env::get_secret` (§4.5).

**Atlas's token key is `ATLAS_GH_TOKEN` and nothing else.** `GH_TOKEN` /
`GITHUB_TOKEN` are *gh's* variables, not Atlas's; their meaning is settled in the
next paragraph rather than by adding them to the resolution chain.

Auth resolution, in order:

1. **`GH_TOKEN` or `GITHUB_TOKEN` is exported in the environment** → `gh` is
   already authenticated, from the environment, for the life of that environment.
   Atlas logs this and **does nothing else**. This is not a preference: `gh auth
   login --with-token` *refuses to run* in this state ("The value of the
   `GH_TOKEN` environment variable is being used for authentication"; the message
   names whichever variable is set). Both variables were probed and behave
   identically (§6.1). Ephemeral env-based auth counts as authenticated for
   `check` and `verify`, and the README says plainly that it vanishes with the
   shell.
2. **Already authenticated on disk** (`gh auth token >/dev/null 2>&1` succeeds) →
   log it, change nothing. A working login is user-owned state and is never
   overwritten.
3. **Not authenticated, `ATLAS_GH_TOKEN` resolvable** → `gh auth login
   --with-token` reading the token **from stdin**, never from a command-line
   argument (argv is world-readable in `/proc`) and never echoed to a log.
   If that command fails, `install` fails. `gh` validates the token over the
   network, so a rejected token and an unreachable network are indistinguishable
   by exit code, and both are treated as hard failures. This is deliberate: the
   user supplied a credential and asked Atlas to install it; finishing "green"
   without having done so would report a workstation as provisioned when its
   GitHub access is not. (An install has already reached the network by this
   point — `os::dnf_install` ran — so offline is not a state Atlas can reach and
   still be doing useful work.)
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
that first needs it, and it is the alternative to every future credentialed module
open-coding the same xtrace guard and permission check.

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

This is not a silent failure mode. `check` resolves the secret too, so in the
state that matters — a token supplied, `gh` logged out — the warning fires on
every `install` and `status` run until the mode is fixed, naming the file and the
command. (`check` short-circuits before resolving when `gh` is already
authenticated: there is no reason to read a credential nobody needs. `verify` and
`doctor` never resolve it at all.)

`env::get` keeps its semantics — non-secret keys (`ATLAS_GIT_USER_EMAIL`) go on
using it, and it still reads a `644` `atlas.env` — but it gains the same xtrace
guard, as a bug fix. It walks *every* line of `atlas.env` to find one key, so
under an operator's `bash -x` a `core/git` identity lookup was tracing
`line=ATLAS_GH_TOKEN=ghp_…`: a module leaking a credential belonging to a
different module, during a lookup of something else entirely. Found by running
`bash -x ./atlas install development/github-cli` end to end; no unit test on
`env::get_secret` could have caught it, because `env::get_secret` was never on
that call path.

#### The resolver's guard is not enough on its own

`env::get_secret` can only protect its own body. The moment a caller does
`token="$(env::get_secret …)"`, xtrace is back on and bash traces the assignment
as `+ token=ghp_…`, then traces the value again on every expansion. The guard is
defeated at the call site, not inside the resolver.

So the rule for callers, and for every credentialed module after this one:
**never assign a secret to a variable.** Pipe the resolver straight into the tool
that consumes it:

```sh
env::get_secret ATLAS_GH_TOKEN | gh auth login --with-token
```

Resolve once beforehand, discarding the value (`env::get_secret KEY >/dev/null`),
to distinguish "no usable secret" — a warning — from "the tool rejected it" — a
failure. The value then never enters the module's shell at all: not in a trace,
not in argv, not in the process's memory.

### 4.6 Configuration — Atlas manages none

`gh` has **no include mechanism**. Unlike Git, there is no way to layer an
Atlas-owned fragment beneath the user's `config.yml`, so RFC-0001 §4.4's pattern
cannot be reused. Atlas will not hand-edit YAML it does not own, and Atlas's
dependency policy forbids pulling in `yq`.

The original design was "set `git_protocol=ssh` if unset". **A probe against real
`gh` disproved the mechanism** (gh 2.45.0 on Ubuntu/WSL, gh 2.93.0 on Windows,
2026-07-09):

| Observation | Consequence |
|---|---|
| `gh config get git_protocol` on a fresh config dir prints `https`, rc `0` | "unset" is **not observable**. `gh` reports its default indistinguishably from a user's explicit choice. Set-if-unset is unimplementable. |
| `gh config get` does not create `config.yml`; `gh config set` does | The **existence of `config.yml`** is an observable "this user has configured gh" signal. |

That second observation admitted a narrower design — write the key only when
`config.yml` is absent — consistent with the owner's ruling:

> Atlas configures GitHub CLI only when initializing a fresh GitHub CLI
> configuration. Existing user configuration is immutable unless the user
> explicitly requests migration or reset.

**The owner then declined that design too** (§9 decision 3), and Atlas manages no
`gh` configuration at all. The reasoning is worth recording, because it is the
kind of default that looks free and is not: under `git_protocol=ssh`, *every*
`gh repo clone` requires a key registered on GitHub — **including public
repositories**, which stock `gh` clones anonymously over HTTPS with no setup. The
benefit accrues only to a user who completes the SSH-key step; the cost lands
immediately on everyone who does not. `gh`'s own default is the better default,
and a user who wants SSH sets it with one command.

Consequently the module never invokes `gh config` in any form, never reads or
creates `config.yml`, and needs no config-path resolution logic. `gh` owns `gh`'s
configuration.

### 4.7 `gh auth setup-git` — deliberately NOT run

`gh auth setup-git` writes `credential.helper` entries into the user's global Git
config, through `gh`'s own writer.

Note that decision 3 **removed** the convenient second argument for declining.
Under the abandoned `git_protocol=ssh` design, `setup-git` was simply unnecessary —
SSH needs no credential helper. Under `gh`'s HTTPS default it is *not* unnecessary;
it is exactly what an HTTPS user wants. Atlas still does not run it, and the
reason is the one that was load-bearing all along:

It is **configuration this module does not own**. `docs/conventions.md` permits
editing a file another module owns only under the validate-then-write, atomic,
revertible discipline `core/git` implements. An edit made by `gh`'s writer is none
of those things: Atlas cannot validate it, cannot track it, and cannot revert it.
It would also mean `development/github-cli` mutating `core/git`'s owned file — the
explicit safety rule against modifying another module's configuration.

The README tells HTTPS users to run `gh auth setup-git` themselves, in one line.
That is the whole cost of holding the boundary, and it is worth paying: this is
the reference example of a module **declining** to do something convenient because
it would cross a module boundary.

### 4.8 Hook contracts

**`check`** — satisfied iff:

```
os::has_cmd gh  AND  NOT ( token-resolvable AND not-authenticated )
```

where "not-authenticated" is the offline probe `gh auth token >/dev/null 2>&1`
failing.

The governing rule is *if there is work `install` can do, `check` must fail* — the
runner skips `install` entirely when `check` passes, so a `check` that ignores
available work leaves that work undone forever. Enumerating every state:

| `gh` | token | authed | `check` | Correct? |
|---|---|---|---|---|
| absent | any | any | fails | yes — `install` installs it |
| present | yes | no | fails | yes — `install` authenticates |
| present | yes | yes | passes | yes — nothing to do |
| present | no | yes | passes | yes — nothing to do |
| present | no | no | passes | yes — `install` **cannot** log a user in without a credential |

Configuration appears nowhere in this table because the module owns none (§4.6).
Had it owned any, the clause would have had to assert the config file's
**existence** (fixable by `install`, converging after one run) and never its
**contents** (unfixable under the immutability ruling — a user who changed the
value would fail `check` on every run with no path to green). That is the same
distinction `core/git` draws: it asserts its include is *first*, an Atlas-owned
property `install` can restore, not that Atlas's values *win*, a user-owned
outcome it must not force.

Note the consequence of the last row: on `atlas install`, a passing `check` skips
the module **including its `verify` hook** (`internal/runner.sh`: the `check`
branch prints `__SKIP__` and exits), so the "installed but unauthenticated"
warning is **not** printed during that run. It surfaces under `atlas verify` and
`atlas doctor`, which is where a user looks for the health of an
already-provisioned box.

**`install`** —
1. `os::has_cmd gh` || `os::dnf_install gh`
2. authenticate per §4.4

Returns non-zero only on a real failure: the package install, or a resolvable
token that `gh auth login --with-token` did not accept.

**`verify`** — `gh --version` succeeds. Auth state is *reported*: authenticated →
`info`; not → `warn`. Never fails on auth.

> **Engine gap.** The runner's per-module outcome is `ok` / `skip` / `fail`; a
> warning is invisible in the summary line. "Installed but unauthenticated" is
> exactly the state a `doctor` run should surface. This is a whole-system defect,
> not a `github-cli` one, and needs its own RFC. Noted, not worked around.

**`update`** — no-op beyond a log line. Package currency is the OS's job
(RFC-0001 §3); Atlas manages no configuration; auth is user-granted.

**`remove`** — **no hook.** There is nothing to revert: Atlas wrote no file it
owns, and it must not delete a credential the user granted or a package other
tools depend on. The runner skips a hook a module does not define. The reasoning
lives in the README, where a reader looking for it will actually be; a hook body
that only logs "I do nothing" is noise in the module contract. (No `remove`
platform verb exists yet in any case — RFC-0002.)

**`backup` / `restore`** — explicit **no-op hooks**, each logging why. `gh`'s only
persistent state is `hosts.yml`, which holds a live OAuth token. Atlas will not
copy credentials around: regenerating a token is cheap, leaking one is not.
(`config.yml` is not Atlas's either, and after decision 3 Atlas never so much as
creates it.)

Per the owner's ruling this is scoped, not universal:

> Keep the generic `backup` / `restore` platform verbs. Implement real
> backup/restore in the SSH module as the first concrete implementation, but do
> not special-case SSH in the runner. The runner remains generic and fans out to
> every module. Modules without persistent state implement no-op hooks. The backup
> artifact must contain only module-owned state and should be encrypted locally.

So the precedent this RFC sets is narrow: **a module may decline to back up state
when that state is either user-owned or a cheaply-regenerable credential.** That
carve-out *extends* the ruling rather than restating it — the ruling gives no-op
hooks to modules with no persistent state, and `gh` has some — so it is submitted
for approval as §9 decision 4. A module that declines to back up state because
backing it up is merely *awkward* is a bug, not a precedent.

`core/ssh` (RFC-0004) holds state that is neither user-owned-and-untouchable nor
regenerable — a lost private key is a lost identity — and will implement real,
locally-encrypted backup/restore as the reference for every stateful module after
it.

> *Follow-up:* `core/git` (RFC-0001) omits `backup`/`restore` entirely rather than
> defining no-op hooks. That predates this ruling and is a documentation-level
> inconsistency, not a behavioural one: `internal/runner.sh` skips an undefined
> optional hook with `log::debug` and still counts the module `ok`, which is the
> same outcome as a no-op hook returning 0. It is folded into RFC-0004's branch,
> where the backup contract is written.

## 5. Idempotency & fail-safety

- Re-running `install` on an authenticated box changes nothing and logs why.
- A rejected token fails `install` loudly (non-zero) rather than leaving the user
  believing they are logged in.
- No hook ever writes to `~/.gitconfig`, `~/.ssh`, `config.yml`, or any other file
  Atlas does not own — which, in this module, is every file.

## 6. Testing

Same sandbox discipline as RFC-0001, extended for a binary Atlas does not own:

- `HOME`, `GH_CONFIG_DIR`, `ATLAS_CONFIG_HOME` → fresh `mktemp -d`.
- `GH_TOKEN` and `GITHUB_TOKEN` explicitly unset unless a test is exercising §4.4
  case 1.
- `os::dnf_install` mocked.
- **`gh` is mocked as a shell function** (functions take precedence over `PATH`),
  recording both its **argv** and its **stdin** to files, so tests can assert what
  was asked of it *and* that the token arrived intact on stdin.
- Hook-level tests run under `set -euo pipefail`, the flags `internal/runner.sh`
  gives a hook subshell. Runner-level tests, which drive the module through
  `runner::run`, must instead use the `atlas` entrypoint's flags — `set +e; set -uo
  pipefail`. Under a caller's `-e` the runner dies at the first failing module
  before its failure tally runs, so `ATLAS_EXIT_MODULE` is never returned and an
  "exit 4" assertion proves nothing.
- No test may run real `dnf`, real `gh`, or touch the real `$HOME`.
- The mocked `gh` must disable xtrace in its own body: the real `gh` is a compiled
  binary whose internals cannot appear in a shell trace, and a mock that traces
  them would fail the xtrace-containment assertions for the wrong reason.

Required assertions:

- token reaches `gh` on **stdin**, and appears **nowhere** in recorded argv;
- token absent → `install` succeeds, warns, exit 0;
- `GH_TOKEN` exported → no `gh auth login` invocation at all; treated as authed;
- `GITHUB_TOKEN` exported (with `GH_TOKEN` unset) → identical behaviour;
- `gh auth login --with-token` fails → `install` fails, non-zero;
- already authenticated on disk → auth untouched;
- **`gh config` is never invoked, with any arguments, by any hook** (§4.6);
- **no hook creates `config.yml`**;
- `gh auth setup-git` is never invoked (§4.7);
- `atlas.env` mode `640` → secret not consumed, warning emitted, install still
  succeeds;
- `gh auth token` is never invoked with its stdout captured;
- `verify` warns but passes when unauthenticated;
- `check` fails when a token is resolvable and `gh` is logged out;
- `check` passes when `gh` is installed and no token is resolvable;
- `check` fails when `gh` is absent.

### 6.1 Assumptions about `gh`'s contract

The mock encodes behaviour observed on **gh 2.45.0 (Ubuntu/WSL)** and **gh 2.93.0
(Windows)**, 2026-07-09 and 2026-07-10:

1. `gh auth token` returns non-zero, offline, when no credential is stored — and
   **prints the token** when one is.
2. `gh auth status` exit code is not stable across versions (rc `0` logged out on
   2.45.0; rc `1` on 2.93.0). Atlas never calls it.
3. `gh auth login --with-token` refuses, exit `1`, when **either** `GH_TOKEN` or
   `GITHUB_TOKEN` is exported; in that state `gh auth token` returns `0` and echoes
   the environment's value. Both variables observed independently.
4. `gh --version` and `gh auth token` create **nothing** in a fresh config
   directory (observed: it stays empty). Atlas therefore leaves no trace on a box
   where `install` is skipped or only probes run.

(The `gh config get` findings that killed the set-if-unset design are recorded in
§4.6 for the record; no assumption about `gh config` remains load-bearing, because
Atlas no longer calls it.)

A mocked `gh` proves Atlas's logic, not `gh`'s. **Named follow-up gate before the
v1.1 tag:** one manual pass of `atlas install development/github-cli` against real
`gh` on the clean Fedora acceptance box, recorded in the production-readiness
report. If any assumption above breaks on Fedora's `gh`, the mock and this section
are wrong together and must be corrected together.

## 7. Documentation

`modules/development/github-cli/README.md`, plus a `docs/conventions.md` section
codifying §4.4's credential rules and `env::get_secret` for all future modules.
The README must state (a) that `gh` clones over HTTPS by default and how to change
that, (b) that `gh auth setup-git` is the user's to run, and (c) that an exported
`GH_TOKEN` is ephemeral auth that dies with the shell.

## 8. Alternatives considered

- **Upstream `gh` dnf repo.** Rejected: Fedora packages `gh`; a third-party repo
  adds trust and an engine primitive for nothing (§4.3).
- **Atlas-owned `config.yml` fragment.** Impossible: `gh` has no include.
- **Hand-merging the user's YAML.** Rejected: needs a YAML parser; Atlas's
  dependency policy forbids `yq`.
- **Set-if-unset `git_protocol` via `gh config get`.** Rejected: empirically
  impossible — `gh` cannot distinguish unset from default (§4.6).
- **Set `git_protocol=ssh` only when `config.yml` is absent.** Implementable, and
  rejected on merit by the owner: it breaks anonymous public-repo clones for every
  user who never registers a key (§4.6, §9 decision 3).
- **Atlas-owned stamp file + reconcile on `update`.** Moot once no key is managed.
- **`gh auth status` as the auth probe.** Rejected: version-dependent exit code.
- **Running `gh auth login` interactively.** Rejected: Atlas must run unattended.
- **Storing the token in an Atlas-owned file.** Rejected outright (§4.4).
- **Backing up `hosts.yml`.** Rejected: it is a live OAuth token (§4.8).

## 9. Decisions

1. **Package source = Fedora's `gh`, no third-party repo, no `exit 5` fallback.**
   *Adopted as recommended.*

2. **Auth = non-blocking, token-only, from stdin; absent token is a warning; a
   supplied-but-unusable token is a hard failure; `ATLAS_GH_TOKEN` is the only
   Atlas key; an exported `GH_TOKEN`/`GITHUB_TOKEN` is deferred to, not
   overridden.** The standing credential precedent (§4.4), enforced by
   `env::get_secret` (§4.5). *Adopted as recommended.*

3. **Atlas manages no `gh` configuration.** *Decided by the owner, 2026-07-10,*
   against the drafted `git_protocol=ssh` alternative, on the grounds that SSH
   breaks anonymous public-repo clones until a key is registered and therefore
   leaves a no-token user strictly worse off than stock `gh`.

   The consequences are carried through §4.6 (no `gh config` calls), §4.7 (the
   "unnecessary under SSH" argument against `gh auth setup-git` is withdrawn; the
   module-boundary argument stands alone), §4.8 (`check` has no config clause;
   `update` is a pure no-op), and §6 (tests assert `gh config` is *never* called).

   **The Phase-1 order was reviewed and stands: Git → GitHub CLI → SSH.** It is
   uniquely enabling — `gh` needs Git, and registering an SSH key with GitHub needs
   an authenticated `gh`. RFC-0004 (`core/ssh`) will attempt `gh ssh-key add` on a
   best-effort basis: succeeding when `gh` is authenticated, warning when it is
   not. Do not reorder.

4. **`gh auth setup-git` is never run (§4.7); no `remove` hook; `backup`/`restore`
   are explicit no-ops because `hosts.yml` is a cheaply-regenerable credential and
   `config.yml` is user-owned (§4.8).** This *extends* the owner's backup ruling,
   which addresses modules with no persistent state, to modules whose state is
   user-owned or regenerable. Declining to back up state because it is merely
   *awkward* remains a bug. `core/ssh` implements the real, locally-encrypted
   reference. *Adopted as recommended.*

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

- On a fresh Fedora box, `atlas install development/github-cli` installs `gh` and
  either authenticates from a supplied token or warns clearly — with no prompt and
  no manual step inside Atlas.
- `gh`'s configuration is untouched: no `config.yml` is created, on any path.
- Re-running is a clean no-op.
- `verify` passes on an unauthenticated box and says so.
- The token never appears in argv, in a log line, or in any Atlas-owned file.
- A group-readable `atlas.env` yields a warning and an unconsumed secret, not a
  leak and not a failure.
- No hook writes to any file owned by another module.
- Every behaviour above is covered by tests needing neither root, real `dnf`, nor
  real `gh`.
