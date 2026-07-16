# Installation

Atlas supports two execution modes:

- `atlasctl` — the managed global launcher installed at `~/.local/bin/atlasctl`;
- `./atlasctl` — repository-local execution from inside the checkout.

The global launcher is named `atlasctl` because Fedora already has unrelated
software that may provide `/usr/bin/atlas`. Atlas does not compete for that
command name.

## Requirements

- Fedora Linux.
- Bash and standard GNU utilities.
- Git. `bootstrap.sh` installs Git through Fedora package management if needed.
- Network access to `github.com` for the default bootstrap and self-update path.

Atlas has no Python, Ansible, YAML parser, `jq`, `make`, or framework runtime
dependency.

## Standard install

```bash
curl -fsSL https://raw.githubusercontent.com/thiva2k/atlas/main/bootstrap.sh | bash
export PATH="$HOME/.local/bin:$PATH"
atlasctl install
```

The bootstrap target defaults to:

```text
Repository: https://github.com/thiva2k/atlas.git
Path:       ~/atlas
Launcher:   ~/.local/bin/atlasctl
Branch:     main
```

## Custom checkout path

Set `ATLAS_HOME` before bootstrap:

```bash
ATLAS_HOME="$HOME/src/atlas" \
  curl -fsSL https://raw.githubusercontent.com/thiva2k/atlas/main/bootstrap.sh | bash
```

Atlas self-management is recorded only when bootstrap creates a canonical
managed checkout. Existing directories are left alone.

## Existing checkout

If you already cloned Atlas:

```bash
cd /path/to/atlas
./atlasctl install
```

This works, but `atlasctl self-update` may refuse until the checkout has a valid
self-management marker. That refusal is intentional: Atlas will not guess that
an arbitrary repository is safe for engine self-management.

## Updating Atlas

Use:

```bash
atlasctl self-update
```

Optional validation levels:

```bash
atlasctl self-update --verify     # includes the full Atlas test suite
atlasctl self-update --full-test  # alias for full test validation
```

Before mutating the checkout, self-update validates:

- the managed marker exists and is parseable;
- the running executable matches the recorded managed launcher;
- the remote identity is `github.com/thiva2k/atlas`;
- the branch is `main`;
- the working tree and index are clean;
- the update is fast-forward-only.

If any precondition fails, Atlas refuses the update. It does not recover,
rewrite history, switch branches, or adopt another checkout.

## Uninstalling Atlas

Atlas v1 does not provide an engine uninstall command. If you want to remove the
checkout and launcher manually, inspect what exists first:

```bash
ls -l "$HOME/.local/bin/atlasctl"
ls -ld "$HOME/atlas"
```

Then remove only those Atlas-owned paths if they match your installation:

```bash
rm "$HOME/.local/bin/atlasctl"
rm -rf "$HOME/atlas"
```

Do not remove `~/.local/state/atlas` or `~/.config/atlas` blindly if you have
backups, logs, module state, or user-managed configuration you still need.

## Troubleshooting

### `atlas` runs the wrong program

Use `atlasctl`, not `atlas`.

```bash
command -v atlas
command -v atlasctl
```

On Fedora, `/usr/bin/atlas` may be a different package. Atlas intentionally uses
`atlasctl` globally to avoid that conflict.

### `atlasctl self-update` refuses managed state

Run:

```bash
atlasctl self-verify
git -C "$HOME/atlas" status --short --branch
git -C "$HOME/atlas" remote -v
```

Refusal usually means the checkout is dirty, not on `main`, has the wrong
remote, was not created by bootstrap, or the launcher points somewhere else.
