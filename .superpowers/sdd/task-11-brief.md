### Task 11: Top-level docs + conventions + architecture reconciliation

**Files:**
- Create: `README.md`
- Create: `LICENSE` (MIT, 2026, thiva2k)
- Create: `CONTRIBUTING.md`
- Create: `CHANGELOG.md`
- Create: `docs/conventions.md`
- Create: `docs/module-authoring.md`
- Modify: `docs/architecture.md` (reconcile testing note: pure-Bash harness, not bats; and strict-mode wording)

**Interfaces:**
- Produces: the reader-facing documentation set. No code; the deliverable is that a new contributor can read `README.md` → `docs/architecture.md` → `docs/module-authoring.md` and understand the system and how to extend it in ~10 minutes.

- [ ] **Step 1: Write `README.md`**

```markdown
# Atlas

**Atlas is a workstation lifecycle manager.** It takes a fresh Fedora machine to
a fully configured engineering workstation — and keeps it that way: installing
and configuring tooling, verifying health, and backing up and restoring the
irreplaceable bits.

Atlas is not a migration script, a dotfiles repo, or a package installer.
Those are *capabilities*, expressed as modules.

## Quick start

```bash
# on a fresh machine
curl -fsSL https://raw.githubusercontent.com/thiva2k/atlas/main/bootstrap.sh | bash
cd ~/atlas
./atlas install
```

## Commands

| Command | Does |
|---|---|
| `atlas install` | ensure modules are present & configured |
| `atlas update`  | bring modules to their latest desired state |
| `atlas verify`  | check modules are healthy |
| `atlas backup`  | capture irreplaceable module state |
| `atlas restore` | re-apply captured state |
| `atlas doctor`  | diagnose the workstation |
| `atlas status`  | show what is / isn't installed |

## How it works

Everything is a **module** under `modules/<category>/<name>/`, and every module
implements the same lifecycle hooks. The `atlas` CLI dispatches a **platform
verb** to those modules through a small engine in `internal/`. Read
[`docs/architecture.md`](docs/architecture.md) for the full picture and
[`docs/module-authoring.md`](docs/module-authoring.md) to add one.

## Requirements

Bash, GNU coreutils, Git, and a Fedora base system. Nothing else.

## Status

v1 is the **skeleton**: the architecture, CLI, runner, and placeholder modules
are in place; real installation logic lands module by module. See
[`CHANGELOG.md`](CHANGELOG.md).

## License

MIT — see [`LICENSE`](LICENSE).
```

- [ ] **Step 2: Write `LICENSE`** — standard MIT text, `Copyright (c) 2026 thiva2k`.

- [ ] **Step 3: Write `CONTRIBUTING.md`**

```markdown
# Contributing to Atlas

## Principles

Simplicity over cleverness. One responsibility per file. Explicit over implicit.
Zero runtime dependencies beyond Bash + coreutils + Git. Documentation is part
of the change, not an afterthought.

## Ground rules

- Every shell file starts with `#!/usr/bin/env bash`.
- User-facing output goes through the `log::*` API — never bare `echo`.
- Shared helpers live in `internal/`; capabilities live in `modules/`.
- The runner must never reach inside a module — only call contract hooks.
- Line endings are LF (enforced by `.gitattributes`).

## Adding a module

See [`docs/module-authoring.md`](docs/module-authoring.md).

## Tests

Run the whole suite with:

```bash
bash tests/run.sh
```

Tests are pure Bash (no framework). Add `tests/test_<area>.sh` and use the
assertions in `tests/lib/assert.sh`. Every behavioural change ships with a test.

## Commits

Conventional commits (`feat:`, `fix:`, `docs:`, `test:`, …). Keep them small and
focused.
```

- [ ] **Step 4: Write `CHANGELOG.md`**

```markdown
# Changelog

All notable changes to Atlas are documented here. Format loosely follows
[Keep a Changelog]; Atlas uses semantic versioning once it hits 1.0.

## [Unreleased]

### Added
- v1 skeleton: architecture, `atlas` CLI, module runner, and the `internal/`
  engine (logging, errors, OS helpers, module contract, dependency resolution).
- Eight placeholder modules across core / development / apps / desktop.
- Zero-dependency `bootstrap.sh`.
- Pure-Bash test harness under `tests/`.

[Keep a Changelog]: https://keepachangelog.com/
```

- [ ] **Step 5: Write `docs/conventions.md`**

```markdown
# Coding Conventions

These keep Atlas readable enough to understand in ten minutes.

## Bash

- `#!/usr/bin/env bash` on every script.
- Entry points: `set -uo pipefail`. Module hook subshells: `set -euo pipefail`.
- Quote expansions: `"$var"`, `"${array[@]}"`.
- Small functions, one job each. If a function needs a comment to explain a
  second responsibility, split it.
- No global mutable state beyond documented `ATLAS_*` variables.
- Prefer Bash builtins and coreutils; never add a runtime dependency.

## Naming

- Modules: `lower-kebab` directory names under a category.
- Functions: `snake_case`; namespaced APIs use `::` (`log::info`, `module::path`,
  `os::has_cmd`, `runner::run`). Module hooks are `module::<hook>`.
- Environment / globals: `UPPER_SNAKE`, prefixed `ATLAS_`.
- Private helpers: leading underscore (`_log_emit`, `_runner_run_module`).

## Output & errors

