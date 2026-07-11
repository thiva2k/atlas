# Coding Conventions

These keep Atlas readable enough to understand in ten minutes.

## Bash

- `#!/usr/bin/env bash` on every script.
- Entry points: `set -uo pipefail`. Module hook subshells: `set -euo pipefail`.
- Quote expansions: `"$var"`, `"${array[@]}"`.
- Small functions, one job each. If a function needs a comment to explain a
  second responsibility, split it.
- No global mutable state beyond documented `ATLAS_*` variables.
- Prefer Bash builtins and coreutils. Adding a runtime dependency needs a reason in an
  RFC — `gpg` is the only one so far, for local backup encryption (RFC-0004).

### `set -e` is NOT in effect inside a hook

`internal/runner.sh` invokes every hook as `if ! "module::$hook"`, and Bash suspends
`errexit` for a command in an `if` condition — recursively, into the function and
everything it calls. `-u` and `pipefail` survive; `-e` does not. So:

- **Never rely on `set -e` to abort a hook.** Every fallible command needs an explicit
  `|| { log::error …; return 1; }`. The canonical disaster is `d="$(mktemp -d)"` failing,
  `d` becoming empty, and a later `rm -rf "$d"/` expanding to `rm -rf /`.
- **A hook returns its last statement's status.** An `A && B` in final position silently
  becomes the hook's exit code.
- **A pipeline's failure reaches nothing on its own.** `pipefail` shapes `$?` of the
  pipeline, but if the pipeline is not the hook's last statement, nobody reads it. Wrap
  it: `if ! a | b; then … return 1; fi`.
- **Test hooks the way the runner calls them** (`if ! module::x`), never bare under
  `set -e`. A bare-under-`-e` test is *stricter* than production and will pass a hook
  that marches on in the field.

### Temp directories: one trap, over a global

A `trap … EXIT` set inside a hook is **subshell-global** and fires at subshell exit, not
at hook return — and for `atlas install`, `check`/`install`/`verify` share one subshell,
so a trap set by a later hook **silently replaces** an earlier one. Worse, a trap body
that names a hook `local` runs after that local has died: under `set -u` the trap itself
errors and the subshell exits **1**, turning a module whose hook *succeeded* into a
reported failure.

So a module that needs temp directories keeps one module-scope array and registers one
idempotent trap whose body touches only globals:

```sh
_X_CLEANUP=()
_x_cleanup() { local p; for p in "${_X_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf -- "$p"; done; return 0; }
_x_track()   { [ -n "${_X_TRAP_SET:-}" ] || { trap _x_cleanup EXIT; _X_TRAP_SET=1; }; _X_CLEANUP+=("$1"); }
```

The trap is a safety net for failure paths. If a directory holds secret material, delete
it explicitly the moment you are done — do not leave it on disk until the subshell exits.
`modules/core/ssh/` is the reference.

### Stdout is a control channel

The runner reads a hook's stdout looking for the `__SKIP__` token. All user-facing output
goes through `log::*`, which writes to stderr. A hook that prints to stdout corrupts the
runner's bookkeeping.

## Naming

- Modules: `lower-kebab` directory names under a category.
- Functions: `snake_case`; namespaced APIs use `::` (`log::info`, `module::path`,
  `os::has_cmd`, `runner::run`). Module hooks are `module::<hook>`.
- Environment / globals: `UPPER_SNAKE`, prefixed `ATLAS_`.
- Private helpers: leading underscore (`_log_emit`, `_runner_run_module`).

## Output & errors

- All user output via `log::*`. Machine output (`--version`) may use `echo`.
- Fatal failures go through `die <code> <what> [why] [how]`.
- Exit codes are defined once in `internal/error.sh`.

## Files

- `internal/` = the engine, shared, module-agnostic.
- `modules/<category>/<name>/` = one capability, self-contained.
- Files that change together live together.

## User-specific configuration

Some settings are the user's, not Atlas's — an identity, a token, a hostname.
Atlas never prompts for them and never guesses. A module reads them with
`env::get NAME` (`internal/env.sh`), which resolves, in order:

1. the environment variable `NAME`
2. the key `NAME=value` in `$ATLAS_CONFIG_HOME/atlas.env`
   (default `~/.config/atlas/atlas.env`)

and returns non-zero when neither is set. Rules:

- **Namespace the key** after the module: `ATLAS_GIT_USER_NAME`, not `USER_NAME`.
- **Never block on a missing value.** `warn` and continue; a missing optional
  value is not an install failure, and never a `verify` failure.
- **Never overwrite a value the user already set** by hand. Apply it only when
  the target is unset.
- `atlas.env` holds secrets. It is the user's file; Atlas reads it, never writes it.

