# RFC-0004: SSH Module

| | |
|---|---|
| **Status** | Accepted |
| **Author** | Claude Code (for thiva2k) |
| **Created** | 2026-07-10 |
| **Revised** | 2026-07-10 — architecture review r1: 9 blocking, 8 adopted, 1 refuted by probe. Gate review r2: 6 blocking edits, all confirmed by probe and applied. Post-implementation errata: see §12 |
| **Phase / order** | Phase 1 — Foundation · module 3 of 16 |
| **Depends on** | *nothing.* `MODULE_DEPENDS=()` — see Decision 1 |
| **Establishes** | **Ownership of persistent state**, the **backup/restore contract**, and one **engine fact** about `errexit` |

---

## 1. Summary

Implement `modules/core/ssh` — install the OpenSSH client, optionally generate an
ed25519 workstation identity, verify the identity's health and its GitHub
connectivity, and provide the first real `backup` / `restore` implementation in
Atlas: a deterministic archive of **module-owned state only**, encrypted locally
with GPG, never uploaded.

This is the first Atlas module that manages state the user cannot afford to lose
and cannot regenerate. A private key *is* the user's identity. Every rule below
follows from that single fact.

Two owner rulings govern this RFC and are quoted, not paraphrased.

The backup ruling (2026-07-10):

> Keep the generic backup and restore platform verbs. Implement real
> backup/restore in the SSH module as the first concrete module implementation,
> but do not special-case SSH in the runner. The runner remains generic and fans
> out to every module. Modules without persistent state implement no-op hooks.
> The backup artifact must contain only module-owned state and should be
> encrypted locally. This establishes the reference implementation for all future
> stateful modules.

The ownership ruling (2026-07-10):

> Atlas must never silently assume ownership of existing SSH keys. Atlas must
> never modify imported user keys. Atlas must never overwrite existing SSH
> configuration. Atlas must never delete user-created keys. Atlas must never
> modify user-created known_hosts entries. Atlas may manage only resources that
> Atlas explicitly created or imported through a documented Atlas workflow.

And RFC-0003's forward commitment, which this RFC discharges:

> RFC-0004 (`core/ssh`) will attempt `gh ssh-key add` on a best-effort basis:
> succeeding when `gh` is authenticated, warning when it is not.

---

## 2. Motivation

A workstation without an SSH identity cannot clone, push, or sign. Provisioning
one is therefore in scope for the Fedora Definition of Done.

But an SSH module is the sharpest tool Atlas will ever hold. The failure modes are
not "the install did not converge" — they are *the user lost their identity* and
*the user's private key was copied somewhere it should not be*. A module that is
merely correct is not good enough here; it must be **refusing by default**.

So this module inverts Atlas's usual posture. Elsewhere Atlas installs and
configures. Here Atlas **detects, verifies, and reports**, and acts only when the
user has explicitly asked it to — by supplying a passphrase, or by naming a key to
import. The default behaviour of `atlas install core/ssh` on a machine that
already has SSH keys is to change *nothing*.

---

## 3. Goals / Non-goals

**Goals**

1. Install the OpenSSH client.
2. Detect and report existing SSH state without modifying it.
3. Optionally generate an ed25519 keypair, encrypted, non-interactively.
4. Adopt ("import") an existing key into Atlas's management by explicit request.
5. Verify permissions, key integrity, and GitHub connectivity.
6. Register an Atlas-owned public key with GitHub, best-effort.
7. Implement real `backup` / `restore`: deterministic, GPG-encrypted, local-only,
   conflict-detecting, idempotent.
8. Establish the ownership manifest and the **backup contract** that every future
   stateful module reuses.

**Non-goals**

1. **No `~/.ssh/config` management.** The generated key lives at OpenSSH's default
   identity path, so no configuration is required.
2. **No `authorized_keys` management.** Inbound SSH is a server concern.
3. **No `ssh-agent` lifecycle management.** That belongs to the desktop session.
4. **No modification of the user's `~/.ssh/known_hosts`** (§4.7, Decision 6).
5. **No key rotation, no key deletion, no `remove` hook** (§4.13).
6. **No upload of any backup artifact, ever.**
7. **No passphrase changes on an existing key**, owned or not.

---

## 4. Design

### 4.0 An engine fact this module must be built around

`internal/runner.sh:50` invokes every hook as:

```sh
if ! "module::$hook"; then …
```

A command in an `if` condition runs with `errexit` **suspended**, and the
suspension propagates into the function and everything it calls. So although
`_runner_run_module` opens its subshell with `set -euo pipefail`, **`-e` is not in
effect inside any hook body.** Verified:

```
set -euo pipefail
inner()           { false; echo "inner: SURVIVED"; }
module::install() { inner; echo "hook: SURVIVED"; false; echo "hook: SURVIVED own false"; }
if ! module::install; then echo failure; else echo success; fi
#  inner: SURVIVED / hook: SURVIVED / hook: SURVIVED own false / success
```

`-u` and `pipefail` **are** still in effect (also verified). Three consequences,
all binding on this module:

1. **No hook may rely on `set -e` to abort.** Every fallible command needs an
   explicit `|| { log::error …; return 1; }`. This is not a style preference; the
   canonical disaster is
   `staging="$(mktemp -d)"` failing, `staging` becoming empty, and a later
   `rm -rf "$staging"/` expanding to `rm -rf /`. Reproduced verbatim under the
   real runner semantics.
2. **A hook's return value is its last statement's status.** Any `A && B` as the
   final statement of a hook silently becomes its exit code.
3. **Hook-level tests must invoke hooks the way the runner does** (`if ! module::x`),
   not bare under `set -e`. Testing bare-under-`-e` is *stricter* than production:
   a hook that leans on `-e` passes the test and marches on in the field.

This applies to `core/git` and `development/github-cli` too, which were written
before it was known. Auditing them is filed as follow-up work in §11; both appear
to use explicit `|| return`, but "appear to" is not "were checked".

### 4.1 Module layout

```
modules/core/ssh/
  module.sh
  README.md
  config/
    known_hosts        # Atlas-owned, pinned; NOT the user's file
```

### 4.2 Metadata

```sh
MODULE_NAME="ssh"
MODULE_DESCRIPTION="OpenSSH client: manages an Atlas-owned workstation identity, with encrypted local backup."
MODULE_DEPENDS=()
```

No dependency. Argued in Decision 1.

### 4.3 Package source

Fedora ships OpenSSH in the base install; `openssh-clients` provides `ssh`,
`ssh-keygen`, `ssh-keyscan`, `ssh-add`. `install` runs
`os::dnf_install openssh-clients gnupg2` — `gnupg2` because `backup` cannot exist
without it, and a backup tool that fails the first time it is needed is not a
backup tool. Both are near-certainly present already; `install` no-ops when they are.

`gpg` is the first runtime dependency Atlas takes beyond coreutils.
`docs/conventions.md` says "never add a runtime dependency", a rule written against
*convenience* dependencies. Local encryption was mandated by the owner. GPG is not
the only tool on a Fedora box that can encrypt symmetrically — `openssl enc
-aes-256-cbc -pbkdf2` would also work — but GPG gives *integrity-protected*
encryption (SEIPD/MDC: modification **detection**, not modern AEAD — do not overstate
this) and a standard, self-describing artifact format, and it is what the ruling
names. The convention is amended in the open (§8), not quietly broken.

### 4.4 Ownership — the manifest

Everything else rests on one question: **which keys are Atlas's?**

Guessing — "a key at `~/.ssh/id_ed25519` must be ours" — would let Atlas back up,
and restore over, a key it never created. Ownership is therefore **recorded**, and
the record is **bound to the bytes on disk**.

`$ATLAS_CONFIG_HOME/ssh/manifest` (default `~/.config/atlas/ssh/manifest`), mode
`600`:

