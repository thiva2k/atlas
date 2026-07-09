# RFC-0001: Git Module

| | |
|---|---|
| **Status** | Accepted (2026-07-09) |
| **Author** | Claude Code (for thiva2k) |
| **Created** | 2026-07-09 |
| **Accepted** | 2026-07-09 — all four §9 decisions approved as recommended |
| **Phase / order** | Phase 1 — Foundation · module 1 of 16 |
| **Depends on** | Promotes `os::dnf_install` from placeholder to real (§4.6) |
| **Reference for** | Every future Atlas module |

---

## 1. Summary

Implement `modules/core/git` — the first *real* Atlas module. On a fresh Fedora
workstation it installs Git, applies an Atlas-owned set of global defaults, and
optionally configures the user's commit identity. It is idempotent, safely
re-runnable, fully tested, and fully documented.

Because Git is the first module, **this RFC also sets the precedent** for three
things every later module inherits:

1. **How a module owns configuration** without clobbering the user's files.
2. **How user-specific values** (identity, secrets) reach a module without being
   hard-coded or committed.
3. **How a module that installs system software is tested** without root and
   without mutating the test machine.

It also promotes the shared `os::dnf_install` helper from a logging placeholder
to a real, idempotent package-install primitive (§4.6) — Git is its first
consumer, and every future module reuses it.

## 2. Motivation

Atlas v1.0 delivered the skeleton: contract, runner, CLI, engine, placeholder
modules. v1.1 fills the modules in, one at a time. Git is first because it is a
hard dependency of the tools Atlas itself is developed with (GitHub CLI, the AI
CLIs) and because it exercises every part of the module contract — package
install, configuration ownership, verification, idempotency, and the
user-specific-config problem — making it the ideal reference implementation.

## 3. Goals / Non-goals

**Goals**
- Install the `git` package on Fedora, idempotently.
- Apply a small, opinionated set of Atlas-managed global git defaults that Atlas
  fully owns and can cleanly remove.
- Configure the user's `user.name` / `user.email` when the user has supplied
  them, without ever clobbering an identity the user already set.
- Provide `check` / `install` / `verify` (required) plus `update` and `remove`
  (optional). `backup` / `restore` are intentionally omitted (§4.7).
- Log every action; fail safely; be safe to run any number of times.
- Establish the reusable **configuration**, **identity-sourcing**, and
  **testing** patterns for all future modules.