## Owning configuration a module does not own

A module writes its own settings into a file it *owns*, under
`$ATLAS_CONFIG_HOME/<module>/`, and then wires that file into the tool's real
configuration with the smallest possible edit (an include, a source line, a
drop-in). This keeps `update` and `remove` tractable: Atlas can regenerate or
delete its own file without ever parsing the user's.

Where the tool resolves configuration positionally, the Atlas fragment goes
**first**, so the user's own settings — read later — override Atlas's defaults.
Atlas provides defaults; the user always wins.

When a module must edit a user-owned file anyway:

- validate first, write second: every refusal (`die`, exit `ATLAS_EXIT_MODULE`)
  must happen *before* anything is modified;
- one atomic write (temp file in the same directory, then `mv`), preserving mode;
- resolve symlinks and edit the target, so dotfile managers keep working;
- take whatever lock the tool itself uses, and never steal one you did not create.

`modules/core/git/` is the reference implementation of all of the above.

## Secrets

`atlas.env` holds the user's secrets next to their preferences, so **both**
resolvers disable `xtrace` for their bodies: `env::get` walks every line of the
file to find one key, and would otherwise trace a credential during a lookup of
something else.

A secret is not a preference. Reading one goes through `env::get_secret NAME`
(`internal/env.sh`), never `env::get`:

- it disables `xtrace` for its own duration, so a caller running under `set -x`
  cannot leak the value to stderr;
- it refuses to consume a secret from a group- or world-readable `atlas.env`,
  warning and returning non-zero so the value is treated as **absent**. Atlas will
  not make an already-leaked credential load-bearing;
- it fails closed: a file whose mode cannot be determined is refused;
- a value taken from the **environment** is not mode-checked. The environment is
  the caller's problem, not a file Atlas can judge.

The standing rules for every credentialed module (RFC-0003 §4.4):

- **Atlas never prompts for a secret.** It runs unattended.
- **Atlas never writes a secret** into a file it owns, and never into the repo.
- A secret reaches Atlas only via the environment or `atlas.env` — mode `600`,
  gitignored, the user's own file.
- **A secret is never a command-line argument.** `argv` is world-readable in
  `/proc`.
- **A secret is never assigned to a variable.** `env::get_secret` can only guard
  its own body; `token="$(env::get_secret KEY)"` traces as `+ token=ghp_…` the
  instant the value crosses back into a caller running under `set -x`. Pipe the
  resolver straight into the tool that consumes it, so the value never enters the
  module's shell at all:

  ```sh
  env::get_secret ATLAS_GH_TOKEN >/dev/null || { log::warn "no usable token"; return 0; }
  env::get_secret ATLAS_GH_TOKEN | gh auth login --with-token
  ```

  The first call, discarding the value, separates "no usable secret" (a warning)
  from "the tool rejected it" (a failure).
- **A secret is never logged**, not even in an error path. No Atlas code may run
  under `set -x`, and no Atlas code may *leak* under an operator's `set -x`.
- **Absent credentials degrade to a warning, never a failed install.** A missing
  credential is the user's to supply. Only a credential the user *did* supply, and
  the tool then rejected, is a hard failure.

- **A process substitution inherits `xtrace`.** `3< <(printf '%s' "$pass")` traces
  `++ printf '%s' hunter2`; `3< <(env::get_secret KEY)` does not, because the guard lives
  inside the resolver and the trace shows only the call. **The producer feeding a secret
  file descriptor must always be `env::get_secret`** — never an inline `echo`, `printf`
  or `cat`.

Beware tools that print secrets, and tools that take them in `argv`:

| Tool | Never | Instead |
|---|---|---|
| `gh auth token` | capture it — it prints the token | `gh auth token >/dev/null 2>&1`, as a predicate |
| `gh auth login` | `--with-token <tok>` | pipe the resolver into it on stdin |
| `gpg` | `--passphrase`, `--passphrase-file` | `--passphrase-fd 3` with `3< <(env::get_secret …)` |
| `ssh-keygen` | `-N "$pass"` (argv is world-readable in `/proc`) | `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force` |

`ssh-keygen -N ''` is admissible — an empty passphrase is not a secret.

**Never trust an exit code where a property is what you mean.** `ssh-keygen -t ed25519
-f k </dev/null` with no `-N` neither hangs nor fails: it silently produces an
*unencrypted* key and exits 0. Assert the property instead — Atlas checks that the key it
just generated really does reject an empty passphrase, and deletes it if not. Likewise
`backup` asserts its artifact does *not* open without a passphrase.

`tests/test_secret_discipline.sh` enforces these rules statically across the repo, and
each rule is itself verified to fire on a planted violation.

