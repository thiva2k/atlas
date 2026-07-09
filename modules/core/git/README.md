# git

**What it does:** Installs Git and layers Atlas's opinionated defaults *underneath*
your own global configuration.

**Installs / configures:**
- the `git` package (via `dnf`, only when Git is absent)
- an Atlas-owned config fragment at `~/.config/atlas/git/gitconfig`
- one `include.path` directive at the **top** of your `~/.gitconfig`
- optionally `user.name` / `user.email`, only if they are not already set

**Depends on:** nothing.

**Design:** [RFC-0001](../../../docs/rfcs/RFC-0001-git-module.md).

## Atlas provides defaults; you always win

Atlas never edits your settings. It writes its own fragment and points your
`~/.gitconfig` at it with a single directive placed **before** everything else:

```ini
[include]
	path = "/home/you/.config/atlas/git/gitconfig"

# …your configuration, untouched, below…
```

Git resolves configuration positionally — the last value read wins — and expands
an include where the directive sits. Because the include comes first, anything
you set below it overrides the Atlas default. Set `pull.rebase = false` in your
own config and it stays `false`.

The corollary: `atlas verify git` checks that the fragment is intact and that Git
*resolves* it. It does **not** check that Atlas's value is the winning one,
because for any key you have overridden it deliberately is not.

The managed defaults live in [`config/gitconfig`](config/gitconfig):
`init.defaultBranch`, `pull.rebase`, `push.default`, `push.autoSetupRemote`,
`fetch.prune`, `rebase.autostash`, `color.ui`.

## Identity

`user.name` and `user.email` are yours, not Atlas's, so Atlas only fills them in
when they are missing. It reads them from the environment first, then from
`~/.config/atlas/atlas.env`:

```sh
ATLAS_GIT_USER_NAME=Ada Lovelace
ATLAS_GIT_USER_EMAIL=ada@example.com
```

Neither is required. With no identity available, `install` warns and continues —
a missing identity is not an install failure, and never a `verify` failure. An
identity you have already set is never overwritten.

## Lifecycle

| Verb | What happens |
|---|---|
| `check` | Git present, fragment readable, and the include is the **first** section |
| `install` | install Git if absent → write the fragment → wire the include → fill in identity if missing |
| `verify` | `git --version` works, the fragment is intact, and Git resolves it |
| `update` | re-apply the fragment (picks up new Atlas defaults) and re-check the include |
| `remove` | drop the include and delete the fragment |

`backup` / `restore` are intentionally **not implemented**: the fragment is
regenerable, and everything else in `~/.gitconfig` belongs to you, not to Atlas.
Omitting a hook you do not need is correct — the runner simply skips it.

`update` does not upgrade the Git package, and `remove` does not uninstall it
(shared, high blast radius) or touch your identity. `remove` restores your
`~/.gitconfig` byte-for-byte.

`check` requires the include to be *first*, not merely present, because the runner
skips `install` whenever `check` passes. That is what lets a config wired up by an
older, buggy Atlas migrate itself on the next run.

## Editing your global config safely

Atlas has to modify a file it does not own, so it is careful:

- the rewrite is a **single atomic write** (temp file in the same directory, then
  `mv`), so a crash leaves your old file intact
- the file's **mode is preserved** (a `600` config stays `600`)
- a **symlinked** `~/.gitconfig` (chezmoi, stow) keeps its link; the target is rewritten
- it takes Git's own `.lock` file, and never steals one it did not create
- `$GIT_CONFIG_GLOBAL` is honoured when set

It **refuses** (exit `4`, telling you what, why, and how to fix it) rather than
touch a config that is locked, unwritable, not a regular file, a dangling symlink,
unparseable by Git, or owned by another user while Atlas runs as root. Nothing is
ever modified before those checks pass.

## Testing

Every test sandboxes `HOME`, `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM`, and
`ATLAS_CONFIG_HOME` into a fresh temp directory and mocks `os::dnf_install`, so
the suite never touches your real `~/.gitconfig` and never runs `dnf`. Run it on
Linux — Windows Git-Bash mangles POSIX paths:

```sh
bash tests/run.sh
```