**Non-goals**
- No `dnf upgrade` of the git package (OS package currency is the OS's job).
- No management of per-repository config, credential helpers, GPG/SSH commit
  signing (SSH is Phase 1 module 3; signing can be a later RFC).
- No interactive prompting (Atlas must run unattended).
- No migration/import of an existing `~/.gitconfig`.

## 4. Design

### 4.1 Module layout

```
modules/core/git/
├── module.sh                 # metadata + hooks (the contract)
├── config/
│   └── gitconfig             # Atlas-owned git config fragment (managed defaults)
└── README.md                 # what it does / installs / depends on
```

`config/gitconfig` is the fragment Atlas owns and installs (§4.4). It replaces
the current placeholder `config/gitconfig.template`.

### 4.2 Metadata & dependencies

```bash
MODULE_NAME="git"
MODULE_DESCRIPTION="Distributed version control: installs git and applies Atlas's global defaults."
MODULE_DEPENDS=()
```

Git has no Atlas-module dependencies — it is foundational. (It depends on the
engine's `os::dnf_install`, which is engine, not a module.)

### 4.3 Managed configuration (what Atlas owns)

Atlas manages a small, uncontroversial default set. These live in the fragment
(§4.4) and are the *only* keys Atlas claims ownership of:

```ini
[init]
	defaultBranch = main
[pull]
	rebase = true
[push]
	default = simple
	autoSetupRemote = true
[fetch]
	prune = true
[rebase]
	autostash = true
[color]
	ui = auto
```

These are deliberately modest and are the user's to tune — the file is theirs to
edit after install. **The exact default set is a taste decision (see §9).**

`user.name` / `user.email` are **not** in the fragment — they are per-user
identity, handled separately (§4.5) so Atlas never overwrites a user's own.

### 4.4 Configuration strategy — an Atlas-owned include fragment

**Decision (recommended): `include.path`.** Atlas writes its managed defaults to
a single Atlas-owned file and adds *one* `include.path` line to the user's
`~/.gitconfig`:

- Fragment installed to **`${XDG_CONFIG_HOME:-$HOME/.config}/atlas/git/gitconfig`**
  (Atlas's file — Atlas may overwrite it freely).
- One idempotent include line added to `~/.gitconfig`:
  ```
  [include]
  	path = ~/.config/atlas/git/gitconfig
  ```
  added via `git config --global --add include.path <path>` **only if that exact
  path is not already included** (checked with `git config --global --get-all
  include.path`).

Why this is the reference pattern:
- **A module owns its own configuration** (an architecture principle) — literally
  one Atlas-owned file.
- **Never modifies another module's / the user's file** beyond one include line.
- **Idempotent** — re-running rewrites Atlas's own fragment and re-checks the
  single include line.
- **Cleanly removable** — `remove` deletes the fragment and drops the include
  line, leaving the user's `~/.gitconfig` otherwise untouched.
- Because the include is added near the top of `~/.gitconfig`, any value the user
  later sets directly in `~/.gitconfig` overrides the Atlas default — Atlas
  provides defaults, the user always wins.

The alternative (`git config --global <key> <val>` per key) is simpler but
intermixes Atlas's settings with the user's in one file, making "what did Atlas
set?" and clean removal harder. See §8.

### 4.5 User identity sourcing (the cross-cutting precedent)

A fresh machine has no `user.name` / `user.email`, and they must never be
hard-coded or committed. **Recommended source order (first hit wins):**

1. **Environment:** `ATLAS_GIT_USER_NAME`, `ATLAS_GIT_USER_EMAIL`.
2. **User config file:** `${XDG_CONFIG_HOME:-$HOME/.config}/atlas/atlas.env`
   (a gitignored, machine-local file the user fills once), e.g.
   ```
   ATLAS_GIT_USER_NAME="Ada Lovelace"
   ATLAS_GIT_USER_EMAIL="ada@example.com"
   ```
3. **Neither present:** skip identity. `install` still succeeds and logs a clear
   `warn` telling the user how to set it. Git without an identity is fine until
   the first commit, so a missing identity must **not** fail `install` or
   `verify`.

Identity is written with `git config --global user.name/email` **only if that
key is currently unset**, so Atlas never clobbers an identity the user already
configured (idempotent + non-destructive on re-runs).

This establishes the general rule for every future module:
**user-specific configuration comes from `atlas.env` (with env-var override),
never from tracked files, and is applied non-destructively.**

### 4.6 Foundational dependency — real `os::dnf_install`

The engine ships `os::dnf_install` as a placeholder that only logs. Git is its
first real consumer, so this RFC promotes it to a real primitive (still in
`internal/os.sh`, no contract change):

```
os::dnf_install <pkg>...
- os::require_cmd dnf                 # exit 5 (unsupported) if no dnf
- SUDO=""; os::is_root || SUDO="sudo" # use sudo only when not already root
- log::info "installing packages: $*"
- $SUDO dnf install -y "$@"           # dnf install is idempotent (no-op if present)
- on failure: return non-zero (caller decides fatality); log::error the failure
```

It is idempotent (dnf is a no-op for already-installed packages), fails safely,
and logs. Every future module installs packages through it.

### 4.7 Hook contracts

**`module::check`** — the idempotency gate. Returns `0` (satisfied, nothing to
do) iff **all** hold: `os::has_cmd git`; the Atlas fragment file exists; the
include line is present in `~/.gitconfig`. Identity is *not* part of `check`
(it's optional/user-supplied). Any miss → non-zero (work needed).

**`module::install`** — idempotent, in order, each step logged:
1. If `! os::has_cmd git` → `os::dnf_install git`.
2. Write/refresh the Atlas fragment (Atlas owns it → overwrite).
3. Ensure the single `include.path` line (add only if absent).
4. Resolve identity (§4.5); set `user.name` / `user.email` only if provided
   **and** currently unset; otherwise `warn` and continue.
Returns non-zero on any real failure, leaving a re-runnable state.

**`module::verify`** — health check, returns `0` if healthy: `git --version`
succeeds; the fragment exists; `git config --global --get init.defaultBranch`
(and the other managed keys) resolve to the expected values. Missing identity is
**not** a verify failure (it is optional).

**`module::update`** — re-apply the latest managed fragment + re-check the
include line (picks up changes to Atlas's default set). Does not touch identity;
does not upgrade the package.

**`module::remove`** — drop the include line from `~/.gitconfig` and delete the
Atlas fragment. **Does not uninstall the git package** (shared, high blast
radius) and does not touch the user's identity. Logs exactly what it changes.

**`module::backup` / `module::restore`** — intentionally **not implemented**.
Nothing Git-related is both irreplaceable *and* Atlas-owned: the managed fragment
is regenerable, and identity/`~/.gitconfig` belong to the user, not Atlas. This
is a deliberate reference example of when omitting optional hooks is correct.

## 5. Idempotency & fail-safety

| Operation | Idempotency mechanism |
|---|---|
| Package install | guarded by `os::has_cmd git`; `dnf install` is itself a no-op if present |
| Managed fragment | Atlas owns the file → overwrite is inherently idempotent |
| Include line | added only if the exact path is absent (`--get-all include.path` check) |
| Identity | set only if the key is currently unset (never clobbers the user) |

Fail-safe rules: any real failure (`dnf` error, unwritable config) returns
non-zero via the module contract / `die`; a partially-completed run always leaves
a state that a re-run completes cleanly. All output goes through `log::*`.

## 6. Testing strategy (the reference testing pattern)

The hard problem — and the precedent — is testing a module that installs system
packages, on any machine, without root and without mutating it. The pattern:

**Two seams:**

1. **Mock the system-mutating primitive.** Tests override `os::dnf_install` with
   a stub that records its arguments and returns success (or, in a negative test,
   failure). Tests therefore never invoke real `dnf`/`sudo`.
   ```bash
   os::dnf_install() { printf '%s\n' "$*" >>"$STUB_CALLS"; return 0; }
   ```

2. **Sandbox and really-run the user-space side.** Point `HOME` and
   `XDG_CONFIG_HOME` at a temp dir and run the *real* `git config` operations
   (Git is available in the test harness). Assert the resulting fragment file,
   the include line, and the managed values — then run `install` **again** and
   assert nothing changed (idempotency).

**Test cases (`tests/test_module_git.sh`):**
- `install` on a clean sandbox → fragment created, include line present, managed
  keys resolve, `os::dnf_install git` was called once.
- `install` run twice → identical state, still exactly one include line
  (idempotency).
- Identity: with `ATLAS_GIT_USER_*` set → identity written; with a pre-existing
  identity in the sandbox → **not** overwritten; with neither → install still
  succeeds, identity unset, a warning logged.
- `check` → non-zero on a clean sandbox, `0` after `install`.
- `verify` → `0` after `install`; non-zero when the fragment/include is missing.
- `remove` → include line dropped, fragment deleted, `~/.gitconfig` otherwise
  intact; git package untouched.
- `os::dnf_install` unit test: shadow `dnf` (and `sudo`) with stub scripts on a
  temp `PATH`, assert the constructed command and the non-zero return when the
  stub fails.

Package installation on real Fedora is an **integration** concern validated on an
actual Fedora box (and later Fedora CI), explicitly out of unit-test scope — the
mock covers the module's contract with the primitive.

The harness sandboxes `HOME` per test (subshell + `mktemp -d`, cleaned up), so
tests remain isolated and the single-shell `run.sh` sourcing model is respected
(each test file sets its own environment; cf. `CONTRIBUTING.md`).

## 7. Documentation plan

- `modules/core/git/README.md` — updated to describe real behavior: what it
  installs, the managed config keys, how to set identity (`atlas.env` / env
  vars), and how `remove` behaves.
- `CHANGELOG.md` — an entry under Unreleased.
- If the identity/`atlas.env` convention is accepted, a short note in
  `docs/conventions.md` establishing "user-specific config lives in
  `~/.config/atlas/atlas.env`" for all modules.

## 8. Alternatives considered

- **Direct `git config --global <key>` per managed key** (no fragment). Simpler,
  but Atlas's keys intermix with the user's, "what did Atlas set?" is unclear,
  and clean removal is fiddly. Rejected in favor of the owned fragment.
- **Symlink a whole `~/.gitconfig`.** Atlas would own the *entire* file and
  clobber anything the user has. Violates "never modify the user's file" and is
  hostile on a machine that isn't brand-new. Rejected.
- **Interactive identity prompt.** Breaks unattended runs. Rejected in favor of
  `atlas.env` + env vars.
- **Storing identity in a tracked repo file.** Leaks personal data into git.
  Rejected outright.

## 9. Decisions (approved 2026-07-09)

All four were approved as recommended:

1. **Config strategy** → **`include.path` owned fragment** (§4.4). ✅ Approved.
2. **Identity sourcing** → **env vars + `~/.config/atlas/atlas.env`,
   non-blocking** (§4.5), adopted as the standard for all future user-specific
   config. ✅ Approved.
3. **Managed default set** (§4.3) → approved **as-is**. ✅
4. **`os::dnf_install` promotion** (§4.6) → **folded into** this module's work.
   ✅ Approved.

## 10. Implementation plan (after acceptance)

One focused change, TDD, small commits:
1. Promote `os::dnf_install` to real + its unit test.
2. Add the identity resolver (env → `atlas.env`) + tests.
3. Write `modules/core/git/config/gitconfig` (managed fragment).
4. Implement `module.sh` hooks (`check`/`install`/`verify`/`update`/`remove`),
   TDD against the sandbox pattern (§6).
5. Update `modules/core/git/README.md`, `CHANGELOG.md`, and (if approved)
   `docs/conventions.md`.
6. Full suite green + review → merge.

## 11. Acceptance criteria

- On a fresh Fedora box, `atlas install core/git` installs Git, writes the
  managed fragment, wires the include line, and (given `atlas.env`/env) sets
  identity — with no manual steps.
- Re-running is a clean no-op (`check` returns satisfied; state unchanged).
- `verify` passes; `remove` cleanly reverts Atlas's changes without touching the
  package or the user's identity.
- Every behavior above is covered by tests that need neither root nor a real
  package install.
- The config, identity, and testing patterns here are documented well enough that
  the next module (GitHub CLI) can follow them without re-deriving them.

## Errata

*Appended 2026-07-09 during implementation. Nothing above this line is modified;
the RFC's status and its §9 decisions stand unchanged.*

**§4.4's mechanism sketch cannot satisfy §4.4's own guarantee.** The section shows
`git config --global --add include.path …`, but `--add` *appends* — git writes the new
`[include]` section at the **bottom** of `~/.gitconfig`. Git resolves configuration
positionally (last value wins) and expands an include at the position of the directive.
A bottom include is therefore read **last**, so the Atlas fragment would silently
override any value the user had already set above it: a user with
`[pull] rebase = false` would find `git config pull.rebase` reporting `true` after
`atlas install`.

That is the exact opposite of the guarantee stated in the same section — "the include
is added near the top … Atlas provides defaults, **the user always wins**" — which is
also the rationale on which §9 decision 1 selected `include.path` in the first place.

**The guarantee is normative; the `--add` sketch was an error in the example.** The
implementation prepends the `[include]` block to the top of
`${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}` via an atomic, mode-preserving, lock-guarded
rewrite, and relocates an already-appended include on re-install. `module::check` and
`module::verify` require the block to be *first*, not merely present, so an older
mis-installed config migrates itself. No design decision changed, so no superseding RFC
is required.
