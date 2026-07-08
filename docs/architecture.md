# Atlas — Architecture

> This document is the single source of truth for how Atlas is designed.
> A new contributor should be able to read it in ten minutes and understand
> how Atlas works, how modules work, how to add one, and how a command flows
> through the system.

---

## 1. What Atlas is

Atlas is a **workstation lifecycle manager**. It manages the complete life of a
personal engineering workstation: bootstrapping a fresh machine, installing and
configuring tooling, verifying health, managing configuration, and backing up
and restoring irreplaceable assets.

Atlas is **not** a migration project, **not** a dotfiles repository, and **not**
a package installer. Migration, installation, backup, restore, verification,
updates, and diagnostics are *capabilities* of Atlas — not its identity.

Everything in this repository should reinforce that framing.

---

## 2. Engineering principles

These are load-bearing. When a design decision is unclear, resolve it toward the
principle.

- **Simplicity over cleverness.** The obvious implementation wins.
- **Unix philosophy.** Small pieces, one job each, composed through clear interfaces.
- **Single Responsibility.** A file, function, or module does one thing.
- **Explicit over implicit.** No magic. Behaviour is discoverable by reading.
- **Convention over configuration.** Structure carries meaning (e.g. a module's
  category is its directory), so there is less to configure.
- **Modular by design.** Capabilities are modules; the core knows nothing about them.
- **Zero unnecessary dependencies.** See §4.
- **Documentation is part of the product.** An undocumented module is unfinished.
- **Restore is as important as backup.** A backup that cannot be restored is a lie.
- **Every module is independently understandable.** You can read one module in
  isolation and know what it does, how to use it, and what it needs.

Avoid premature optimization and avoid introducing abstractions before a real
use case demands them.

---

## 3. The two-level lifecycle (core mental model)

Atlas has two lifecycles that never bleed into each other.

**Platform verbs** — what the *user* runs:

```
atlas install    atlas update    atlas verify    atlas backup
atlas restore    atlas doctor     atlas status
```

**Module hooks** — what each *module* implements:

| Hook      | Required | Purpose                                           |
|-----------|----------|---------------------------------------------------|
| `check`   | ✔        | Is this capability already present & configured?  |
| `install` | ✔        | Make it present & configured (idempotent).        |
| `verify`  | ✔        | Is it healthy right now?                           |
| `update`  | optional | Bring it to the latest desired version.           |
| `remove`  | optional | Cleanly remove it.                                 |
| `backup`  | optional | Capture this module's irreplaceable state.        |
| `restore` | optional | Re-apply previously captured state.               |

A platform verb is nothing more than the **runner fanning that verb out across
the selected modules**. `atlas backup` means "call every module's `backup`
hook." That is why backup and restore are verbs, not folders — they are
cross-cutting operations expressed once in the runner and contributed to by
modules.

**The runner never depends on a module's internals.** It only ever calls hooks
through the module contract (§7).

---

## 4. Runtime dependency policy

An end user performing a fresh installation must need only:

- **Bash**
- **Core GNU utilities** (coreutils, grep, sed, etc.)
- **Git** (bootstrapped by `bootstrap.sh` if missing)
- the **Fedora base system**

Explicitly **not** required at runtime: Ansible, Python frameworks, `jq`, `yq`,
any YAML parser, `just`, `make`, or any orchestration framework.

Consequences that shape the whole codebase:

- Data the runner must parse (module metadata, dependency lists) is expressed in
  **plain Bash**, so Bash itself is the parser. No config file needs a third-party
  reader.
- Development-only dependencies (e.g. a test framework, a linter) are acceptable,
  but they live behind contributor tooling and are **never** on the end-user path.

---

## 5. Repository layout

