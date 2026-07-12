# Atlas Autonomous Engineering Pipeline

This repository is governed by the Atlas architecture and module contract.
Before changing code, read and treat these documents as normative:

- `docs/architecture.md`
- `docs/conventions.md`
- `docs/module-authoring.md`
- `docs/rfcs/`
- `CONTRIBUTING.md`

The Atlas architecture is frozen unless changed through an approved RFC. If an
implementation requires an engine or architecture change, stop and explain why
instead of implementing around it.

## Module workflow

Work on one module at a time. Complete these phases in order:

1. Architecture — create an RFC if none exists.
2. Architecture review — resolve ownership, lifecycle, dependency, security,
   idempotency, and maintenance concerns before implementation.
3. Test design — define the validation matrix before code.
4. Test-driven development — add failing tests before implementation.
5. Implementation review — audit correctness, security, shell robustness,
   ownership, rollback, privilege, and idempotency.
6. Repository audit — fix only related architectural inconsistencies that
   preserve the current architecture.
7. Validation — run syntax checks, `git diff --check`, module validation, the
   full suite, and real Fedora validation when applicable.
8. Deliverable — produce an engineering report with recommendation.

## Standing principles

- Atlas owns only what Atlas creates.
- Atlas never assumes ownership from tool or package existence alone.
- Ownership is determined by Atlas-managed state.
- Atlas never silently overwrites user configuration.
- Atlas never weakens Fedora security defaults.
- Atlas never deletes user data without explicit ownership.
- A fresh Fedora installation is always valid state.
- `verify` succeeds for healthy managed state and for never-installed state.
- `verify` fails only when Atlas owns the installation and managed state is broken.
- Every production bug receives a regression test.
- Favor deterministic, maintainable, minimal solutions over cleverness.

## Current module sequence

After `development/python`, the intended follow-on modules are:

1. `development/uv` — depends on Python.
2. Node.js and pnpm.
3. Claude Code.
4. Codex.