```
# atlas-ssh-manifest v1
key generated .ssh/id_ed25519 SHA256:OvCBPq6…  9f2c1e…  600
key imported  .ssh/id_work    SHA256:bL0nKx9…  4ad77b…  600
github        SHA256:OvCBPq6…
```

`key <origin> <path> <pubfp> <privhash> <mode>` — path is `$HOME`-relative.

| Field | What it is | What it is for |
|---|---|---|
| `pubfp` | `ssh-keygen -lf <path>.pub` | the key's **identity** (GitHub records, `ssh-add -l` matching) |
| `privhash` | `sha256sum <path>` | the private file's **integrity** |

`github <pubfp>` records that **Atlas has confirmed** this public key is present on
the user's GitHub account — whether Atlas added it or found it already there.

#### Why two fields, and not just the fingerprint

The obvious design — store `ssh-keygen -lf` of the key and re-check it — is
**broken**, and not subtly. Probed:

```
$ ssh-keygen -lf real.pub                 SHA256:TZv/DnvUO/yA1Y+ktDKLqbd7Z8yrTpVLPbwosoaEmQ8
$ cp other real                           # swap ONLY the private half
$ ssh-keygen -lf real                     SHA256:TZv/DnvUO/yA1Y+ktDKLqbd7Z8yrTpVLPbwosoaEmQ8   ← unchanged!
$ rm real.pub && ssh-keygen -lf real      SHA256:4jm3r3LkMg/ehlyTbSna/3SoQc48SyglNZV9zYsLGE8   ← the other key
```

**`ssh-keygen -lf <private-key>` prefers the adjacent `.pub` file when one exists.**
It never reads the private half. An attacker (or a confused user) who replaces the
private file while leaving `.pub` in place passes every fingerprint check, and Atlas
would archive, and later restore over, a private key it never created. Hashing the
private file closes this. `sha256sum` works on an encrypted key too, without the
passphrase.

#### What the hash does and does not mean

`privhash` detects **any** change to the private file. It cannot distinguish "the
user swapped the key" from "the user rotated its passphrase" — OpenSSH rewrites the
file with a fresh salt on `ssh-keygen -p`, so even the same key under the same
passphrase hashes differently. Atlas therefore treats *any* mismatch identically:
the recorded key is no longer the key on disk, so **Atlas stops touching it** and
says so. Recovery is §4.14.

Storing `sha256` of a private key file is safe: it is one-way, and anyone able to
confirm a guess against it already holds the key.

#### Refusals baked into the ownership check

An owned path must be a **regular file, not a symlink**. A symlinked owned path is
treated exactly as a mismatch — refuse and report. (Otherwise `restore` writes
*through* the link to a target outside the conflict scan.) All ownership checks and
the restore conflict scan use `[ -L ]` and refuse; none follow links.

An owned path must lie under `$HOME`, and must contain no whitespace, newline, or
control character. `ATLAS_SSH_IMPORT_KEY` is user-supplied; such paths are
**refused, not escaped** — safety over convenience, and it keeps the manifest a
line-oriented file that cannot be spoofed by a crafted filename.

#### The parser fails closed, because the user may edit this file

§4.14 makes the manifest officially user-editable, so its parser is a trust boundary,
not a convenience. It rejects — rather than repairs or ignores — every one of:

- an unrecognised or missing `# atlas-ssh-manifest v1` header;
- an unknown record type; a `key` record without exactly five fields, or a `github`
  record without exactly two;
- a `mode` field that is not three octal digits;
- a duplicate `path`, or a duplicate/orphan `github` record (one naming a `pubfp` no
  `key` record has);
- a path that is absent, is not a regular file, is a symlink, is a directory, or is
  unreadable — all of these are `divergent`, never a crash and never "assume it's fine".

Trailing `\r` is stripped before parsing, exactly as `env::get` does for `atlas.env`
(`internal/env.sh:29`): a manifest edited on Windows, or copied through one, must not
silently mismatch every hash.

#### Three classes of key

| Class | How it arises | Atlas may |
|---|---|---|
| **Generated** | `ssh-keygen`, run by Atlas | back up, restore, register, verify |
| **Imported** | user set `ATLAS_SSH_IMPORT_KEY` | back up, restore, register, verify — **never modify** |
| **External** | everything else in `~/.ssh` | **detect, report** — nothing else |

An external key is not a problem to be solved. It is the normal state of a
developer's machine.

### 4.5 Key generation — opt-in, never a default

`atlas install core/ssh` on a machine with no key generates **nothing** unless asked.
Generation is requested by supplying a passphrase:

| Variable | Effect |
|---|---|
| `ATLAS_SSH_KEY_PASSPHRASE` | (secret) generate an ed25519 key encrypted with it |
| `ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE=1` | generate an **unencrypted** key; loud warning |
| neither | do not generate; warn once; exit 0 |

Supplying a passphrase *is* the opt-in. There is deliberately no separate
`ATLAS_SSH_GENERATE=1` knob, because a knob that can be set without deciding about
the passphrase is a knob that produces unencrypted keys by accident.

Setting **both** is a contradictory instruction and Atlas refuses it — it does not pick
a winner. "Encrypt this key with `hunter2`" and "make this key unencrypted" cannot both
be honoured, and guessing which the user meant is exactly the class of decision this
module does not make.

Generation never overwrites. If `~/.ssh/id_ed25519` exists — owned or not — Atlas
does not run `ssh-keygen` at all.

#### Setting a passphrase without a tty, without argv, without a variable

`ssh-keygen -N <passphrase>` puts the secret in `argv`, world-readable in
`/proc/*/cmdline`. Forbidden (RFC-0003 §4.4).

OpenSSH ≥ 8.4: with `SSH_ASKPASS` set and `SSH_ASKPASS_REQUIRE=force`, `ssh-keygen`
invokes the named program and reads the passphrase from **its stdout** — twice, for
the confirmation prompt. Probed on OpenSSH 9.6 (§6.1).

Atlas writes a short askpass helper into a `mktemp -d` (mode `700`, removed by an
`EXIT` trap). The helper **contains no secret**: it sources `internal/env.sh` and
execs `env::get_secret ATLAS_SSH_KEY_PASSPHRASE`. The passphrase travels
resolver → pipe → `ssh-keygen`; never a variable, never an argument, never logged,
never on disk.

**A footgun worth naming.** `ssh-keygen -t ed25519 -f k </dev/null` with no `-N`
does **not** hang and does **not** fail. It reads the empty line as the passphrase
and silently produces an *unencrypted* key, exit 0 (§6.1). Any path in this module
that runs `ssh-keygen` without either `-N` or a working askpass is a security bug no
exit code will reveal. So the module **asserts the result**: after generating with a
passphrase it checks that `ssh-keygen -y -f <key> -P ''` *fails*, and aborts if it
succeeds. The test suite asserts the same, rather than asserting `ssh-keygen`
returned 0.

### 4.6 Importing an existing key

`ATLAS_SSH_IMPORT_KEY=~/.ssh/id_work` is the documented workflow by which a user
hands Atlas an existing key. On `install`, Atlas:

1. resolves the path (must exist; be a **regular file, not a symlink**; live under
   `$HOME`; have no whitespace/newline/control chars; have a readable `.pub` beside it);
2. computes `pubfp` from the `.pub` and `privhash` from the private file;
3. appends `key imported …` to the manifest, atomically.

It **does not** chmod it, rewrite it, re-encrypt it, or move it. Import is a
statement about the *manifest*, not about the key. Its only effects: the key is
thereafter backed up, restored, verified, and eligible for GitHub registration.

Import is idempotent — an identical record is a no-op. A record for the same path
with a *different* `pubfp`/`privhash` is a hard error: the key changed under Atlas.
The user resolves it deliberately (§4.14).

### 4.7 `known_hosts` — Atlas keeps its own, and pins

