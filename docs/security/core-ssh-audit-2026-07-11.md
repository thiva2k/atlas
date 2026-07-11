# Security audit — `core/ssh` (RFC-0004)

**Date:** 2026-07-11 · **Commit under audit:** `feat/ssh` @ post-`1be2b9a` (the
`~/.ssh` ownership constraint) · **Auditor:** self-run, after three subagent
security-audit attempts failed to complete (two session limits, one watchdog stall).
**Environment:** OpenSSH 9.6p1, GnuPG 2.4.4, GNU tar 1.35, bash 5.2, on WSL Ubuntu.
Every check ran in a sandboxed `$HOME`/`ATLAS_CONFIG_HOME`/`ATLAS_STATE_DIR`/`GNUPGHOME`;
no real `$HOME`, `dnf`, `gpg` keyring, or GitHub was touched.

## Verdict

**SECURE-TO-MERGE**, with one finding fixed in this branch and the manual real-`gh`
acceptance run still outstanding (RFC §11).

## Finding (fixed)

**F-SSH-1 · Write-anything-under-`$HOME` on restore of a tampered artifact · LOW.**
In disaster recovery (a clean `$HOME` with no live manifest), a backup artifact whose
archived manifest named a path such as `.bashrc` caused `restore` to write that file
under `$HOME`. Because the manifest also carries the recorded `privhash`, the file's
*content* is attacker-chosen, so this is arbitrary-content write → RCE on the next shell.

- **Attacker model:** must know `ATLAS_BACKUP_PASSPHRASE` (in `~/.config/atlas/atlas.env`,
  mode 600) **and** be able to replace the artifact file. On a single machine both imply
  same-uid access to `$HOME`, which already permits writing `~/.bashrc` directly — no
  escalation. The realistic vector is the artifact's *intended portability*: it is meant
  to be copied off-box, where a tamperer who also knows the passphrase could plant a
  payload that fires on a later `atlas restore`.
- **Fix:** owned keys are constrained to live directly in `~/.ssh` (SSH keys' natural
  home). `import` and `restore` both refuse any other path. The generated key
  (`.ssh/id_ed25519`) and normal imports are unaffected. Regression-tested (restore and
  import). Recorded in RFC-0004 §12.

## Checks that passed (18/18 after the fix)

**A. Secret leakage** — neither passphrase appears in a full install→backup→restore
`bash -x` trace, nor in any Atlas-owned file; the empty-passphrase path yields an
unencrypted key as requested; **a passphrase kept only in `atlas.env` never reaches
`ssh-keygen`'s environment** (`/proc/<pid>/environ`) — the module's bare
`export ATLAS_SSH_KEY_PASSPHRASE` marks the name without a value; the askpass helper is
removed after generation.

**B. Key material at rest** — no plaintext private-key *file* (as opposed to a symlink)
appears outside `~/.ssh` during backup (raced with a 200-iteration watcher); artifact
mode 600, manifest 600, config dir 700; the decrypted archive is removed from staging on
the restore *failure* path, not merely at subshell exit.

**C. Malicious artifact** — `rel=.bashrc` refused (F-SSH-1 fix); a symlink member
(`→ /etc/passwd`) rejected before extraction; a normal artifact will not decrypt with an
empty passphrase.

**D. Ownership** — a key whose *public* half was swapped is detected as divergent and is
**not** uploaded to GitHub.

**E. TOCTOU** — flipping `atlas.env` to world-readable between `check` and `backup` makes
`backup` refuse (no artifact written), because `env::get_secret` re-checks the mode.

## Residual risks (for known-limitations)

- **tmpfs swap.** Key material staged on `/dev/shm` is in RAM but tmpfs pages can be
  swapped, and Fedora does not encrypt swap by default. Atlas warns when staging is not
  on a tmpfs at all; it cannot prevent swap of tmpfs pages.
- **Environment-variable secrets.** A passphrase the user *exports* (rather than putting
  in `atlas.env`) is visible to same-uid processes via `/proc`. This is inherent to
  environment variables and is the caller's choice; `atlas.env` (mode 600) is the
  recommended channel.
- **Same-uid / root attacker.** Nothing here defends the user's keys against a process
  running as the same uid or as root; such an attacker owns the keys directly.
- **The mock proves Atlas's logic, not the tools' contracts.** `gh` is mocked and the
  network is never touched. The RFC §11 manual acceptance run against real `gh`, real
  GitHub, and real `gpg` on the clean Fedora box remains required before the v1.1 tag.
