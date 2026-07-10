# github-cli

**What it does:** Installs GitHub's official CLI (`gh`) and, if you supplied a
token out of band, logs it in — without ever prompting you.

**Installs / configures:**
- the `gh` package (via `dnf`, only when `gh` is absent)
- a GitHub login, **only** when you supplied `ATLAS_GH_TOKEN`

**Depends on:** `core/git`.

**Design:** [RFC-0003](../../../docs/rfcs/RFC-0003-github-cli-module.md).

## Atlas manages none of `gh`'s configuration

This module owns no files. It never runs `gh config`, never reads or creates
`config.yml`, and never touches your `~/.gitconfig`.

That is a decision, not an oversight. Atlas used to set `git_protocol = ssh` on a
fresh install, which sounds harmless and is not: under SSH, *every* `gh repo
clone` needs a key registered on GitHub — including public repositories, which
`gh` clones anonymously over HTTPS with no setup at all. A default that only pays
off once you finish a later step, and quietly costs you until then, is a bad
default. `gh`'s own is better.

If you want SSH, it is one command:

```sh
gh config set git_protocol ssh
```

## Authentication

`gh auth login` is interactive. Atlas is not. So Atlas will authenticate for you
only from a token you supplied yourself, and it will **never prompt, never store a
token of its own, and never fail an install because you have not logged in.**

Give it a token by exporting `ATLAS_GH_TOKEN`, or by putting it in
`~/.config/atlas/atlas.env`:

```sh
ATLAS_GH_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx
```

That file must be mode `600`. If it is readable by anyone else, Atlas **refuses to
use the secret** — it warns, tells you to `chmod 600`, and carries on as if no
token were there. A credential that has already leaked is not one Atlas will build
on.

Without a token, `install` succeeds and tells you to run `gh auth login` yourself.
That is the "minimal manual authentication step where security demands it".

**If `GH_TOKEN` or `GITHUB_TOKEN` is exported in your shell,** `gh` is already
authenticated from it and Atlas leaves it alone — `gh auth login` actually refuses
to run in that state. Be aware that this login is *ephemeral*: it lives only as
long as that environment variable does, and vanishes with the shell. Nothing is
written to disk.

### What Atlas never does with your token

- never passes it as a command-line argument (it goes to `gh` on **stdin**, so it
  never appears in `/proc/*/cmdline`)
- never writes it to a file Atlas owns, and never to this repo
- never prints it — not in a log line, not in an error, not under `set -x`

A token that `gh` rejects **fails** the install, loudly. `gh` validates over the
network, so a bad token and an unreachable GitHub look identical; Atlas would
rather stop than report a workstation as provisioned when its GitHub access is not.

## HTTPS users: run `gh auth setup-git` yourself

`gh auth setup-git` teaches Git to use `gh` as a credential helper for HTTPS
pushes. It is genuinely useful, and Atlas still will not run it, because it writes
into `~/.gitconfig` — a file owned by the `core/git` module. Atlas modules do not
edit each other's configuration, and an edit made by `gh`'s own writer is one
Atlas could neither validate, track, nor revert.

It is one command, and it is yours to run:

```sh
gh auth setup-git
```

## Lifecycle

| Hook | What happens |
|---|---|
| `check` | `gh` is installed, **and** it is not the case that you supplied a token while `gh` is logged out |
| `install` | install `gh` if absent → authenticate from your token if there is one, else warn |
| `verify` | `gh --version` works; auth state is reported, never enforced |
| `update` | nothing — package currency is `dnf`'s job, and Atlas owns no configuration |
| `backup` / `restore` | nothing — see below |

`check` deliberately says nothing about `gh`'s configuration, because Atlas owns
none of it. It *does* fail when you have supplied a token and `gh` is logged out,
because that is work `install` can do — and the runner skips `install` entirely
whenever `check` passes.

One consequence worth knowing: on a box where `gh` is installed and you never
supplied a token, `atlas install` skips this module silently. The "installed but
not authenticated" warning shows up under `atlas verify` and `atlas doctor`.

`backup` and `restore` do nothing on purpose. `gh`'s only state is an OAuth token
in `hosts.yml` — regenerating one is cheap, leaking one is not, so Atlas will not
copy it into a backup artifact. `config.yml` is not Atlas's to back up either.
Modules that hold state you *cannot* regenerate — `core/ssh`, whose private key is
your identity — do implement real, encrypted backup.

There is no `remove` hook. Atlas wrote nothing it owns, so there is nothing to
revert, and it will not delete a credential you granted or a package your other
tools depend on.

## Testing

Every test sandboxes `HOME`, `GH_CONFIG_DIR`, and `ATLAS_CONFIG_HOME` into a fresh
temp directory, mocks `os::dnf_install`, and replaces `gh` with a shell function
that records its argv **and its stdin** — which is how the suite proves the token
reaches `gh` on stdin and appears nowhere else. No test runs real `dnf`, real
`gh`, or touches your real `$HOME`. Run it on Linux:

```sh
bash tests/run.sh
```
