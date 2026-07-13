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

# after bootstrap, if ~/.local/bin is on PATH
atlasctl install
```

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

Inside the repository, `./atlas <command>` remains supported. The managed global
launcher is `atlasctl` to avoid conflicting with other software that already
uses the `atlas` executable name.

## How it works

Everything is a **module** under `modules/<category>/<name>/`, and every module
implements the same lifecycle hooks. The CLI dispatches a **platform
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
