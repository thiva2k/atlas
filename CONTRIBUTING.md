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

> Test files are `source`d into one shell by `tests/run.sh`. `run.sh` resets
> `ATLAS_MODULES_DIR` to the real `modules/` dir before each file; a test that
> needs a fixtures dir must `export ATLAS_MODULES_DIR` itself (do not rely on a
> value left by another test file).

## Commits

Conventional commits (`feat:`, `fix:`, `docs:`, `test:`, …). Keep them small and
focused.
