# Quick Start

Atlas turns a clean Fedora workstation into a managed engineering workstation.
The normal public command is `atlasctl`. Repository-local execution remains
available as `./atlasctl`.

## 1. Bootstrap Atlas

Run this on Fedora:

```bash
curl -fsSL https://raw.githubusercontent.com/thiva2k/atlas/main/bootstrap.sh | bash
```

The bootstrap script:

- ensures Git is present;
- clones `https://github.com/thiva2k/atlas.git` to `~/atlas` when missing;
- installs a managed launcher at `~/.local/bin/atlasctl`;
- records a self-management marker only for the canonical `main` checkout.

It does not adopt arbitrary existing clones.

## 2. Ensure `atlasctl` is on `PATH`

Most Fedora desktop sessions include `~/.local/bin` automatically after login.
If the current shell does not see it yet:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Confirm the launcher:

```bash
command -v atlasctl
readlink -f "$(command -v atlasctl)"
```

Expected target:

```text
/home/<user>/.local/bin/atlasctl
/home/<user>/atlas/atlas
```

If `atlasctl` is unavailable, use repository-local execution:

```bash
cd ~/atlas
./atlasctl help
```

## 3. Install the workstation

```bash
atlasctl install
```

or, from the repository:

```bash
cd ~/atlas
./atlasctl install
```

Atlas runs modules in dependency order. It installs only managed resources and
refuses to silently take ownership of user configuration.

## 4. Validate the workstation

```bash
atlasctl verify
atlasctl doctor
atlasctl status
```

Then run the install again:

```bash
atlasctl install
```

The second run should report modules as already satisfied or intentionally
skipped. It must not perform unintended work.

## 5. Update Atlas itself

For checkouts created by `bootstrap.sh`:

```bash
atlasctl self-verify
atlasctl self-update
```

To run the full test suite after updating:

```bash
atlasctl self-update --verify
```

`self-update` fails closed if the repository is dirty, on the wrong remote,
on the wrong branch, not fast-forwardable, or if the current executable does
not match the managed launcher recorded in the marker.

## What success looks like

A healthy v1 workstation reports:

- `atlasctl install` completes without failed modules;
- a repeated `atlasctl install` performs no unintended work;
- `atlasctl verify` exits successfully;
- `atlasctl doctor` exits successfully;
- `atlasctl status` shows installed modules and valid skipped modules.

Warnings can still be correct. For example, Atlas may report an external SSH key
that it does not own, or an intentionally unimplemented future module.
