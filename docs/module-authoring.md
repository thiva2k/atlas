# Module Authoring

A module is a self-contained workstation capability. Adding one should not
require a runner change, a shared framework change, or a new global registry.
Discovery is automatic.

If a module cannot fit the existing contract, stop and write an RFC. Do not work
around the engine.

## Authoring workflow

1. Read `docs/architecture.md`, `docs/conventions.md`, this guide, and the
   relevant RFCs.
2. Create an RFC if the module does not already have one.
3. Define ownership boundaries before writing code.
4. Design the validation matrix.
5. Add tests before implementation.
6. Implement the smallest module-local change that satisfies the RFC.
7. Run syntax checks, `git diff --check`, module tests, and the full suite.
8. Perform real Fedora validation for modules that install or configure system
   software.

## Directory layout

```text
modules/<category>/<name>/
├── module.sh
├── README.md
└── config/        # optional module-owned templates/data
```

Categories in v1 are `core`, `development`, `apps`, and `desktop`. The category
is the directory. Do not declare it separately.

Files that change together live together. A module's templates, repository
files, signing keys, fragments, or static assets belong beside the module that
owns them.

## Required metadata

```bash
#!/usr/bin/env bash
MODULE_NAME="example"
MODULE_DESCRIPTION="One line: what this capability is."
MODULE_DEPENDS=() # e.g. ("core/git")
```

Dependencies use `category/name` identifiers. The runner resolves and orders
them; modules must not call sibling modules directly.

## Required hooks

```bash
module::check()   { ...; }
module::install() { ...; }
module::verify()  { ...; }
```

Hook contract:

- `check` returns `0` only when the module is already satisfied.
- `install` makes the module satisfied and must be safe to repeat.
- `verify` returns `0` for healthy managed state and for unmanaged or
  never-installed state.
- `verify` returns non-zero only when Atlas owns the module and managed state is
  broken.

Optional hooks:

```bash
module::update()  { ...; }
module::remove()  { ...; }
module::backup()  { ...; }
module::restore() { ...; }
```

If an optional hook is meaningful, implement it. If the module owns no
restorable state, document the hook as a no-op so the lifecycle is explicit.

## Ownership rules

Every module must answer:

- What does Atlas own?
- What remains user-owned?
- What is installation state?
- What is configuration state?
- What is runtime state?
- What is disposable state?
- What does `verify` prove?
- What does Atlas refuse to manage?

Atlas never infers ownership from a command, package, service, or file existing.
Use markers or an explicit RFC-approved adoption path.

Removal must touch only Atlas-owned resources. Backups must capture only
irreplaceable Atlas-owned or explicitly adopted state.

## Shell discipline

Module hooks run under the runner's hook invocation pattern. Do not rely on
`set -e` to abort a hook. Every fallible mutation needs an explicit check:

```bash
if ! os::dnf_install example; then
  log::error "failed to install example"
  return 1
fi
```

Rules:

- quote expansions;
- keep user-facing output on `log::*`, not stdout;
- validate before mutating;
- use same-directory temporary files before `mv`;
- clean temporary files with module-scope cleanup helpers;
- never log secrets;
- never pass secrets in argv;
- avoid runtime dependencies unless an RFC justifies them.

See `docs/conventions.md` for the detailed shell and secret rules.

## README requirements

Each module README must document:

- what the module provides;
- what Atlas owns;
- what Atlas does not own;
- dependencies;
- install, verify, update, remove, backup, and restore behavior;
- security notes;
- known limitations.

The README is part of the module contract. If behavior changes, update the
README in the same change.

## Test requirements

Add tests under `tests/test_<area>.sh`. Use the existing pure-Bash test harness
and assertions in `tests/lib/assert.sh`.

Cover at least:

- fresh Fedora / never-installed state;
- externally installed but unmanaged state;
- Atlas-managed healthy state;
- broken Atlas-managed state;
- repeated install;
- repeated verify;
- doctor and status behavior;
- remove/update/backup/restore hooks where applicable;
- permission and package failure paths;
- regressions for every bug discovered.

Run:

```bash
bash -n modules/<category>/<name>/module.sh
git diff --check
bash tests/run.sh
```

For system-modifying modules, also validate on real Fedora:

```bash
atlasctl install <category>/<name>
atlasctl verify <category>/<name>
atlasctl doctor <category>/<name>
atlasctl status <category>/<name>
atlasctl install <category>/<name>
```

The second install must perform no unintended work.