```text
atlas/
├── atlas                 # the CLI entrypoint — parses args, dispatches a verb
├── bootstrap.sh          # zero-dependency first touch on a fresh machine
├── internal/             # the reusable engine (shared, not user-facing)
│   ├── log.sh            # logging system (§9)
│   ├── error.sh          # error handling, traps, exit codes (§8)
│   ├── os.sh             # Fedora / dnf / flatpak / privilege helpers
│   ├── module.sh         # module discovery, contract, dependency resolution
│   └── runner.sh         # the verbs, implemented on top of the above
├── modules/              # every capability lives here, grouped by category
│   ├── core/             #   fundamentals (git, base packages, shell)
│   ├── development/      #   dev tooling (docker, language runtimes, claude, codex)
│   ├── apps/             #   applications (brave, ghostty)
│   └── desktop/          #   desktop environment (kde, fonts)
├── docs/                 # architecture, conventions, module-authoring guide
├── tests/                # pure-Bash test harness (no external framework)
├── assets/               # static, non-code assets
├── README.md  LICENSE  CONTRIBUTING.md  CHANGELOG.md
```

Notes:

- **`internal/` vs `modules/`.** `internal/` is the engine and is shared by every
  module. `modules/` is where capabilities live. The engine must not know the
  name of any specific module.
- **Categories are directories.** A module's category is simply the directory it
  sits in (`modules/<category>/<name>/`). Nothing declares it separately.
- **No `profiles/` in v1.** Atlas currently targets a single engineering
  workstation. Profiles/roles are a future concern and are deliberately omitted
  to avoid speculative abstraction.
- **No top-level `scripts/` in v1.** Contributor tooling lives under `tests/` and
  `internal/` as needed.

---

## 6. Anatomy of a module

Every module is a self-contained directory:

```text
modules/<category>/<name>/
├── module.sh    # metadata + lifecycle hooks (the contract)
├── config/      # files this module owns (templates, dotfiles) — optional
└── README.md    # what it does, what it installs/configures, what it depends on
```

A module owns everything it needs. There is no shared `configs/` or `packages/`
directory — the files a module manages live beside the module that manages them.
This is what "independently understandable" means in practice: to understand the
`git` module you open exactly one directory.

---

## 7. The module contract

`module.sh` is a Bash file that the runner **sources in an isolated subshell** and
then interrogates. Isolation (a subshell per module invocation) means a module
cannot corrupt runner state or another module, and plain hook names cannot
collide.

### 7.1 Metadata

Declared as plain variables at the top of `module.sh`:

```bash
MODULE_NAME="git"
MODULE_DESCRIPTION="Distributed version control: installs git and applies global config."
MODULE_DEPENDS=()          # e.g. ("core/base") — references are "category/name"
```

The category is **not** declared here; it is derived from the directory path.
Keep metadata to the minimum that carries meaning.

### 7.2 Hooks

Hooks are functions in a `module::` namespace. `check`, `install`, and `verify`
are required; the rest are optional and the runner detects their presence before
calling them.

```bash
module::check()   { ... }   # 0 = already satisfied; non-0 = work needed
module::install() { ... }   # make it so; MUST be safe to run repeatedly
module::verify()  { ... }   # 0 = healthy; non-0 = broken

# optional:
module::update()  { ... }
module::remove()  { ... }
module::backup()  { ... }
module::restore() { ... }
```

### 7.3 Hook return-code contract

- **`check`** — exit `0` if the capability is already present and configured
  (the runner will skip `install`); any non-zero means "not satisfied, work
  needed." `check` is what makes `install` idempotent.
- **`install`** — perform the work. Because `check` gates it and because Atlas
  values idempotency, `install` should itself be safe to re-run.
- **`verify`** — exit `0` if the capability is healthy; non-zero signals a
  problem for `atlas verify` / `atlas doctor` to report.
- Optional hooks follow the same convention: `0` = success, non-zero = failure
  with a logged reason.

Modules communicate **only** through this contract. If the runner ever needs to
reach inside a module, the contract is wrong and should be extended instead.

---

## 8. Error handling

Failure behaviour is predictable and loud.

- The `atlas` entrypoint runs under `set -uo pipefail` and propagates exit
  codes explicitly; each **module hook subshell** runs under `set -euo
  pipefail`. Fatal paths go through `die`.