`modules/development/github-cli/` is the reference for credentials;
`modules/core/ssh/` for secrets that are also *state*.

## Owning persistent state

Some modules manage state the user cannot regenerate — a private key, a token they
minted by hand. `modules/core/ssh/` is the reference implementation (RFC-0004).

**Atlas owns only what Atlas created, or what the user explicitly handed it** through a
documented workflow. Ownership is *recorded*, never inferred from a path, and the record
is bound to the bytes on disk so the claim can be re-checked on every run:

- a manifest under `$ATLAS_CONFIG_HOME/<module>/`, mode `600`, plain text;
- each record carries **two** bindings — an identity (a fingerprint) and an integrity
  hash of the file's actual bytes. One is not enough: `ssh-keygen -lf <private-key>`
  silently reads the sibling `.pub`, so a fingerprint alone never sees the private half;
- owned paths must be **regular files, not symlinks**, must live under `$HOME`, and must
  contain no whitespace or control characters. Such paths are *refused, not escaped*;
- the manifest is user-editable, so its parser is a **trust boundary**: it rejects
  unknown records, bad field counts, duplicates, orphans and missing headers rather than
  repairing or ignoring them. Strip trailing `\r` — a file edited on Windows must parse;
- when the manifest and the disk disagree, the module is **divergent**: it stops touching
  that state, fails `verify`, and refuses `backup`/`restore` **entirely** — not just for
  the offending record. Fail closed;
- **never `chmod`, rewrite, or delete a file the module did not create.** Report the
  fault and print the command the user should run.

## The backup contract

`atlas backup` and `atlas restore` are generic platform verbs that fan out to every
module. The runner has no special cases. A module with no persistent state implements
no-op hooks (or omits them — the runner treats an absent optional hook identically).

A module that *does* hold state follows this contract:

1. **One secret per platform verb.** The passphrase is `ATLAS_BACKUP_PASSPHRASE`, resolved
   with `env::get_secret`. No per-module override: one verb must not demand N secrets.
2. **Artifact:** `$ATLAS_STATE_DIR/backup/<category>-<name>.tar.gpg`, directory `700`,
   file `600`. Fixed name.
3. **Never truncate a good artifact with an unverified one.** Create a unique
   same-directory `<artifact>.tmp.XXXXXX`, read that exact file back, and only then
   `mv -fT` it into place. A shared `.tmp` path lets concurrent backups replace each
   other's candidate; a different directory loses atomic rename. `gpg --yes -o
   "$artifact"` truncates the target *before* the new artifact exists — a failed backup
   would otherwise leave the user with none.
4. **Archive layout** is flat and self-describing, so a restore onto a different `$HOME`
   works: members live under `home/` (relative to `$HOME`) or `config/` (relative to
   `$ATLAS_CONFIG_HOME`). No absolute paths, no `..`, no symlink or device members.
5. **Only module-owned state.** Never `$HOME`. Never a file the module did not create or
   explicitly import.
6. **Encrypt locally; never upload.** Print the path. Moving it off-box is the user's job.
7. **Validate properties, not only the encryptor's exit code.** The archive producer must
   exit `0`, and encryption must create a new, nonempty regular candidate. Read that
   candidate back before reporting success, verify its required contents, and assert it
   does **not** decrypt with an empty passphrase. A nonzero encryption status is advisory
   only when every stronger read-back check passes; otherwise discard the candidate.
8. **No plaintext copy.** Stage a farm of symlinks and let `tar --dereference` stream
   straight into `gpg`. Decrypt into a `700` directory on tmpfs (`/dev/shm`) where
   available. Warn — keyed on the filesystem *type* (`stat -f`), not on how the base was
   chosen — whenever staging lands on a real disk, so an operator override to a disk
   directory warns exactly like the involuntary `$TMPDIR` fallback. A module may accept an
   `ATLAS_<…>_STAGING_DIR`-style override for operators whose `/dev/shm` is too small.
9. **Restore validates everything before writing anything.** List the archive with
   `tar -tv` (`tar -t` prints names only and cannot see member types), reject anything
   that is not a regular file or directory, then scan **every** destination for conflicts.
   A destination that exists and differs — or that is a symlink — is a conflict, and a
   single conflict means **nothing at all is written**. Byte-identical destinations are
   skipped, which is what makes a second `restore` a no-op.
10. **Determinism belongs to the archive, not the ciphertext.** `tar --sort=name --mtime=@0
    --owner=0 --group=0 --numeric-owner` is byte-reproducible; do **not** add
    `--format=posix`, whose pax `atime`/`ctime` headers destroy it. The GPG artifact is
    *not* reproducible, because symmetric encryption draws a fresh salt — and it must not
    be, or an observer could prove two backups are equal.