Atlas ships `config/known_hosts` containing GitHub's **published** ed25519 host key
and installs it to `$ATLAS_CONFIG_HOME/ssh/known_hosts`. Atlas uses that file, and
only that file, for its own connectivity check.

> **Sourcing rule for the pinned key.** At implementation, the key is copied verbatim
> from GitHub's published SSH key fingerprints documentation / `https://api.github.com/meta`,
> with the source URL and retrieval date in a comment at the top of `config/known_hosts`.
> It is **not** taken from `ssh-keyscan`, and not from anyone's memory — including a
> reviewer's, an author's, or a model's. A pinned key transcribed from recall is a pinned
> key nobody verified.

```sh
ssh -o UserKnownHostsFile="$atlas_known_hosts" -o StrictHostKeyChecking=yes \
    -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$key" …
```

Two consequences, both deliberate:

- **Atlas never runs `ssh-keyscan` to learn a host key.** Trust-on-first-use during
  automated provisioning is trust-on-first-*attacker*: a MITM at provisioning time is
  recorded as legitimate forever. The key is pinned in the repo, reviewed like code,
  rotated by a commit. Verified: a wrong pin fails closed with `REMOTE HOST
  IDENTIFICATION HAS CHANGED`, exit 255 (§6.1).
- **Atlas never writes to `~/.ssh/known_hosts`.** The owner's ruling: *"Atlas must
  never modify user-created known_hosts entries."* Atlas owns its own file entirely,
  so it modifies no entry it did not create.

Cost: the user's first `git clone git@github.com:…` still shows the ordinary TOFU
prompt. Whether Atlas should *offer* to append the pinned entry to the user's file is
Decision 6; this RFC recommends **no**.

### 4.8 GitHub registration — best-effort, additive

This discharges RFC-0003's commitment. `install` attempts registration when, and only
when:

- an Atlas-owned key exists and is **intact** (both `pubfp` and `privhash` match), and
- `gh` is on `PATH` and locally authenticated (`gh auth token >/dev/null 2>&1` — a
  local read of `hosts.yml`; the token is never captured, per RFC-0003), and
- the manifest has no `github <pubfp>` record for that key.

Idempotency is checked **against GitHub, not only the manifest**: `gh api user/keys`
is compared by key blob before any write, so a key added by hand is never duplicated
(GitHub 422s on duplicates, so this is load-bearing, not decorative). If the key is
already there, Atlas records `github <pubfp>` anyway — the record means *"Atlas
confirmed this key is registered"*, not *"Atlas performed the upload"*. Without that,
`check` would fail forever on a key the user registered by hand (§4.12, row 6).

Registration uses `gh ssh-key add - --title "<host> (atlas)"`, reading the **public**
key from stdin (probed: `gh ssh-key add -` accepts stdin, exit 0). A public key is
not a secret; stdin is used for uniformity.

Every failure here is a **warning, not an install failure**: `gh` absent, `gh` logged
out, token lacking `admin:public_key`, GitHub unreachable. A user without a GitHub
account must be able to provision a workstation.

Atlas registers only keys it generated or the user explicitly imported. It never
uploads a key it merely found.

**This writes to the user's GitHub account.** It is additive and idempotent, and it is
what `admin:public_key` was granted for — but it is an outward-facing mutation and the
README says so in those words.

### 4.9 Permissions — verify, report, do not repair

| Path | Required | Atlas |
|---|---|---|
| `~/.ssh` | `700` | creates it `700` if absent; **never chmods** an existing dir |
| owned private key | `600` | creates it `600` |
| owned public key | `644` | creates it `644` |
| `$ATLAS_CONFIG_HOME/ssh/` | `700` dir, `600` manifest | owns and enforces |

Atlas does not `chmod` a file it did not create — not even an obviously wrong one. A
`chmod` is a modification of user state, and the ownership ruling has no "unless it
looks broken" clause. `verify` **fails** on a bad mode (OpenSSH will refuse the key,
so the module genuinely is unhealthy) and prints the exact `chmod` to run. Reporting a
fault is not the same as being unable to fix it.

### 4.10 The backup contract (for every future stateful module)

The owner's ruling makes this module the reference. A reference that specifies only
its own behaviour is not one. So the following is the **contract**, and belongs in
`docs/conventions.md`:

1. **One secret per platform verb.** `atlas backup` fans out to every module; it must
   not demand N passphrases. The passphrase is `ATLAS_BACKUP_PASSPHRASE`, resolved with
   `env::get_secret`. There is deliberately **no per-module override** — one secret, one
   verb, until a second stateful module demonstrates a need. (Decision 5.)
2. **Artifact path:** `$ATLAS_STATE_DIR/backup/<category>-<name>.tar.gpg` —
   `$ATLAS_STATE_DIR` is the engine variable already defined at `internal/log.sh:5`
   (default `~/.local/state/atlas`); `backup/` sits alongside the `logs/` directory
   *inside* it. Directory `700`, file `600`. Fixed name.
3. **Never overwrite a good artifact with an unverified one.** Write to
   `<artifact>.tmp` in the same directory, read it back (item 6), and only then
   `mv -f` it into place. `gpg --yes -o "$artifact"` truncates the target *before* the
   new artifact is verified — probed — so a failed backup would otherwise leave the
   user with **zero** backups. A backup verb whose failure mode is "you now have none"
   is the hazard this module exists to prevent.
4. **Archive layout** is flat and self-describing, so a restore onto a machine with a
   different `$HOME` works:

   ```
   home/.ssh/id_ed25519          # members under home/ are $HOME-relative
   home/.ssh/id_ed25519.pub
   config/ssh/manifest           # members under config/ are $ATLAS_CONFIG_HOME-relative
   config/ssh/known_hosts
   ```

   Only `home/` and `config/` roots are legal. No absolute paths, no `..`, no symlink
   members, no device nodes.
5. **Only module-owned state.** Never `$HOME`. Never a file the module did not create
   or explicitly import.
6. **Encrypt locally, never upload.** Print the path; moving it off-box is the user's job.
7. **Read the artifact back** before reporting success — and assert it does **not**
   decrypt with an empty passphrase (§4.11).
8. **A module with no persistent state implements no-op `backup`/`restore`** (or omits
   them — the runner treats an absent optional hook identically). `development/github-cli`
   already ships no-ops; `core/git` currently defines neither hook and gains them here
   (§10 step 7).

### 4.11 `backup` — the implementation

**Contents:** the manifest; every owned key's private and public file; Atlas's own
`known_hosts`. Nothing else.

**No plaintext copy is ever made.** Staging is a directory of **symlinks** on tmpfs;
`tar --dereference` archives the *contents* under the staging layout. The plaintext tar
exists only as a pipe:

```sh
# 1. discard-probe: separate "no usable secret" from "the tool rejected it"
env::get_secret ATLAS_BACKUP_PASSPHRASE >/dev/null || {
  log::error "no usable ATLAS_BACKUP_PASSPHRASE — refusing to write an unencrypted backup"
  return 1
}

# 2. write to a TEMP artifact; never truncate the last good one (contract item 3)
if ! tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --dereference \
         -cf - -C "$staging" . \
     | gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
           --symmetric --cipher-algo AES256 -o "$artifact.tmp" \
           3< <(env::get_secret ATLAS_BACKUP_PASSPHRASE)
then
  log::error "backup pipeline failed"; rm -f "$artifact.tmp"; return 1
fi
```

The explicit `if !` around the pipeline is **not optional**. `-e` is suspended inside
every hook (§4.0), and this pipeline is not the hook's last statement — the read-back
follows it. Probed: without the check, a failing `tar | gpg` is silently swallowed and
the hook returns 0. This snippet is the one every future stateful module will copy, so
it carries the discipline it preaches.

The passphrase reaches GPG on fd 3 from a process substitution: never assigned, never
an argument, never logged.

