# Changelog

All notable changes to Atlas are documented here. Format loosely follows
[Keep a Changelog]; Atlas uses semantic versioning once it hits 1.0.

## [Unreleased]

### Added
- **The `ssh` module** (see `RFC-0004`) — the first Atlas module that manages state
  you cannot regenerate. It installs the OpenSSH client, and then mostly *refuses*:
  on a machine that already has keys, `atlas install core/ssh` changes nothing. It
  generates an ed25519 identity **only** when you supply `ATLAS_SSH_KEY_PASSPHRASE`
  (supplying it *is* the opt-in), adopts an existing key only via
  `ATLAS_SSH_IMPORT_KEY`, and never chmods, rewrites or deletes a file it did not
  create. It registers your public key with GitHub best-effort, and it never touches
  `~/.ssh/known_hosts` — Atlas keeps its own, with GitHub's host key pinned from
  `api.github.com/meta` rather than learned by `ssh-keyscan`, because
  trust-on-first-use during automated provisioning is trust-on-first-attacker.
- **Real `backup` / `restore`**, and the contract every later stateful module
  inherits (`docs/conventions.md`). One platform-wide `ATLAS_BACKUP_PASSPHRASE`; a
  deterministic tar streamed straight into `gpg`, so no plaintext archive ever
  touches the disk; a `.tmp` artifact that is read back — and asserted *not* to
  decrypt with an empty passphrase — before it replaces the previous good one; and a
  restore that validates the whole archive and every destination *before* writing a
  single byte, so one conflict means nothing at all is written.
- An **ownership manifest** bound to the bytes on disk by two values: a public
  fingerprint and a hash of the private file. One is not enough — `ssh-keygen -lf
  <private-key>` silently reads the sibling `.pub` and never looks at the private
  half, so a fingerprint check alone is defeated by swapping the private file.
- No-op `backup` / `restore` for the `git` module, so every module answers every verb.
- Four new static rules in `tests/test_secret_discipline.sh`: a secret file descriptor
  may only be fed by `env::get_secret` (a process substitution inherits `xtrace`, so
  `3< <(printf …)` leaks); `gpg` never takes a passphrase in `argv` or from a file;
  `ssh-keygen -N` appears only in its empty-passphrase form; every `mktemp` is
  failure-checked. Each rule is verified to fire on a planted violation.
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
- **`core/ssh` backup no longer false-fails on a late GPG error after usable
  ciphertext was written.** This surfaced when a restricted Fedora validation
  environment denied `gpg-agent` its socket: GPG returned `2`, but emitted a
  complete, decryptable candidate. Atlas now requires `tar` success and a fresh
  candidate, then makes cryptographic and structural read-back authoritative before
  atomic replacement. Each run uses a unique same-directory candidate, so concurrent
  backups cannot swap partially written files. Invalid output still fails closed,
  stale candidates cannot be promoted, and the late GPG status is surfaced as a warning.
- **`set -e` never applied inside a module hook, and nothing said so.** The runner
  invokes hooks as `if ! "module::$hook"`, and Bash suspends `errexit` for a command
  in an `if` condition — recursively, into the function and everything it calls. `-u`
  and `pipefail` survive; `-e` does not. So an unchecked `d="$(mktemp -d)"` left `d`
  empty and turned a later `rm -rf "$d"/` into `rm -rf /`. Now documented in
  `docs/conventions.md`, and `core/ssh` checks every fallible command explicitly.
  `core/git` and `development/github-cli` predate the discovery and still need an
  audit against it.
- **A `trap … EXIT` set inside a hook is subshell-global**, and for `atlas install`
  the `check`, `install` and `verify` hooks share one subshell — so a trap set by a
  later hook silently *replaced* an earlier one, leaking its temp directory. Worse, a
  trap body naming a hook `local` fires after that local has died: under `set -u` the
  trap itself errors and the subshell exits 1, turning a module whose hook
  *succeeded* into a reported failure. The convention is now one module-scope array
  and one idempotent trap whose body touches only globals.
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

### Changed
- `docs/conventions.md` gains sections on `set -e` inside hooks, temp-directory
  cleanup, stdout as the runner's control channel, owning persistent state, and the
  backup contract. "Never add a runtime dependency" is relaxed to "adding one needs a
  reason in an RFC": `gpg` is the first, for local backup encryption (RFC-0004).
- `tests/test_module_git.sh` and the module inventory reflect `core/ssh` (ten modules).
