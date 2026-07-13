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
| `atlas self-update` | update Atlas itself from a managed checkout |

## How it works

Everything is a **module** under `modules/<category>/<name>/`, and every module
implements the same lifecycle hooks. The `atlas` CLI dispatches a **platform
verb** to those modules through a small engine in `internal/`. Read
[`docs/architecture.md`](docs/architecture.md) for the full picture and
[`docs/module-authoring.md`](docs/module-authoring.md) to add one.

## Requirements

Bash, GNU coreutils, Git, and a Fedora base system. Nothing else.

## Status

Atlas is in the v1 beta track. The module architecture is stable, the Core &
Development workstation modules are implemented, and Atlas self-management is
available for checkouts created by `bootstrap.sh`. See [`CHANGELOG.md`](CHANGELOG.md).

## License

MIT — see [`LICENSE`](LICENSE).
