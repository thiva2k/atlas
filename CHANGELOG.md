# Changelog

All notable changes to Atlas are documented here. Format loosely follows
[Keep a Changelog]; Atlas uses semantic versioning once it hits 1.0.

## [Unreleased]

### Added
- **The `github-cli` module** (see `RFC-0003`) — installs `gh` and, only from a
  token you supplied out of band, authenticates it without ever prompting. It
  **owns no `gh` configuration**: an early draft set `git_protocol = ssh` on a
  fresh install, which would have broken anonymous clones of *public* repos until
  you registered an SSH key. `gh`'s own default is better, so Atlas leaves it be.
  It also never runs `gh auth setup-git` — that writes into `~/.gitconfig`, which
  belongs to the `git` module. No `remove` hook; `backup` / `restore` are no-ops,
  because `gh`'s only state is a regenerable OAuth token Atlas will not copy.
- `env::get_secret` (`internal/env.sh`): the credential-grade sibling of
  `env::get`, and the precedent for every credentialed module after it. It
  disables `xtrace` for its own duration, **refuses to consume a secret from a
  group- or world-readable `atlas.env`** (warning, and treating the value as
  absent rather than failing), and fails closed when a file's mode cannot be read.
  Secrets reach tools on **stdin**, never as command-line arguments — `argv` is
  world-readable in `/proc`.
- **The `git` module** — the first real module, and the reference implementation
  for every module after it (see `RFC-0001`). Installs Git, layers Atlas's
  defaults *underneath* your own `~/.gitconfig` via an owned config fragment, and
  fills in `user.name` / `user.email` only when they are missing. Implements the
  `check` / `install` / `verify` / `update` / `remove` hooks. (The `remove`
  *hook* restores your config byte-for-byte and leaves the Git package and your
  identity alone, but no `atlas remove` platform verb exists yet to invoke it —
  an engine gap tracked by RFC-0002.)
- `env::get` (`internal/env.sh`): resolves user-specific settings from the
  environment, then `~/.config/atlas/atlas.env`. Never prompts, never blocks.
- `os::dnf_install`: a real, idempotent package primitive.
- v1 skeleton: architecture, `atlas` CLI, module runner, and the `internal/`
  engine (logging, errors, OS helpers, module contract, dependency resolution).
- Eight placeholder modules across core / development / apps / desktop.
- Zero-dependency `bootstrap.sh`.
- Pure-Bash test harness under `tests/`.

### Fixed
- **`atlas.env` secrets no longer leak into a `bash -x` trace.** `env::get` walks
  every line of `atlas.env` looking for one key, so running Atlas under `set -x`
  traced `line=ATLAS_GH_TOKEN=ghp_…` — a credential belonging to one module,
  printed to stderr during another module's lookup of an unrelated preference
  (`core/git` reading your git identity). Both `env::get` and `env::get_secret`
  now disable `xtrace` for their bodies and restore it on return, and no module
  may assign a secret to a variable (an assignment traces its own value). Found by
  running `bash -x ./atlas install development/github-cli` end to end.
- **git: Atlas defaults no longer override your own git settings.** The managed
  config was wired into `~/.gitconfig` with `git config --add`, which appends —
  and because git resolves configuration positionally, the Atlas fragment was
  read last and won. Installing Atlas would silently flip a hand-set
  `pull.rebase = false` to `true`. The include block is now prepended, so
  anything you set below it wins, as `RFC-0001` §4.4 always intended. An
  existing bottom-placed include is relocated on the next `atlas install git`.
  The rewrite is a single atomic write, preserves the file's mode, follows a
  symlinked `~/.gitconfig` to its target, and refuses to touch a config that is
  locked, unwritable, not a regular file, or unparseable — always before
  modifying anything.
- **git: `atlas verify git` no longer reports a healthy module as broken** when
  you override one of Atlas's managed defaults. It now checks that the managed
  fragment *resolves*, not that Atlas's value is the winning one — which, after
  the fix above, it deliberately is not.

[Keep a Changelog]: https://keepachangelog.com/
