# ssh

**What it does:** installs the OpenSSH client, and — only if you ask — creates and
manages an SSH identity for this workstation. It can register that key with GitHub,
and it can back it up, encrypted, to a local file.

**Depends on:** nothing.

**Design:** [RFC-0004](../../../docs/rfcs/RFC-0004-ssh-module.md).

## The one thing to understand: Atlas owns only what Atlas created

Your private key *is* your identity. So this module is the one place where Atlas
refuses by default.

| Class of key | How it got there | What Atlas does |
|---|---|---|
| **generated** | Atlas ran `ssh-keygen`, because you gave it a passphrase | manages, verifies, backs up, may register with GitHub |
| **imported** | you set `ATLAS_SSH_IMPORT_KEY` | same — but **never modifies the key itself** |
| **external** | anything else in `~/.ssh` | **detects and reports it. Nothing else.** |

An external key is not a problem to be solved. It is the normal state of a
developer's machine. `atlas install core/ssh` on a box that already has keys changes
**nothing**.

Ownership is not guessed from the filename. It is recorded in
`~/.config/atlas/ssh/manifest`, and every record is bound to the bytes on disk by two
values: the public fingerprint (the key's identity) and a SHA-256 of the private file
(its integrity). Both are re-checked on every run.

> Why both? Because `ssh-keygen -lf <private-key>` silently reads the *sibling `.pub`
> file* when one exists — it never looks at the private half. Replace the private file
> and leave the `.pub` in place, and a fingerprint check notices nothing. Hashing the
> private file closes that.

## Generating a key (opt-in)

Atlas will not create an identity you did not ask for. Supplying a passphrase *is* how
you ask:

```sh
# ~/.config/atlas/atlas.env   (mode 600, gitignored, your file)
ATLAS_SSH_KEY_PASSPHRASE=a long passphrase you can actually remember
```

Then `atlas install core/ssh` creates `~/.ssh/id_ed25519`, encrypted with it.

The passphrase never becomes a command-line argument (`argv` is world-readable in
`/proc`), never a shell variable, and never appears in a log or a `bash -x` trace. It
reaches `ssh-keygen` on the stdout of a tiny helper that Atlas writes to a temp
directory — and that helper contains no secret either; it just calls the resolver.

Afterwards Atlas **checks that the key really does require the passphrase**, and
deletes it if not. This is not paranoia: `ssh-keygen -t ed25519 -f k </dev/null` with
no `-N` neither hangs nor fails — it silently produces an *unencrypted* key and exits
0. An exit code proves nothing here.

If you genuinely want an unencrypted key (you rely on full-disk encryption, say):

```sh
ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE=1 atlas install core/ssh
```

Atlas will do it, and warn you loudly. Setting **both** is a contradiction and Atlas
refuses rather than picking a winner.

If `~/.ssh/id_ed25519` already exists, Atlas never overwrites it — owned or not.

## Adopting a key you already have

```sh
ATLAS_SSH_IMPORT_KEY=~/.ssh/id_work atlas install core/ssh
```

This writes a line to the manifest. It does **not** chmod, rewrite, move or re-encrypt
your key. All it means is: from now on, Atlas will back this key up, verify it, and
offer it to GitHub.

The path must be a regular file (not a symlink) **directly in `~/.ssh`**, with a `.pub`
beside it, and no whitespace or glob characters in its name. Atlas manages keys only in
`~/.ssh` — that is where SSH keys live, and constraining ownership there means a backup
artifact (which is portable, and which you may copy off-box) can never, on restore, name
a path like `~/.bashrc` and drop bytes outside `~/.ssh`.

## GitHub

If `gh` is installed and logged in, `install` registers your public key with GitHub —
once, checked against `gh api user/keys` first, so a key you added by hand is never
duplicated.

**This writes to your GitHub account.** It is additive and idempotent, and it is what
the `admin:public_key` scope exists for — but it is an outward-facing change and you
should know Atlas makes it.

If `gh` is not authenticated, Atlas warns and moves on. `install` never fails because
you have no GitHub account.

> **Ordering.** `core/ssh` runs before `development/github-cli` on a bare
> `atlas install`. So on a fresh box: run `atlas install`, then `gh auth login`, then
> **`atlas install` again** — the second run notices the key is unregistered and
> registers it. Atlas tells you this when it happens.
>
> One caveat: `gh auth token` only proves a token *exists*, not that it still works.
> With a revoked token, Atlas keeps trying to register on every run and `atlas status`
> keeps reporting `core/ssh` as not installed, until you re-authenticate.

## Backup and restore

`core/ssh` is Atlas's reference implementation of encrypted local backup.

```sh
# ~/.config/atlas/atlas.env
ATLAS_BACKUP_PASSPHRASE=another long passphrase
```

```sh
atlas backup            # -> ~/.local/state/atlas/backup/core-ssh.tar.gpg
atlas restore
```

What goes in: the manifest, every key Atlas owns (private and public), and Atlas's own
`known_hosts`. Nothing else — not `~/.ssh/config`, not `authorized_keys`, not a key
Atlas does not own.

- The plaintext archive **never touches the disk.** Staging is a farm of symlinks, and
  `tar` streams straight into `gpg`. The small amount of key material that *is* staged
  (during generation and restore) goes on a tmpfs (`/dev/shm`), so it stays in RAM. If
  your `/dev/shm` is too small for a large backup, set `ATLAS_SSH_STAGING_DIR` to a
  roomier tmpfs. Atlas warns if that directory turns out to be on a real disk, because
  then the decrypted key touches the platter.
- Atlas **reads the artifact back** before reporting success — and checks that it does
  *not* open with an empty passphrase.
- A failed backup **never destroys the previous good one.** Atlas writes a `.tmp`,
  verifies it, and only then replaces the artifact.
- Atlas **never uploads it.** It prints the path. Getting it somewhere safe is your job.
- The archive is byte-for-byte reproducible; the *encrypted file* is not, because GPG
  draws a fresh salt each time. That is correct — a deterministic ciphertext would let
  someone prove two backups are identical.

**Restore never overwrites anything silently.** It checks every destination first. If a
single file exists and differs, it writes **nothing at all**, lists the conflicts, and
exits. Files that are already byte-identical are skipped, which is what makes a second
`atlas restore` a no-op. It will not write through a symlink, and it inspects the
archive's member types before extracting so a tampered artifact cannot escape into
`$HOME`.

Restoring **re-establishes ownership**: it rewrites the manifest. Atlas prints the
paths it is about to own before it writes them.

## known_hosts

Atlas keeps its own `~/.config/atlas/ssh/known_hosts`, containing GitHub's published
ed25519 host key, and uses it only for its own connectivity check. **Your
`~/.ssh/known_hosts` is never touched**, so your first `git clone git@github.com:…`
still asks you to confirm the host — that is your trust decision, not Atlas's.

The key is pinned in the repo, copied from `https://api.github.com/meta` and verified
against GitHub's published fingerprint. Atlas never runs `ssh-keyscan` to learn it:
trust-on-first-use during automated provisioning would record an attacker as legitimate,
permanently.

## "The key Atlas recorded is not the key on disk"

That is *divergence*: the manifest and the disk disagree. Atlas stops touching that key,
`verify` fails, and `backup`/`restore` refuse — for **every** key, not just the bad one.
Atlas cannot tell a swapped key from a compromised machine, so it fails closed.

The manifest is a plain text file, mode 600. Atlas writes it; **you may edit it.**

- to **disown** a key (make it external again): delete its line. The key on disk is
  untouched.
- to **re-adopt** it as it is now: delete the line, then re-run with
  `ATLAS_SSH_IMPORT_KEY=<path>`.

Rotating a passphrase with `ssh-keygen -p` rewrites the private file, so it reads as
divergence too. Re-import to resolve it. Loading a key into the agent (`ssh-add`, even
`ssh-add -K`) only *reads* it and never triggers this.

## Lifecycle

| Hook | What happens |
|---|---|
| `check` | `ssh` present; manifest agrees with disk; no pending generate/import/registration. **No network.** |
| `install` | packages → pin `known_hosts` → import → generate → register with GitHub |
| `verify` | key integrity, permissions, external keys reported, GitHub connectivity (never fatal) |
| `update` | refresh the pinned `known_hosts`. Touches no key |
| `backup` / `restore` | above |

`verify` **fails** on a bad permission — OpenSSH will refuse a `644` private key, so the
module genuinely is unhealthy — and prints the exact `chmod`. It does not run it for
you: changing the mode of a file you created is modifying your state, and this module
does not do that.

`atlas verify` passes offline. Set `ATLAS_SSH_NO_NETWORK=1` to skip the GitHub probe
entirely.

**There is no `remove` hook.** Atlas will not delete a private key. It may be registered
on GitHub, on servers, in a signing config — there is no safe generic revert. Delete it
yourself if you mean to.

## Testing

Every test sandboxes `HOME`, `ATLAS_CONFIG_HOME`, `ATLAS_STATE_DIR`, `GNUPGHOME` and
`GH_CONFIG_DIR` into a fresh temp directory and mocks `dnf` and `gh`. No test touches
your real `$HOME`, runs real `dnf`, or contacts GitHub.

`ssh-keygen`, `tar` and `gpg` are **real**, because the claims worth testing are about
the artifact — "this key requires its passphrase", "this archive is byte-identical",
"this file will not decrypt without a secret" — and a mock cannot have those properties.

Hooks are invoked exactly as the runner invokes them (`if ! module::x`), because `set -e`
is suspended inside a hook body and a test that runs them bare is stricter than
production.

```sh
bash tests/run.sh          # on Linux/WSL
```
