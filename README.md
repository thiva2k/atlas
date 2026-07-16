# Atlas

[![Tests](https://github.com/thiva2k/atlas/actions/workflows/test.yml/badge.svg)](https://github.com/thiva2k/atlas/actions/workflows/test.yml)

**Atlas is a workstation lifecycle manager.** It takes a fresh Fedora machine to
a fully configured engineering workstation — and keeps it that way: installing
and configuring tooling, verifying health, and backing up and restoring the
irreplaceable bits.

Atlas is not a migration script, a dotfiles repo, or a package installer.
Those are *capabilities*, expressed as modules.

## Quick start

```bash
# On a fresh Fedora workstation:
curl -fsSL https://raw.githubusercontent.com/thiva2k/atlas/main/bootstrap.sh | bash

# If ~/.local/bin is already on PATH:
atlasctl install

# Otherwise:
cd ~/atlas
./atlasctl install
```

Read the full [Quick Start](docs/quick-start.md) and
[Installation](docs/installation.md) guides before provisioning a machine you
cannot easily recover.

## Commands

| Command | Does |
|---|---|
| `atlasctl install` | ensure modules are present & configured |
| `atlasctl update`  | bring modules to their latest desired state |
| `atlasctl verify`  | check modules are healthy |
| `atlasctl backup`  | capture irreplaceable module state |
| `atlasctl restore` | re-apply captured state |
| `atlasctl doctor`  | diagnose the workstation |
| `atlasctl status`  | show what is / isn't installed |
| `atlasctl self-update` | update Atlas itself from a managed checkout |
| `atlasctl self-version` | show Atlas engine version |
| `atlasctl self-verify` | verify Atlas self-management state |

Inside the repository, `./atlasctl <command>` remains supported. The managed global
launcher is `atlasctl` to avoid conflicting with other software that already
uses the `atlas` executable name.

## Documentation

- [Quick Start](docs/quick-start.md) — the shortest safe path from fresh Fedora
  to a managed workstation.
- [Installation](docs/installation.md) — bootstrap, PATH, self-management, and
  update details.
- [Architecture Overview](docs/architecture.md) — how the engine, runner,
  modules, markers, and self-management fit together.
- [Module Authoring](docs/module-authoring.md) — the contract for adding a
  production-quality module.
- [Philosophy of Atlas](docs/philosophy.md) — ownership, idempotency, security,
  and why Atlas behaves conservatively.
- [Roadmap](docs/roadmap.md) — planned v1.1, v1.2, and v2.0 direction.
- [RFC Index](docs/rfcs/README.md) — accepted design records.

## Architecture in one minute

Everything is a **module** under `modules/<category>/<name>/`, and every module
implements the same lifecycle hooks. The CLI dispatches a **platform
verb** to those modules through a small engine in `internal/`. Read
[`docs/architecture.md`](docs/architecture.md) for the full picture and
[`docs/module-authoring.md`](docs/module-authoring.md) to add one.

Atlas owns only the state it creates or the state a user explicitly hands to it.
Ownership is marker-based; Atlas does not infer ownership from a package,
binary, config file, or service merely existing on the machine.

## Requirements

- Fedora Linux.
- Bash.
- GNU coreutils and standard Fedora base utilities.
- Git. `bootstrap.sh` installs it if needed.

## Status

Atlas v1.0.0 is the first stable release. The module architecture is frozen,
the Core, Development, and current UX workstation modules are implemented, and
Atlas self-management is available for checkouts created by `bootstrap.sh`.
See [`CHANGELOG.md`](CHANGELOG.md).

## License

MIT — see [`LICENSE`](LICENSE).