- All user output via `log::*`. Machine output (`--version`) may use `echo`.
- Fatal failures go through `die <code> <what> [why] [how]`.
- Exit codes are defined once in `internal/error.sh`.

## Files

- `internal/` = the engine, shared, module-agnostic.
- `modules/<category>/<name>/` = one capability, self-contained.
- Files that change together live together.
```

- [ ] **Step 6: Write `docs/module-authoring.md`**

````markdown
# Authoring a Module

A module is a self-contained capability. Adding one needs **no** change to the
runner — discovery is automatic.

## 1. Create the directory

```
modules/<category>/<name>/
```

Categories in v1: `core`, `development`, `apps`, `desktop`. The category is the
directory — nothing declares it.

## 2. Write `module.sh`

```bash
#!/usr/bin/env bash
MODULE_NAME="example"
MODULE_DESCRIPTION="One line: what this capability is."
MODULE_DEPENDS=()            # e.g. ("core/git"); ids are "category/name"

# Required hooks --------------------------------------------------------------

# 0 = already present & configured (install is skipped); non-0 = work needed.
module::check() {
  os::has_cmd example
}

# Make it so. Safe to run repeatedly.
module::install() {
  os::dnf_install example
}

# 0 = healthy; non-0 = broken (surfaced by `atlas verify` / `doctor`).
module::verify() {
  os::has_cmd example
}

# Optional hooks: module::update, module::remove, module::backup, module::restore
```

## 3. Add `config/` (optional)

Any files the module owns live in `config/` beside it — never in a shared
top-level directory.

## 4. Write `README.md`

Answer three questions: what it does, what it installs/configures, what it
depends on.

## 5. Test it

```bash
bash atlas status <category>/<name>
bash atlas install <category>/<name>
bash tests/run.sh
```

That's the whole contract. If you ever feel the need to reach into another
module's internals, the contract is missing something — extend the contract
instead.
````

- [ ] **Step 7: Reconcile `docs/architecture.md`**

In §5 change the `tests/` comment and in §9/§8 wording to match the built reality. Replace the line:

```
├── tests/                # contributor test suite (dev-only dependency)
```

with:

```
├── tests/                # pure-Bash test harness (no external framework)
```

And in §8 replace "Every entry point runs under `set -euo pipefail` plus an `ERR` trap installed by `internal/error.sh`." with:

```
- The `atlas` entrypoint runs under `set -uo pipefail` and propagates exit
  codes explicitly; each **module hook subshell** runs under `set -euo
  pipefail`. Fatal paths go through `die`.
```

Also update §12's bats-free reality if any mention remains (there is none — confirm).

- [ ] **Step 8: Verify the docs render and links resolve**

Run: `bash tests/run.sh` (still green) and manually confirm the referenced files exist:
`ls README.md LICENSE CONTRIBUTING.md CHANGELOG.md docs/conventions.md docs/module-authoring.md docs/architecture.md`
Expected: all listed, suite `0 failed`.

- [ ] **Step 9: Commit**

```bash
git add README.md LICENSE CONTRIBUTING.md CHANGELOG.md docs/
git -c commit.gpgsign=false commit -m "docs: add README, license, contributing, changelog, and guides

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 10: Push everything**

```bash
git push -u origin main
```

---

## Self-Review (completed by plan author)

**1. Spec coverage** — architecture.md §-by-§:
- §3 verbs + hooks → Tasks 7 (runner verb→hook map), 8 (CLI verbs), 9 (module hooks). ✔
- §4 zero-dep policy → Global Constraints + pure-Bash harness (Task 1), no framework. ✔
- §5 layout (`atlas bootstrap.sh internal/ modules/ docs/ tests/ assets/` + root docs) → Tasks 1–11. `assets/` has no content in v1 (nothing needs it yet — YAGNI); created lazily when a module ships an asset. Noted, not silently dropped.
- §6 module anatomy (module.sh/config/README) → Task 9. ✔
- §7 contract (metadata vars, `module::` hooks, return codes, subshell isolation) → Tasks 5, 6, 7, 9. ✔
- §8 error handling + exit codes → Task 3; reconciled wording Task 11. ✔
- §9 logging → Task 2. ✔
- §10 command flow → realized by Tasks 7–9; smoke-tested Task 9 Step 8. ✔
- §11 extension path → `docs/module-authoring.md` Task 11. ✔
- §12 v1 scope (skeleton, placeholders) → whole plan. ✔

**2. Placeholder scan** — module hooks intentionally call `not_implemented`; that is the *specified* v1 behaviour (§12), not a plan placeholder. No "TBD"/"implement later" as plan instructions; every code step has complete content.

**3. Type/name consistency** — verified across tasks: `log::debug|info|warn|error|step`, `die`, `ATLAS_EXIT_*`, `os::has_cmd|require_cmd|is_fedora|is_root|dnf_install|flatpak_install`, `module::discover|path|has_hook|deps_of|resolve_order`, `not_implemented`, `_runner_hooks_for_verb|_runner_run_module|runner::run`, `ATLAS_ROOT|ATLAS_MODULES_DIR|ATLAS_STATE_DIR|ATLAS_LOG_LEVEL|ATLAS_LOG_SCOPE`. Names match between definition and use.

**Note:** `assets/` is created only when a module first needs it (YAGNI). If you want the empty directory present now for structural completeness, add a `assets/.gitkeep` in Task 1.