> **A rule learned by probing.** A process substitution runs in a subshell that
> **inherits `xtrace`**. `3< <(printf '%s' "$pass")` leaks `++ printf '%s' hunter2`
> into the trace. `3< <(env::get_secret KEY)` does not — the guard lives inside the
> resolver, and the trace shows only `++ env::get_secret KEY`. Both verified. **The
> producer inside a process substitution must always be `env::get_secret`**, never an
> inline `echo`/`printf`/`cat` of a secret. `tests/test_secret_discipline.sh` gains a
> static rule for it.

The discard-probe on the first line is not redundant. If the resolver fails mid-run
(the mode on `atlas.env` flipped between `check` and `backup`), the process
substitution delivers *empty input*. Probed: GnuPG 2.4.4 then refuses — `error creating
passphrase: Invalid passphrase`, exit 2, **no artifact**. So gpg fails closed today.

Atlas does not rely on that, and the discard-probe alone does not close it either.
There is a residual window: the probe passes, the resolver then breaks *persistently*,
a future `gpg` accepts the empty passphrase — and the read-back, using the same broken
resolver, decrypts it happily. Atlas would report success for an artifact the user
believes is protected and then copies off-box.

So the read-back carries a second assertion, borrowed from §4.5's treatment of
`ssh-keygen`: **the artifact must fail to decrypt with an empty passphrase.**

```sh
# 3. read back the TEMP artifact: it must decrypt with the passphrase …
gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 -d "$artifact.tmp" \
      3< <(env::get_secret ATLAS_BACKUP_PASSPHRASE) 2>/dev/null | tar -t > "$listing" \
  || { log::error "backup did not read back"; rm -f "$artifact.tmp"; return 1; }

# … and must NOT decrypt without one (probed: rc=2 today; assert it, do not assume it)
if gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 -d "$artifact.tmp" \
       3< /dev/null >/dev/null 2>&1; then
  log::error "the artifact decrypts with an empty passphrase — refusing to keep it"
  rm -f "$artifact.tmp"; return 1
fi

# 4. every intended member present? then, and only then, replace the good artifact
mv -f "$artifact.tmp" "$artifact"
```

That closes the hole at **runtime, on the user's gpg**, not merely in Atlas's CI. §6
additionally pins gpg's empty-passphrase refusal with a test, so a change in gpg's
policy turns the suite red rather than turning a backup into plaintext.

**Determinism.** The flags above make identical inputs produce a byte-identical *tar*
(verified). **`--format=posix` must not be added**: pax writes `atime`/`ctime`
extended headers that differ between runs, and the archive stops being deterministic
(verified — this RFC's first draft specified it and was wrong).

The **GPG artifact is not byte-identical between runs**, because symmetric encryption
draws a fresh salt and session key. That is correct and required: a deterministic
ciphertext would let an observer prove two backups are equal. Stated here so nobody
later "fixes" it.

**Verification is part of the hook.** A backup that has not been read back is a
hypothesis.

**A known TOCTOU, fail-closed.** The symlink farm archives whatever its targets point
at *when `tar` runs*. A user who swaps a key between the manifest read and the `tar`
gets an archive whose bytes disagree with its archived manifest. Nothing here detects
that; `restore` step 4 does, because it re-checks `privhash` against the manifest
inside the archive. Late, but closed. Removing the window would mean copying the keys
into staging — a plaintext copy on disk, which is worse.

**Failure modes:**

| Condition | Behaviour |
|---|---|
| no owned state, no stale artifact | log "nothing to back up", **exit 0** |
| no owned state, **stale artifact present** | **warn** that it describes state Atlas no longer owns; exit 0 |
| owned state, no passphrase | **exit 4**, guidance, **previous artifact intact** |
| owned state, `gpg` absent | **exit 4**, guidance, **previous artifact intact** |
| **any** owned key missing / mismatched / symlinked | **exit 4**, name the key; back up nothing |
| pipeline fails | **exit 4**, `.tmp` removed, **previous artifact intact** |
| read-back fails, or decrypts with an empty passphrase | **exit 4**, `.tmp` removed, **previous artifact intact** |

"Owned state, no passphrase → exit 4" is a deliberate, narrow **exception** to the
standing convention *"absent credentials degrade to a warning, never a failed install"*
(RFC-0003 §4.4). That rule protects `install`. The whole product of `backup` is the
artifact; a `backup` that returns 0 having written nothing is a lie the user discovers
only when they need it. See Decision 4.

### 4.12 `restore` — validate everything, then write, or write nothing

1. Require the artifact and the passphrase; either absent → exit 4.
2. **List before extracting** — with `tar -tv`, **not `tar -t`**. Probed: `tar -t`
   prints member *names only*; a symlink member and a regular file are indistinguishable
   in its output, so the obvious implementation cannot enforce the rule it claims to.
   `tar -tv` prints the type flag as the first character. Accept a member only if its
   type is `-` (regular file) or `d` (directory), its path begins with `home/` or
   `config/`, and it contains no `..` and no leading `/`. Reject symlinks, hardlinks,
   device nodes, everything else. Then extract with `--no-same-owner`.
   The artifact is Atlas's own, but restore is exactly where a tampered or corrupted
   archive meets the user's `$HOME`.
3. Extract into `mktemp -d` under `/dev/shm` when available, else `$TMPDIR`. Mode `700`,
   removed by the module's single cleanup trap (§5). (`/dev/shm` is tmpfs: it avoids the
   filesystem, but tmpfs pages *can* reach swap, and Fedora does not encrypt swap by
   default. When falling back to a disk-backed `$TMPDIR`, Atlas says so in a log line.)
4. Validate: the manifest parses; every file it names is present; `pubfp` and
   `privhash` match for each.
5. **Scan every target for conflicts before writing any of them:**

   | Target state | Verdict |
   |---|---|
   | absent | will create |
   | present, byte-identical | skip (this is what makes restore idempotent) |
   | present, differs | **conflict** |
   | present, is a symlink | **conflict** (never write through a link) |

6. Any conflict → **write nothing at all**, list every conflicting path, exit 4, and say
   precisely what to do. Partial restores are how identities get destroyed.
7. No conflicts → create `~/.ssh` (`700`) if absent; install each file with its recorded
   mode; **install the manifest last**, so an interrupted restore never claims ownership
   of a key that was not written.

Restore never deletes, never merges, never overwrites. A second `restore` over a
completed one finds everything byte-identical, skips everything, exits 0.

