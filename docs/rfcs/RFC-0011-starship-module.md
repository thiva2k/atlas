# RFC-0011: Starship Prompt Theme Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `development/starship` as Atlas's prompt theme contract for the experience
layer.

The module owns an Atlas-scoped Starship configuration file and an install
marker. It does not install Starship, does not activate Starship in any shell,
and does not modify user shell startup files. This keeps prompt presentation
independent from Fish, Bash, Zsh, Ghostty, and future shell modules.

## Context

The experience layer requires a quiet engineering prompt that displays only:

- current directory
- Git branch
- Git status
- command duration
- Python
- Node
- Docker context
- time

Starship's upstream configuration documentation defines
`~/.config/starship.toml` as the default config and `STARSHIP_CONFIG` as the
supported override mechanism. Atlas must not write the user default config or
shell startup files, because those are user-owned or future shell-module-owned
surfaces.

Fedora package metadata available to the project does not provide a deterministic
`starship` package at this time. Downloading an upstream binary would add a
separate binary distribution lifecycle, checksums, architecture mapping, and
upgrade policy that this phase does not need.

## Decision

Create `development/starship`.

Atlas owns:

- `$ATLAS_CONFIG_HOME/starship/starship.toml`
- `$ATLAS_STATE_DIR/installed/development-starship`
- the prompt format and palette inside the Atlas config
- verification of the managed config

Atlas does not own:

- the `starship` binary
- `~/.config/starship.toml`
- Fish, Bash, or Zsh startup files
- shell integration snippets
- user prompt themes
- Starship cache files

The future Fish module may opt into this prompt by exporting
`STARSHIP_CONFIG="$ATLAS_CONFIG_HOME/starship/starship.toml"` before invoking
Starship init. Until then, installation prepares the managed prompt but does not
force it into any shell.

## Configuration Contract

The managed config uses an explicit `format` instead of `$all`, so decorative
and low-value modules stay hidden.

The config must:

- disable the leading blank line
- keep scan and command timeouts low
- use a restrained Atlas-blue palette
- avoid custom command modules
- avoid shell-specific prompt escape sequences
- avoid decorative symbols and emoji
- use only Starship built-in modules

## Verification Contract

`verify` succeeds when:

- the module has never been installed by Atlas
- the module is detached
- Atlas owns the module and the managed config matches Atlas source
- Atlas owns the module, Starship is present, and Starship accepts the managed
  config

`verify` fails only when Atlas owns the module and managed state is broken:

- marker malformed, insecure, or incomplete
- marker indicates an incomplete install
- managed config missing, symlinked, or drifted
- Starship is present but rejects the managed config

Starship absence is not a verification failure for this module, because binary
installation is intentionally outside this contract until a deterministic
Fedora-packaged lifecycle exists.

## Dependency Model

`development/starship` has no current Atlas module dependency.

Future integration points:

- a future Fish module owns shell activation
- a future Starship binary module may own binary installation if Fedora package
  availability becomes deterministic
- Ghostty remains independent and only hosts the shell

## Backup and Restore

`backup` and `restore` are documented no-ops. The managed config is
reconstructable from the repository, and user prompt configuration is outside
Atlas ownership.

## Remove Behavior

`remove` deletes only the Atlas-owned Starship config when it matches the
repository source, then writes a detached marker.

`remove` refuses to delete a drifted config. A drifted config may contain user
changes, so Atlas must not silently destroy it.

## Idempotency

Repeated `install`, `verify`, `doctor`, `status`, `update`, and `remove` must be
stable.

A second `install` over unchanged managed state performs no meaningful work and
leaves the marker/config bytes unchanged.

## Architecture Review

Ownership: Writing only under `$ATLAS_CONFIG_HOME/starship` avoids user-owned
`~/.config/starship.toml` and shell startup files.

Lifecycle: Config lifecycle is independent from binary lifecycle, preventing an
unreviewed upstream-binary installer from entering Atlas.

Security: No custom Starship command modules are allowed. This avoids prompt-time
shell execution and prevents the config from becoming a command injection
surface.

Idempotency: Marker hashes bind Atlas ownership to the exact managed config
source.

Extensibility: Future Fish or Starship binary modules can consume the managed
config without changing this module's ownership model.

## Validation Matrix

- clean Fedora installation
- unmanaged Starship binary
- unmanaged user `~/.config/starship.toml`
- Atlas-managed install
- repeated install
- repeated verify
- doctor
- status
- remove hook
- detached reinstall with user-created Atlas path
- configuration drift
- marker corruption
- marker mode regression
- Starship command failure
- Starship missing
- unsupported environments
- backup and restore no-ops
- full suite regression