- **Module isolation.** Each module hook runs in its own subshell, so one
  module's failure cannot poison the runner or sibling modules.
- **Fatal vs recoverable.** The runner distinguishes a *fatal* failure (stop
  safely, report, non-zero exit) from a *recoverable* one (log, skip that
  module, continue, summarize at the end). A module signals fatality via its
  exit code and a `die` helper.
- **No silent failures.** Every failure is logged and surfaced in the final
  summary.
- **Meaningful exit codes** (defined once in `internal/error.sh`):

  | Code | Meaning                         |
  |------|---------------------------------|
  | 0    | success                         |
  | 1    | general / unexpected failure    |
  | 2    | usage error (bad args)          |
  | 3    | unmet or cyclic dependency      |
  | 4    | a module hook failed (fatal)    |
  | 5    | unsupported environment         |

Every failure message answers three questions: **what happened, why, and how to
fix it.** This is a hard rule enforced through the `die` helper's signature.

---

## 9. Logging

A single logging system in `internal/log.sh` is reused by the runner and every
module. There is no ad-hoc `echo` for user-facing output.

- **Levels:** `debug`, `info`, `warn`, `error` (plus a `step` for section
  headers). A verbosity flag controls the floor.
- **Format:** consistent prefix with a timestamp and level, e.g.
  `2026-07-08T20:14:03  INFO  [git]  installing…`.
- **Colour when interactive.** Colour is applied only when stdout is a TTY;
  output is plain text when piped or redirected.
- **Persistent log file.** Every run also appends to
  `~/.local/state/atlas/logs/atlas-<date>.log`, so a failed unattended run is
  diagnosable after the fact.

API sketch (finalised during implementation):

```bash
log::step  "Installing core modules"
log::info  "git already present"
log::warn  "docker service not enabled"
log::error "failed to write ~/.gitconfig"
```

---

## 10. How a command flows through the system

Walkthrough of `atlas install`:

1. **`atlas`** parses global flags (`--verbose`, `--dry-run`, …) and the verb,
   then calls into `internal/runner.sh`.
2. **`runner.sh`** asks `internal/module.sh` to **discover** modules by scanning
   `modules/<category>/<name>/module.sh`.
3. **`module.sh`** reads each module's `MODULE_DEPENDS`, builds a dependency
   graph, and **topologically orders** the modules (a cycle is a fatal exit `3`).
4. For each module in order, the runner:
   - sources `module.sh` in a **subshell**,
   - runs `module::check`; if satisfied, logs and skips,
   - otherwise runs `module::install`, then `module::verify`,
   - records the outcome.
5. The runner prints a **summary** (installed / skipped / failed) and exits with
   a meaningful code.

`atlas verify`, `atlas backup`, etc. follow the same shape — only the hook that
gets fanned out changes. This uniformity is the point: to learn one verb is to
learn them all.

---

## 11. Adding a new module (the extension path)

1. Create `modules/<category>/<name>/`.
2. Write `module.sh` with metadata and at least `check` / `install` / `verify`.
3. Add a `config/` directory if the module owns any files.
4. Write a `README.md` answering: what it does, what it installs/configures, what
   it depends on.

No registration step, no edit to the runner, no central manifest. Discovery is
automatic; dependencies are declared in the module. This is the payoff of
convention over configuration — **where new functionality belongs is obvious.**

See `docs/module-authoring.md` for the annotated template.

---

## 12. Scope of v1

v1 delivers the **architecture and skeleton**, not installation logic:

- finalized architecture (this document),
- repository layout,
- the module contract,
- the `atlas` CLI skeleton and runner skeleton,
- placeholder modules that make future implementation obvious,
- coding conventions and architecture documentation.

Placeholder hooks are real functions that log "not yet implemented" and return
cleanly, so the skeleton runs end-to-end while doing no work. Real installation
logic lands module by module in subsequent milestones.