**Restore re-establishes ownership** in the disaster-recovery case — where the live
manifest is *absent*, and restore writes the archived one. If the live manifest is
merely *edited* (so it differs from the backup's), the conflict scan sees the mismatch
and the whole restore refuses, rather than silently re-adopting keys the user disowned.
Either way, restore prints the list of paths it will own *before* it writes anything.

### 4.13 There is no `remove` hook

`module::remove` is deliberately absent, as in `development/github-cli`.

Atlas will not delete a private key. There is no safe generic revert: the key may be
registered on GitHub, on servers, in a signing config. `remove` would be
`rm ~/.ssh/id_ed25519` and a shrug. The README says to do it by hand.

### 4.14 Divergence, and how the user recovers

The module is **divergent** when the manifest does not parse, or when it names a key
that is missing, unreadable, no longer a regular file (a directory, a device), has
become a symlink, or whose `pubfp` or `privhash` no longer matches. Atlas will not
touch that key; `install` and `verify` fail loudly; `backup` and `restore` refuse
**for every key**, not just the divergent one (§4.15).

The manifest is plain text, mode `600`. **Atlas writes it; the user may edit it.**
That is the documented recovery, and the error message says so:

- to **disown** a key (make it external again): delete its line. Atlas stops managing it;
  the key on disk is untouched.
- to **re-adopt** it at its current bytes: delete the line, then set
  `ATLAS_SSH_IMPORT_KEY=<path>` and re-run `atlas install core/ssh`.

There is no `ATLAS_SSH_FORGET_KEY` knob. Deleting a line from a file the user owns is
already the simplest possible interface, and a knob that mutates the manifest is a knob
that can mutate it by accident.

A rotated passphrase (`ssh-keygen -p`) changes `privhash` and therefore reads as
divergence. That is a false positive Atlas cannot distinguish from a swapped key, and
it resolves the same way: re-import. Documented in the README.

`ssh-keygen -p` is the *only* ordinary operation that rewrites a private key file.
Loading a key into the agent — `ssh-add`, including `ssh-add -K` — reads it and never
writes it, so agent use never triggers a false divergence. The README says so, because
a user who sees "divergent" after an `ssh-add` will otherwise assume Atlas is broken.

### 4.15 Hook contracts

The runner maps `install → check install verify` and **skips `install` (and therefore
`verify`) entirely when `check` passes**. Two rules follow, and the first draft of this
RFC broke both:

> **Everything `check` asserts must be work `install` can perform.**
> **`check` performs no network I/O and no mutation.** (`atlas status` must be fast and
> must work on a plane.)

The manifest may name **several** keys, so the predicate is quantified over them. `K` is
the set of `key` records. Let

- `bin` — `ssh` and `ssh-keygen` on `PATH`
- `intact(k)` — `k`'s files exist, `k` is a regular file (not a symlink, not a
  directory), and both `pubfp` and `privhash` match
- `divergent` — `∃k ∈ K : ¬intact(k)`, **or** the manifest does not parse (§4.14)
- `owned` — `∃k ∈ K` (`K` is non-empty)
- `want` — a passphrase is resolvable, **or** `ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE=1`
- `free` — `~/.ssh/id_ed25519` does not exist
- `import` — `ATLAS_SSH_IMPORT_KEY` is set and its record is not already in the manifest
- `ghauth` — `gh` on `PATH` **and** `gh auth token >/dev/null 2>&1` (local, no network)
- `reg(k)` — the manifest has a `github <pubfp(k)>` record

```
check passes  ⟺  bin
              ∧ ¬divergent                              # install reports it and fails
              ∧ ¬(want ∧ ¬owned ∧ free)                 # install generates
              ∧ ¬import                                 # install imports
              ∧ ¬(ghauth ∧ ∃k: intact(k) ∧ ¬reg(k))     # install registers
```

Every failing clause names work `install` performs. `divergent` is the one clause whose
"work" is *to fail loudly* — see row 10.

**Multi-key semantics, stated rather than left to the implementation.** These follow
from the quantifiers and are deliberate:

- **One divergent key poisons the module.** `backup` and `restore` refuse *entirely* —
  they do not back up the intact keys and skip the bad one. Atlas cannot know whether
  the divergence means a compromised machine, and a partial artifact silently missing a
  key is worse than none. Fail closed.
- **Divergence blocks import.** `install` refuses at step 2, before step 4, so an
  unrelated divergent record must be resolved (§4.14) before a new key can be adopted.
- **Registration is per-key.** Each intact key gets its own `github <pubfp>` record, and
  `check` fails while *any* intact key is unregistered and `gh` is authenticated.

**A known limit of row 5.** `ghauth` tests that a token *exists* in `hosts.yml`, not
that it is valid — `gh auth token` validates nothing (RFC-0003 §6.1). With a revoked or
expired token, `check` fails on every run, `install` warns and returns 0 on every run,
and `atlas status` reports `core/ssh` as "not installed" until the user re-authenticates.
That is loud and honest, but it never converges on its own. Documented in the README.

| # | State | `check` | `install` | Why |
|---|---|---|---|---|
| 1 | no `ssh` | ✗ | installs it | |
| 2 | `ssh`, no key, no passphrase | ✓ | *(skipped)* | valid machine; nothing to do |
| 3 | `ssh`, no key, passphrase supplied | ✗ | generates | |
| 4 | `ssh`, owned key, `gh` logged out | ✓ | *(skipped)* | registration impossible; not a fault |
| 5 | `ssh`, owned key, `gh` authed, unregistered | ✗ | registers | converges after `gh auth login` |
| 6 | owned key, registered **by hand** on GitHub | ✗ then ✓ | records `github <fp>` | else `check` fails forever (B8) |
| 7 | `ssh`, external key only, no passphrase | ✓ | *(skipped)* | Atlas owns nothing. Correct and common |
| 8 | `ATLAS_SSH_IMPORT_KEY` set, not in manifest | ✗ | imports | |
| 9 | **external key at the default path + passphrase** | ✓ | *(skipped)* | Atlas will not overwrite it. `verify` **warns** |
| 10 | **divergent** (mismatch / missing / symlink) | ✗ | **fails, exit 4** | the recorded identity is not the one on disk |
| 11 | crash between `ssh-keygen` and manifest append | ✓ | *(skipped)* | key exists, unowned → identical to row 9 |

Rows 6, 9, 10 and 11 are the four states the first draft got wrong, and rows 9/11 are why
the generation clause carries `∧ free`: without it, an external key at the default path
plus a passphrase in `atlas.env` makes `check` fail on **every** run forever while
`install` refuses to overwrite — a module that never converges. This is precisely the
"box with pre-existing keys" the acceptance criteria require.

Row 10 is a permanent red `atlas install` **by design**, and it is not a bricked machine:
the runner tallies failures per module and continues, so every other module still installs
and only `core/ssh` reports `fail` (exit 4 overall). Recovery is one edit (§4.14). Atlas
must not report a provisioned workstation while its recorded identity does not match disk.

Row 9's warning is only visible under `atlas verify` / `atlas doctor`, because the runner
skips `install` — and with it `verify` — when `check` passes. That is the known engine gap
already recorded against `development/github-cli`: the runner has `ok`/`skip`/`fail` but no
`warn`. It needs its own RFC. Listed in §11.

**`install`:**
1. `os::dnf_install openssh-clients gnupg2` (no-op when present)
2. refuse and fail if `divergent`
3. install `$ATLAS_CONFIG_HOME/ssh/known_hosts` from `config/`
4. import (§4.6) if requested
5. generate (§4.5) if requested and the default path is free — else warn
6. register with GitHub (§4.8), best-effort
7. touch nothing external

**`verify`** (may do network I/O; **never fails because the network is down**):
- `ssh`/`ssh-keygen` present and runnable — else fail
- not `divergent` — else fail, naming the key
- owned key modes correct; `~/.ssh` is `700` — else fail with the exact `chmod`
- no owned key → **warn**, exit 0
- row 9 → **warn**: a passphrase is set but the default path holds a key Atlas does not own
- reports external keys by fingerprint and path; touches none
- GitHub connectivity: **reported, never fatal** (below), and skipped entirely when
  `ATLAS_SSH_NO_NETWORK=1` so `atlas verify` is fast and offline-safe

**`update`:** refresh Atlas's `known_hosts` from `config/` (the pinned key may be rotated
by a commit). Touches nothing else. Mirrors `core/git`'s fragment refresh.

**`backup` / `restore`:** §4.11, §4.12. **`remove`:** absent.

**Stdout discipline.** The runner's only stdout channel is the `__SKIP__` token
(`runner.sh:19-21, 74-77`). Every hook writes user-facing output through `log::*`, which
goes to stderr. A hook that prints to stdout corrupts the control channel. Atlas prints
the backup artifact path with `log::info`.

#### The connectivity check cannot test an encrypted key

`ssh -o BatchMode=yes` will not prompt for a passphrase, so a passphrase-protected key
**cannot be tested** without an agent. Atlas determines cheaply and locally whether the
key is encrypted (`ssh-keygen -y -f "$key" -P ''` succeeds ⟺ it is not):

