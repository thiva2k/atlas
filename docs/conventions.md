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

## User-specific configuration

Some settings are the user's, not Atlas's — an identity, a token, a hostname.
Atlas never prompts for them and never guesses. A module reads them with
`env::get NAME` (`internal/env.sh`), which resolves, in order:

1. the environment variable `NAME`
2. the key `NAME=value` in `$ATLAS_CONFIG_HOME/atlas.env`
   (default `~/.config/atlas/atlas.env`)

and returns non-zero when neither is set. Rules:

- **Namespace the key** after the module: `ATLAS_GIT_USER_NAME`, not `USER_NAME`.
- **Never block on a missing value.** `warn` and continue; a missing optional
  value is not an install failure, and never a `verify` failure.
- **Never overwrite a value the user already set** by hand. Apply it only when
  the target is unset.
- `atlas.env` holds secrets. It is the user's file; Atlas reads it, never writes it.

## Owning configuration a module does not own

A module writes its own settings into a file it *owns*, under
`$ATLAS_CONFIG_HOME/<module>/`, and then wires that file into the tool's real
configuration with the smallest possible edit (an include, a source line, a
drop-in). This keeps `update` and `remove` tractable: Atlas can regenerate or
delete its own file without ever parsing the user's.

Where the tool resolves configuration positionally, the Atlas fragment goes
**first**, so the user's own settings — read later — override Atlas's defaults.
Atlas provides defaults; the user always wins.

When a module must edit a user-owned file anyway:

- validate first, write second: every refusal (`die`, exit `ATLAS_EXIT_MODULE`)
  must happen *before* anything is modified;
- one atomic write (temp file in the same directory, then `mv`), preserving mode;
- resolve symlinks and edit the target, so dotfile managers keep working;
- take whatever lock the tool itself uses, and never steal one you did not create.

`modules/core/git/` is the reference implementation of all of the above.