- **unencrypted** → run the live check below;
- **encrypted** → report `cannot test connectivity: the key is encrypted`, and stop.

Atlas never decrypts a key to test it. It would be possible to look the key's `pubfp`
up in `ssh-add -l` and test it when an agent already holds it — the architecture review
recommended cutting that twice, and it is cut: connectivity is *reported, never fatal*,
so the branch buys a nicer message on the fiddliest code path in the module. It is
recorded as deferred, not overlooked (§11).

The check uses `-o IdentitiesOnly=yes -i <owned key>`: without it a *different* key in
the agent produces a false pass.

**And it must not use the exit code.** `ssh -T git@github.com` exits **1 on success**
(GitHub refuses the shell after authenticating) and 255 on failure. Verified. Success is
`successfully authenticated` on stderr; `Permission denied` means the key is not
registered; anything else is a network or host-key fault.

---

## 5. Idempotency & fail-safety

- Every hook is safely re-runnable; a second `install` generates, imports and registers
  nothing.
- Every refusal happens **before** anything is written (the `core/git` convention).
  `restore` scans all conflicts before creating any file.
- Nothing in this module deletes a file the user created.
- No hook relies on `set -e` (§4.0). Every fallible command is explicitly checked,
  `mktemp` above all.
- The plaintext tar exists only as a pipe; backup staging is a symlink farm; restore
  staging is on tmpfs where available.
- A good backup artifact is never truncated by an unverified one (§4.10 item 3).
- The manifest is written last in `restore` and atomically (same-dir temp + `mv`)
  everywhere else.
- `install` is skipped when `check` passes, so `check` never asserts anything `install`
  cannot perform (§4.15).

### 5.1 Temp-directory cleanup: exactly one trap, over a global

Two hooks in this module create temp directories that may contain key material — the
askpass tmpdir (§4.5) and the restore staging dir (§4.12). The obvious pattern is
wrong, in two ways that were probed against the real runner:

1. **A later `trap … EXIT` silently replaces an earlier one**, and for `atlas install`
   the `check`, `install` and `verify` hooks share **one subshell**. A trap registered
   in `install` therefore discards a trap registered in `check`, and that `check` temp
   dir — possibly holding a private key — is never removed.
2. **A trap body that names a hook `local` fires after the local is gone.** Under the
   subshell's `set -u` the trap itself errors (`staging: unbound variable`) and the
   subshell exits **1** — turning a module whose hook body *succeeded* into a reported
   failure. Verified: hook body ran to completion, `return 0`, subshell `rc=1`.

Traps are subshell-global and fire once, at subshell exit — not at hook return. So the
module keeps **one** module-scope array and registers **one** idempotent trap:

```sh
_SSH_CLEANUP=()                       # module scope, not a hook local
_ssh_cleanup() { local p; for p in "${_SSH_CLEANUP[@]:-}"; do [ -n "$p" ] && rm -rf -- "$p"; done; }
_ssh_track()   {                      # register the trap at most once
  [ -n "${_SSH_TRAP_SET:-}" ] || { trap _ssh_cleanup EXIT; _SSH_TRAP_SET=1; }
  _SSH_CLEANUP+=("$1")
}
```

`"${_SSH_CLEANUP[@]:-}"` and `${_SSH_TRAP_SET:-}` are `-u`-safe; the trap body touches
only globals; `rm -rf --` never runs on an empty string. Cleanup is deferred to subshell
exit rather than hook return, which is acceptable: the subshell is per-module and
short-lived. This is the pattern every future module with a temp dir must copy.

---

## 6. Testing

Every test sandboxes `HOME`, `ATLAS_CONFIG_HOME`, `ATLAS_STATE_DIR`, `GH_CONFIG_DIR` and
`GNUPGHOME` into a fresh temp dir, and mocks `os::dnf_install`. **No test touches the real
`$HOME`, runs real `dnf`, or contacts GitHub.** `gh` is a shell function recording argv and
stdin, starting with `local -; set +x` (RFC-0003) so the mock's own internals cannot be
mistaken for a leak.

`ssh-keygen`, `tar` and `gpg` are **real** — hermetic, fast, and mocking them would test
the mock. This is where Atlas's tests stop proving "we called the right command" and start
proving "the artifact has the property we claim".

**Hooks are invoked as the runner invokes them** — `if ! module::install` — not bare under
`set -e` (§4.0). Runner-level tests use `set +e; set -uo pipefail` (RFC-0003 §6).

| Scenario | Asserts |
|---|---|
| fresh workstation, no passphrase | nothing generated; exit 0; warning emitted |
| fresh, passphrase | key generated; **`ssh-keygen -y -P ''` fails, `-P "$pass"` succeeds** |
| fresh, `ALLOW_EMPTY_PASSPHRASE=1` | key generated, unencrypted, loud warning |
| existing external keypair | byte-identical before/after `install`; manifest empty |
| external key at default path + passphrase (row 9) | `check` passes; nothing overwritten; `verify` warns |
| imported keypair | manifest records it; file mode and content unchanged |
| Atlas-managed keypair | `check` passes; second `install` is a no-op |
| **swapped private half, `.pub` intact** | divergent: `install`/`verify` fail; **key untouched**; `backup` refuses |
| symlinked owned path | divergent; refused |
| key registered on GitHub by hand (row 6) | `install` records it; `check` then passes |
| permission failures (`~/.ssh` `755`, key `644`) | `verify` fails; **no `chmod` performed** |
| backup, no owned state | exit 0, no artifact |
| backup, no owned state, stale artifact | exit 0, warning |
| backup, no passphrase | exit 4, no artifact |
| **backup, resolver fails mid-run** | exit 4; **no artifact decryptable with an empty passphrase** |
| **failed backup over a good artifact** | exit 4; **the previous artifact is byte-identical** |
| backup | artifact mode 600; decrypts; contains **exactly** the owned files |
| backup determinism | two runs → identical *tar*; **different ciphertext** |
| **two owned keys, one divergent** | `backup` refuses both; neither key touched |
| restore into empty `$HOME` | files created, modes correct, idempotent on rerun |
| restore, byte-identical target | skipped, exit 0 |
| restore, conflicting target | exit 4; **target unchanged**; nothing else written |
| restore, target is a symlink | exit 4; **never written through** |
| restore, artifact with `../`, absolute, or **symlink** member | refused before extraction |
| **malformed / CRLF / orphan-`github` manifest** | fails closed as divergent |
| repeated install / backup / restore | converge, exit 0 |
| `verify` / `doctor` / `status` | correct on each state above |
| `verify` offline | passes |
| **trap discipline** | a hook that creates a temp dir and succeeds returns **0**, not 1 |
| secret discipline | no passphrase in any `bash -x` trace; no secret assigned |

New static rules in `tests/test_secret_discipline.sh`, each verified to fire on a planted
violation:

- a process substitution feeding a secret fd may contain nothing but `env::get_secret`;
- `gpg` is never passed `--passphrase` or `--passphrase-file` (only `--passphrase-fd`);
- `ssh-keygen -N` appears only on the documented empty-passphrase path;
- no hook body relies on `set -e` for a fallible command's failure (heuristic: an
  unchecked `mktemp`/`cd`/`cp` at statement position).

And, per the standing practice from RFC-0003: **the module is driven end-to-end under
`bash -x` against a sandboxed `HOME`, and the trace is grepped for both passphrases.**
Unit tests cannot find call-site trace leaks.

### 6.1 Assumptions about the tools' contracts

Probed 2026-07-10 (OpenSSH 9.6p1, GnuPG 2.4.4, GNU tar 1.35, gh 2.45.0). Each must be
re-checked on the Fedora acceptance box.

| # | Assumption | Evidence |
|---|---|---|
| 1 | `ssh-keygen -f k </dev/null` with no `-N` silently makes an **unencrypted** key, exit 0 | probed; neither hangs nor fails |
| 2 | `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force` supplies the passphrase at generation, no tty | probed; key then requires that passphrase |
| 3 | **`ssh-keygen -lf <private>` reads the sibling `.pub` when present** — it does not fingerprint the private half | probed; swapped private half went undetected |
| 4 | `sha256sum` of an encrypted private key works without the passphrase, and is stable | probed |
| 5 | `ssh -T git@github.com` exits **1 on success**, 255 on failure | probed |
| 6 | a wrong pinned host key fails closed (`HOST IDENTIFICATION HAS CHANGED`, 255) | probed |
| 7 | `gh ssh-key add -` reads a public key from stdin, exit 0 | probed |
| 8 | `gpg --passphrase-fd 3 --symmetric` with data on stdin needs no plaintext file | probed |
| 9 | GPG symmetric output is **not** byte-deterministic | probed (fresh salt) |
| 10 | `tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner` **is** byte-deterministic — **and adding `--format=posix` breaks it** (pax `atime`/`ctime` headers) | both probed, with the exact pipeline flags |
| 11 | a process substitution inherits `xtrace`; `<(printf …)` leaks, `<(env::get_secret …)` does not | probed both ways |
| 12 | `gpg --passphrase-fd` with **empty** input refuses (`Invalid passphrase`, exit 2, no artifact) — encrypt *and* decrypt | probed |
| 13 | `errexit` is suspended inside a hook invoked as `if ! module::x`, recursively; `-u` and `pipefail` are not | probed (§4.0) |
| 14 | `pipefail` shapes a pipeline's own `$?` but nothing consumes it: a failing `tar \| gpg` **mid-hook** is silently swallowed | probed (§4.11) |
| 15 | `gpg --batch --yes -o F` truncates an existing `F` before writing | probed (§4.10 item 3) |
| 16 | **`tar -t` prints member names only**; it cannot distinguish a symlink member from a regular file. `tar -tv` prints the type flag | probed (§4.12) |
| 17 | a `trap … EXIT` set in a hook is **subshell-global**, fires at subshell exit, and a later one **replaces** it | probed (§5.1) |
| 18 | a trap body naming a hook `local` errors under `-u` after the local dies, flipping a **successful** module to `rc=1` | probed (§5.1) |

Assumptions 2 and 3 are load-bearing. If Fedora's `ssh-keygen` ever declines `SSH_ASKPASS`
at generation, Atlas must **refuse to generate** rather than fall back to `-N` (argv) or an
empty passphrase; the module asserts the generated key requires its passphrase and aborts
if it does not.

---

## 7. Documentation

- `modules/core/ssh/README.md` — ownership classes; the four env vars; what Atlas does
  *not* do; the outward-facing GitHub write, stated plainly; backup/restore; divergence and
  how to recover; how to remove a key by hand.
- `docs/conventions.md` — new **"Owning persistent state"** section (manifest, dual
  binding, symlink refusal, validate-then-write, conflict-scan-before-restore) and the
  **backup contract** of §4.10. Extend **"Secrets"** with the process-substitution rule.
  Amend "never add a runtime dependency" to permit `gpg`, with the reason. Add the **`set -e`
  is suspended inside hooks** fact to the Bash section — it is engine-wide, not SSH-specific.
- `CHANGELOG.md`, `docs/rfcs/README.md` index row.

---

## 8. Alternatives considered

1. **Own `~/.ssh/id_ed25519` by path.** Rejected: indistinguishable from a key the user
   made five minutes earlier.
2. **Bind ownership with `ssh-keygen -lf` alone.** Rejected — *and it is the design this
   RFC's first draft specified.* It reads the sibling `.pub` and never sees the private
   half (§6.1 #3).
3. **`ssh-keygen -N "$pass"`.** Rejected: `argv` is world-readable in `/proc`.
4. **Generate an unencrypted key by default.** Rejected: the single most consequential
   default in Atlas.
5. **`ssh-keyscan` the host key at install time.** Rejected: TOFU during automated
   provisioning records an attacker as trusted.
6. **`gpg --passphrase-file`.** Rejected: a plaintext passphrase on disk.
7. **`--format=posix` for the tar.** Rejected: pax `atime`/`ctime` headers destroy
   determinism. (`--pax-option=delete=atime,delete=ctime` would restore it, but the default
   format already works and needs no flag.)
8. **Encrypt the backup to the user's GPG *public* key** (asymmetric). Genuinely
   attractive: no passphrase to manage, and the secret never enters Atlas at all. Deferred
   only because it presumes a GPG keypair — a *fourth* identity to provision, and this
   module has not yet provisioned the first. Worth an RFC once `core/gpg` exists; the
   manifest and pipeline here are unchanged by it.
9. **Back up `~/.ssh` wholesale.** Rejected by the owner's ruling.
10. **Deterministic ciphertext.** Rejected: it leaks equality of plaintexts.
11. **`chmod` a badly-permissioned user key.** Rejected: modification of user state.
12. **An `ATLAS_SSH_FORGET_KEY` knob.** Rejected: the manifest is a text file; deleting a
    line is a simpler interface than a knob that can mutate it by accident (§4.14).
13. **`verify` performs the GitHub registration** (so ordering never matters). Rejected:
    `verify` backs `atlas doctor`, and a *doctor* run that writes to the user's GitHub
    account is a category error. It would also not help — `core/ssh`'s `verify` still runs
    before `development/github-cli`'s `install` in the same pass.
14. **A soft `MODULE_AFTER` ordering array.** An engine change; the sprint freezes the
    architecture and requires an RFC instead. Not on the table here.
15. **`gpg -o "$artifact"` directly, verifying afterwards.** Rejected: `--yes` truncates
    the previous good artifact *before* the new one is verified. Write `.tmp`, verify,
    `mv`.
16. **`tar -t` for the restore allow-list.** Rejected: it prints names only and cannot
    see member types, so it silently permits the symlink members it purports to reject.
17. **A `trap … EXIT` per hook, over a `local`.** Rejected twice over: a later hook's trap
    replaces it, and the trap body errors under `-u` once the local is gone — turning a
    healthy module into a reported failure (§5.1).

---

## 9. Decisions

**All seven ruled by the owner on 2026-07-10, as recommended.** Decisions 1, 2, 5 and 6
were put to the owner explicitly; 3, 4 and 7 were accepted with the RFC. The rulings are
recorded verbatim in each subsection and are now normative — a change to any of them
requires a superseding RFC, not an implementation decision.

### 9.1 Decision 1 — `MODULE_DEPENDS=()`, reversing the first draft

**Owner ruling (2026-07-10): no dependency. `MODULE_DEPENDS=()`.**

`core/ssh` needs `gh` only for an optional step, but `MODULE_DEPENDS` is Atlas's only
ordering mechanism, and `module::discover` sorts alphabetically — so on a bare `atlas
install`, `core/ssh` runs **before** `development/github-cli`. The first draft therefore
proposed declaring the dependency to force ordering.

The architecture review reversed this, and the reasoning is decisive:

**`MODULE_DEPENDS` orders *installation*; registration needs *authentication*.** RFC-0003
(Accepted) authenticates `gh` only from a pre-supplied `ATLAS_GH_TOKEN`, and the sprint's
Definition of Done explicitly permits `gh auth login` as a **manual** step. In the canonical
flow — fresh box, no pre-staged token, `gh auth login` by hand — registration lands on a
later run *whether or not the dependency is declared*. The dependency buys a one-pass
install only for the user who pre-staged **both** secrets in `atlas.env`; that user gets a
free, idempotent second `atlas install` anyway.

Meanwhile `check` row 5 already makes the module self-healing: the run after `gh auth login`
registers the key. Registration converges on *authentication* — which `MODULE_DEPENDS`
cannot order — rather than on *installation*, which it can but which does not matter.

The costs of declaring are real: `atlas install core/ssh` on a GitHub-less box would drag in
`gh`, contradicting this module's own refusing-by-default posture; and `core` → `development`
is a layering inversion that, shipped in the reference stateful module, becomes precedent.

**Recommendation: do not declare.** The README carries one line — *"if you authenticate `gh`
after the first run, run `atlas install` again to register the key"* — which is needed in the
manual-auth flow regardless, and is the tell that the dependency buys nearly nothing.

### 9.2 Decision 2 — generation is opt-in

**Owner ruling (2026-07-10): generation is opt-in.**

A brand-new Fedora box finishes `atlas install` **without an SSH key** unless the user set
one variable. This is "the minimal manual step where security demands it", applied to the
most security-demanding artifact on the machine. *Recommend: accept.*

### 9.3 Decision 3 — `verify` fails on bad permissions, but never repairs them

**Owner ruling (2026-07-10): accepted.**

OpenSSH refuses a `644` private key, so the module is genuinely unhealthy. But `chmod`-ing a
user's file is a modification, and the ownership ruling admits no exception. Atlas prints the
command. *Recommend: accept.*

### 9.4 Decision 4 — `backup` fails when it has state but no passphrase

**Owner ruling (2026-07-10): accepted.**

A narrow, stated exception to "absent credentials degrade to a warning, never a failed
install". That rule protects `install`. Here the credential is the only thing between the
user's private key and a plaintext archive. With **no owned state**, `backup` is a no-op
success and needs no passphrase. *Recommend: accept.*

### 9.5 Decision 5 — one backup passphrase for the platform verb

**Owner ruling (2026-07-10): one platform-wide `ATLAS_BACKUP_PASSPHRASE`; no per-module override.**

`atlas backup` fans out to every module. If each stateful module minted its own
`ATLAS_<MODULE>_BACKUP_PASSPHRASE`, one verb would eventually demand N secrets. So:
**`ATLAS_BACKUP_PASSPHRASE` is the platform-wide secret**, and there is no per-module
override until a second stateful module proves it needs one.

The trade-off is real and belongs to the owner: **one passphrase protects every
artifact.** Compromise it and every module's backup opens. Per-module *scoping* would be
theatre — modules are unsandboxed repo code running as the same user, and any module's
`backup` hook can already read `~/.ssh` directly — so the choice is genuinely between one
secret and N secrets for one verb, not between one blast radius and N.

This is a cross-cutting convention rather than an engine change (no code in `internal/`
moves), but it is a decision the *first* stateful module makes on behalf of every later one,
so it is surfaced here rather than settled by accretion. *Owner ruling requested.*

### 9.6 Decision 6 — Atlas does not touch `~/.ssh/known_hosts`

**Owner ruling (2026-07-10): Atlas does not touch `~/.ssh/known_hosts`.**

Atlas maintains its own pinned `known_hosts` for its own checks. It *could* also append the
pinned GitHub entry to the user's file when that file has no `github.com` entry — recording
the exact line in the manifest so it remains an entry Atlas owns. That would remove the TOFU
prompt from the user's first clone.

*Recommend: no, in v1.* It is the only place in this design where Atlas would write into a
user-owned file for convenience, and the ruling names `known_hosts` explicitly. The prompt is
one keystroke, and it is the user's trust decision to make.

### 9.7 Decision 7 — `gnupg2` becomes a runtime dependency

**Owner ruling (2026-07-10): accepted.**

Mandated by the backup ruling ("encrypted locally"). `docs/conventions.md` is amended rather
than quietly contradicted. *Recommend: accept.*

---

## 10. Implementation plan

1. RFC review → owner rulings on Decisions 1–7 → status `Accepted`.
2. Failing tests first: the scenario table in §6, red.
3. `module.sh` — manifest read/write/validate (dual binding, symlink refusal); then `check`;
   then `install`; then `verify`.
4. `backup`, then `restore` (list-before-extract; conflict scan before any write).
5. Extend `tests/test_secret_discipline.sh` with the four new static rules; verify each fires
   on a planted violation.
6. End-to-end under `bash -x` on a sandboxed `HOME`; grep the trace for both passphrases.
7. Add no-op `backup`/`restore` to `core/git` (deferred by RFC-0003 §4.8), so every module
   answers every verb.
8. Reviews: implementation, security, RFC-compliance, documentation (Opus). Then Luna:
   simplify, document, automate.
9. `docs/`, `CHANGELOG.md`, module inventory. Merge.

## 11. Acceptance criteria

- [ ] Every scenario in §6 passes; suite green; no test touches real `$HOME`/`dnf`/GitHub.
- [ ] `bash -x` end-to-end trace contains neither passphrase.
- [ ] Backup artifact decrypts and contains **exactly** the owned files.
- [ ] Restore into a conflicting `$HOME` writes **zero** bytes and exits 4.
- [ ] A swapped private half is detected; the key is left untouched.
- [ ] An external key is byte-identical before and after `install`, `verify`, `backup`.
- [ ] `atlas verify` passes offline.
- [ ] `core/git` answers `backup`/`restore` as no-ops.
- [ ] Manual acceptance on clean Fedora **and** on a box with pre-existing keys, with real
      `gh`, real GitHub, real `gpg` — recorded in the production-readiness report.

### Follow-up work this RFC surfaces (not blocking)

- **Engine:** the runner has `ok`/`skip`/`fail` but no `warn`. Rows 4 and 9 are invisible in
  an `atlas install` summary. Needs its own RFC.
- **Engine/audit:** `set -e` is suspended inside every hook (§4.0). `core/git` and
  `development/github-cli` were written without knowing this and must be audited for any
  fallible command that relies on it — and for any `trap … EXIT` set inside a hook (§5.1),
  which can both leak a temp dir and flip a healthy module to `rc=1`.
- **Deferred, not overlooked:** `verify` could test connectivity for an *encrypted* key
  already loaded in `ssh-agent` by matching its `pubfp` against `ssh-add -l`. Cut from v1.1
  on the architecture review's recommendation — connectivity is reported, never fatal.
- **Deferred:** a per-module backup passphrase override, if a second stateful module ever
  needs one (Decision 5).
- **Docs:** `CONTRIBUTING.md` should record that the suite is verified on Linux/WSL, not Git
  Bash.

---

## 12. Errata (post-implementation, 2026-07-10)

Corrections made after the implementation and its reviews, recorded here rather than
by rewriting the body (per the RFC process: an accepted RFC is amended by a dated note,
not silently edited). None changes a design decision.

- **§4.15 said `verify` "reports external keys by fingerprint"; the first implementation
  reported by path only.** Corrected in code — `verify` now logs both the fingerprint and
  the path — and the wording above is fixed. (RFC-compliance review.)
- **`ATLAS_SSH_NO_NETWORK=1` was implemented and documented in the README but not named in
  this RFC.** It skips the GitHub connectivity probe so `atlas verify` is offline-safe.
  Added to §4.15's `verify` list.
- **`ATLAS_SSH_STAGING_DIR` is a knob this RFC did not anticipate.** It overrides the base
  directory for key-material staging — for an operator whose `/dev/shm` is too small for a
  large backup, and for the test suite (a per-sandbox directory, so tests never share the
  global `/dev/shm`). Its addition surfaced a real gap: an override to a *disk* directory
  must still warn that key material touches the disk. The warning is now keyed on the
  filesystem *type* (`stat -f`), so an override to disk warns exactly like the involuntary
  `$TMPDIR` fallback (§4.11 / §4.12 step 3). Documented in the README and `docs/conventions.md`.
- **§4.12's "restore re-establishes ownership" was imprecise.** It is true only when the
  live manifest is *absent* (disaster recovery). An *edited* live manifest differs from the
  backup's and is caught by the conflict scan, so the whole restore refuses rather than
  re-adopting disowned keys. Wording tightened.
