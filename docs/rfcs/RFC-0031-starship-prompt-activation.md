# RFC-0031: Starship prompt activation — Atlas-owned, reversible shell wiring

Status: Accepted (Revision 3)

Date: 2026-07-14

Revised: 2026-07-14

Extends: RFC-0029 (Activation framework)

## 0. Revision history

- **Rev 1** (Proposed): first draft. Judged **RED** — three contract-level holes,
  all verified by actually hashing the live machine:
  - **F1 — false byte-identity premise.** Rev 1 claimed the live hand-written
    snippet `~/.config/fish/conf.d/10-atlas-starship.fish` was byte-identical to
    the RFC's fixed template and would be "adopted as absent-prior." This is
    **false.** The live file's comment header (`# Atlas full-UX activation
    (2026-07-13)… # User-owned wiring — NOT managed by development/fish…`) differs
    from the template's header; only the four functional lines match. The hashes
    therefore differ (live `23b220…`, template `dccf4c…`), so on the real machine
    Rev 1's "adopt iff byte-identical" rule would take the **foreign-file
    refuse-to-clobber** branch — the opposite of the claimed adoption. Test 6
    encoded this falsehood.
  - **F2 — user-file destruction in two interruption timelines**, contradicting
    the RFC's own "never destroys divergent user bytes": (a) a resumed
    `state=activating` wrote the snippet unconditionally (`mv -f`), overwriting
    whatever a user placed at the path during the window; (b) `deactivate` under
    `state=activating` `rm -f`'d the on-disk file while claiming it was "verified
    in step 2," but step 2 only verified under `state=active`.
  - **F3 — no snippet hash in the escrow.** Ownership was judged by comparing the
    on-disk file to the *current in-code template*. Any future one-byte template
    edit would make every already-activated machine's snippet "not match," and
    both verbs would permanently take the disown branch — a self-bricking escrow
    across Atlas upgrades.
- **Rev 2**: kept everything the judge validated (no engine change;
  config-only install; binary **required but not installed**; distinct filename
  from `development/fish`'s `00-atlas.fish`; honest no-DBus-live-apply) and
  replaces the fragile "adopt iff byte-identical" story with a **robust
  RECORD-VERBATIM design** that honors RFC-0029's record-before-switch invariant
  for *any* pre-existing file:
  - **F1 fix:** on activate, if any file already exists at the snippet path, back
    up its **exact prior bytes** to a sibling under `$ATLAS_STATE_DIR` and record
    `prior_conf=present` + `prior_conf_sha256=<hash of the backup>`; if no file
    existed, record `prior_conf=__ATLAS_ABSENT__`. `deactivate` restores the
    backed-up bytes verbatim (or deletes, if absent). The live hand-written
    snippet is now a **normal, non-refusing case** — its bytes are recorded and
    restored. No byte-identity-with-template claim is made anywhere.
  - **F2 fix:** a resumed `state=activating` verifies the on-disk file is absent
    or the already-recorded prior/backup before writing — a *new* foreign file in
    the window is **refused, never overwritten**. `deactivate` verifies the
    on-disk file is the Atlas-owned snippet (by the recorded `snippet_sha256`, F3)
    **before** deleting — an unowned file is **refused, never removed**.
  - **F3 fix:** activate records `snippet_sha256=<hash of the bytes it actually
    wrote>` in the state file. Every ownership check (refuse-to-clobber,
    deactivate delete-guard) compares the on-disk file to that **recorded** hash,
    not the current template — so a later template edit cannot brick an
    already-activated machine.
  - Non-blocking notes addressed: §5.7 honestly names the post-activation
    "healthy-but-broken-wiring" hazard per RFC-0024a's failure-class framing; §8
    adds the missing tests.
- **Rev 3** (this): Rev 2's F1/F2/F3 fixes are **confirmed good and kept
  unchanged** — but the second adversarial review judged Rev 2 **RED** on **two
  new contract-level holes the backup mechanism introduced**, plus one
  non-blocking nit. Rev 3 fixes exactly these and disturbs nothing else:
  - **B1 — interrupted-deactivate false-drift + mis-ordered backup removal
    (blocking).** In Rev 2, after a `deactivate` restore `mv` lands but before
    `state=inactive` is written, the on-disk file holds the *prior* bytes, which
    hash to `prior_conf_sha256` — **not** `snippet_sha256`. Rev 2 §5.6 step 2's
    ownership branch classified that as "edited/replaced since activation" and
    took **refuse-to-clobber** — a *false* drift accusation on a normal crash,
    contradicting §8 test 15 (which demands finalize). Rev 2 also removed the
    backup **before** writing `state=inactive`, so a crash in that window (backup
    gone, state still `active`, prior bytes on disk) dead-ended. **Fix:** mirror
    the theme reference's already-restored finalize + write-state-after-restore
    ordering. Add an ALREADY-RESTORED finalize branch to §5.6 for
    `prior_conf=present` (on-disk == `prior_conf_sha256` ⇒ finalize, not refuse);
    reorder deactivate to **write `state=inactive` before removing the backup**.
    Ownership step 2 now classifies four cases explicitly (own-snippet → restore;
    already-restored prior → finalize; absent → per contract; only a genuine
    fourth value is drift). §8 test 15 rewritten; a new test 15a covers
    crash-after-restore-before-state.
  - **B2 — the fixed backup path was not write-once across escrow generations
    (blocking).** After a **disown** (delete the state file — the exact escape the
    refuse messages instruct), the on-disk file was already the Atlas snippet
    (written at first activation), so the orphaned backup at the *fixed* path was
    the **only surviving copy** of the user's pre-Atlas bytes. A fresh `activate`
    backed the current on-disk file up **to that same fixed path**, silently
    overwriting the sole copy — destroying user bytes, breaking the "never
    destroys divergent user bytes" invariant. Rev 2 §8 test 17 blessed this.
    **Fix:** make the backup **write-once / non-destructive across generations**
    via **unique backup naming** — `activate` creates each backup with a `mktemp`
    filename in the backups dir and records that filename in the state file as a
    new key `backup_ref=<name>`; every restore/verify/remove uses the recorded
    `backup_ref`. A disown leaves a uniquely-named inert orphan; a fresh
    `activate` mints a **new** unique backup and can never overwrite the orphan.
    Parser gains a strict rule for `backup_ref`; §5.2/§5.4/§5.5/§5.6 and §8 test
    17 updated so disown-then-reactivate provably cannot destroy the orphan.
  - **N1 — resume pre-write guard too narrow (non-blocking).** The F2a resume
    guard accepted the on-disk file being the Atlas snippet only at "the hash we
    are about to write." After an Atlas *template upgrade*, a resumed activation
    whose disk already held Atlas's *previously-written* snippet (the recorded
    `snippet_sha256`) would be wrongly refused as foreign. Rev 3 adds the recorded
    `snippet_sha256` as an accepted arm of the resume guard (§5.5, F2a).

## 1. Summary

RFC-0029 established a reversible, opt-in activation model (`atlas activate` /
`atlas deactivate`, an optional `module::activate` / `module::deactivate` hook
pair, and a separate `$ATLAS_STATE_DIR/activated/<category>-<name>` state file
with a **write-once** prior escrow). It implemented exactly one reference:
`desktop/theme`, a KDE ColorScheme flip. RFC-0029 §3 explicitly deferred
`development/starship` activation to a follow-up RFC because it "needs shell
wiring + a binary Atlas does not install, which are materially different from a
KConfig flip." **This is that follow-up.**

`development/starship` installs an *isolated prompt config* at
`~/.config/atlas/starship/starship.toml` and deliberately does **not** install
the Starship binary, wire it into any shell, or touch user shell config (its
module header says so verbatim, and `module.sh` never calls `starship init` nor
writes to `conf.d`). Consequently, on a fully "installed" workstation the Atlas
prompt is present but inert — the exact "installed but off" gap RFC-0029 was
written to close.

In live use this gap was bridged by a **hand-written, user-owned** fish snippet,
`~/.config/fish/conf.d/10-atlas-starship.fish`, which prepends `~/.local/bin` to
`PATH`, sets `STARSHIP_CONFIG` to the Atlas config, and runs
`starship init fish | source` when interactive. Its own comment reads
"User-owned wiring — NOT managed by development/fish ... To undo: delete this
file." This RFC makes Atlas **own that activation reversibly**: `activate` writes
Atlas's own snippet (as Atlas-owned, hashed content) *after* recording — byte for
byte — whatever was at the path before; `deactivate` restores precisely that
recorded prior (the exact prior bytes, or absence) and returns the machine to its
pre-activation state.

The RFC-0029 invariant is inherited unchanged:

> **Atlas may switch a user-owned setting to its own asset only after recording
> the exact prior value exactly once, and `deactivate` restores that recorded
> value verbatim. A fresh machine, activated then deactivated, returns to
> precisely its pre-Atlas state — including a file that did not exist before.**

Here the "setting" is *the content (or absence) of the file at the snippet path*,
and Rev 2 records that prior **verbatim** — either the exact prior bytes (backed
up out-of-band) or the absent sentinel (§5.2). This is the honest reading of
"restores the recorded value verbatim": the live hand-written snippet is
preserved and restored, not deleted on a byte-identity guess.

## 2. Goals

- Make the Atlas Starship prompt **actually active** in interactive fish, via an
  explicit, opt-in `atlas activate development/starship` — never during install.
- Reuse the RFC-0029 contract **exactly**: the two verbs and the hook pair already
  exist (no engine change), the `activated/development-starship` state file, the
  write-once prior escrow via a transitional `activating` state, the refuse-to-
  clobber guard, the interrupted-deactivate finalize, and the disown path.
- Own **only** the one wiring snippet Atlas writes; leave `development/fish`'s
  `00-atlas.fish`, the user's `config.fish`, and every other user shell file
  untouched. `deactivate` removes **only** the Atlas Starship snippet.
- **Record any pre-existing file at the path verbatim** before overwriting it, and
  restore it verbatim on `deactivate` — so a fresh machine, or the live
  hand-written machine, activated then deactivated, returns to precisely its
  pre-activation bytes.
- Require the prerequisite `starship` binary to be present and reject activation
  with clear guidance when it is not — Atlas will not wire a prompt whose engine
  is missing (mirroring how `desktop/theme` requires `plasma-apply-colorscheme`).
- Be honest about live effect: there is **no DBus live-apply** here. Already-open
  shells do not change; the wiring takes effect in the next interactive fish (or
  after `source`-ing the snippet). `activate` says so. Be equally honest about the
  post-activation failure class (§5.7).

## 3. Non-goals

- **No binary install in this RFC.** Whether `development/starship` should install
  the Starship binary is a real question, answered in §5.1 and §7: it is a change
  to the *module's install*, not to activation, and is out of scope here.
  Activation **requires** the binary present and fails cleanly otherwise.
- **No bash / zsh / other-shell wiring.** This RFC wires interactive **fish**
  only, because that is the shell the live snippet targets and the shell Atlas
  manages (`development/fish`). Other shells are future work.
- **No `PATH` ownership.** The snippet's `fish_add_path -gp $HOME/.local/bin` is
  part of the wiring (Starship must be findable), but Atlas does not otherwise
  manage the user's `PATH`, `config.fish`, functions, or completions.
- **No activation inside `install`.** Installing ships the prompt config;
  activation is a separate, later, opt-in step.
- **No re-assertion of taste.** If the user deletes or edits the snippet after
  activation, Atlas reports and steps back (refuse-to-clobber + disown); it does
  not silently re-wire.
- **No general-purpose file-escrow engine.** The backup mechanism (§5.2) is scoped
  to exactly one path Atlas owns for exactly one purpose (its own reversal); it is
  not offered as a reusable primitive for arbitrary user files.

## 4. Engine changes

**None.** RFC-0029 already added the `activate` / `deactivate` verbs, mapped them
to the `activate` / `deactivate` hooks in `_runner_hooks_for_verb`, added them to
the `atlas` verb `case`, added explicit `__SKIP__` accounting so a module without
the hook is counted *skipped* (not *ok*), and added the `usage()` lines. A module
that implements `module::activate` / `module::deactivate` is picked up by that
machinery automatically. This RFC adds those two hooks to
`modules/development/starship/module.sh` and nothing else. No change to the
runner, the CLI entrypoint, or any other module.

## 5. Activation contract for `development/starship`

### 5.1 Prerequisites (what `activate` requires)

`module::activate` refuses with clear guidance unless **all** hold:

1. **Install marker `installed`.** You cannot wire a config that Atlas has not
   installed. `_starship_marker_load` must report `state=installed` and the Atlas
   config must match source (the module's existing `module::check` semantics).
   The `activated/` lifecycle is separate from the install marker (RFC-0029 §5.2),
   so we read the install marker only as a precondition, never mutate it.
2. **The Starship binary is on `PATH`.** `os::has_cmd starship` must succeed. The
   `development/starship` module does **not** install the binary — its header
   states this, and its only binary interaction is the optional
   `_starship_validate_if_present` health check, which *warns and returns 0* when
   `starship` is absent. Activation cannot be so lenient: a wiring snippet that
   runs `starship init fish` in a shell where `starship` is not found produces a
   per-shell startup error on every new terminal. So activation is **strict** —
   binary absent ⇒ fail with:
   `starship binary not found on PATH; install it (e.g. to ~/.local/bin) before
   activating development/starship`.
   This mirrors `desktop/theme` requiring `plasma-apply-colorscheme` present.
3. **The `development/fish` snippet directory is usable.** The snippet lives under
   `~/.config/fish/conf.d/`; `activate` creates that directory if missing (fish
   itself sources every `*.fish` there). It does not require `development/fish` to
   be installed — a user may run fish without Atlas managing it — but the two
   files never collide (§6).

Why binary-required-not-installed is the right boundary: installing Starship is a
SHA256-verified GitHub binary fetch to `~/.local/bin` in live use — a network,
integrity-verification, and update-lifecycle concern that belongs in a module's
**install** hook, reviewed on its own (its own RFC amendment to RFC-0011), not
smuggled into an activation hook. Keeping `activate` a pure, offline,
filesystem-only switch keeps it reversible and testable. §7 records the rejected
alternative of installing-on-activate.

### 5.2 What is switched, and the recorded prior (record-verbatim)

Unlike the KConfig reference (one key with a string value), the switched state
here is **the content (or absence) of one file** at:

```
$XDG_CONFIG_HOME/fish/conf.d/10-atlas-starship.fish   (default ~/.config/fish/conf.d/10-atlas-starship.fish)
```

The Atlas-owned content Atlas writes is fixed (an exact byte template, §5.3), and
its hash is recorded at activation time (`snippet_sha256`, §5.4). The reversible
**prior** — what was at the path *before Atlas wrote its content there* — is one
of two cases, recorded write-once in the state file:

- **The snippet did not exist** (the pre-Atlas norm on a fresh machine):
  `prior_conf=__ATLAS_ABSENT__`. On `deactivate`, absent ⇒ **delete the Atlas
  snippet**, returning `conf.d` to file-absent.
- **A file already existed at that exact path** (the honest hard case — e.g. the
  live hand-written snippet, whose bytes are *not* identical to Atlas's template).
  Rev 2 does **not** guess by comparing to the template. It **records the prior
  bytes verbatim**:
  - Back up the existing file's exact bytes to a **uniquely-named** sibling under
    `$ATLAS_STATE_DIR` — a `mktemp` file in the backups dir, so a later escrow
    generation can never overwrite an earlier orphan (the B2 fix):
    ```
    $ATLAS_STATE_DIR/activated/backups/development-starship/<mktemp XXXXXX>.prior
    ```
    (mode 600, atomic, in the state tree so it inherits the 600/700 discipline of
    the escrow, not world-readable like the live config).
  - Record in the state file `prior_conf=present`,
    `prior_conf_sha256=<sha256 of the backed-up bytes>`, and
    `backup_ref=<basename of the mktemp backup file>`.
  - On `deactivate`, `prior_conf=present` ⇒ **restore the backed-up bytes** from the
    recorded `backup_ref` (verify it still hashes to `prior_conf_sha256` before
    restoring; write it back atomically with mode 644), then — **after**
    `state=inactive` is written (the B1 ordering fix) — remove the backup file.

Because the strict `key=value` marker parser cannot hold multi-line file content,
the prior file's *content* lives in the sibling backup, and the state file holds
only the sentinel/flag plus the backup's hash. This makes the live hand-written
snippet a **normal case**: its bytes are recorded and later restored verbatim.
There is no byte-identity-with-template test anywhere in the activation path, and
no case in which Atlas deletes divergent user bytes on `deactivate` — it restores
them.

**Why not just refuse on any pre-existing file?** Because the *whole point* on the
live machine is to adopt the existing wiring reversibly. Refusing would force the
user to manually move their file aside, and the RFC-0029 invariant explicitly
covers "a file that did not exist before" **and**, read honestly, a file that
*did* exist before and must return verbatim. Recording-verbatim satisfies the
invariant for both; it never stores foreign bytes *in place of* restoring them and
never silently clobbers.

**What is still refused.** A backup is taken at first activation only, write-once
(§5.5). During a resumed activation, if the on-disk file is neither absent, the
recorded backup, nor the Atlas snippet Atlas already wrote — i.e. some *new*
foreign content appeared in the interruption window — activation **refuses**
rather than overwrite it (§5.5, F2a). And `deactivate` refuses to delete any
on-disk file that is not the Atlas snippet it recorded owning (§5.6, F2b/F3).

### 5.3 The Atlas-owned snippet (exact content + hash ownership check)

`activate` writes exactly this content (an emitter function whose output is
hashed, mirroring `development/fish`'s `_fish_config_content` / `_fish_config_hash`
pattern so the ownership check is a SHA256 comparison, not a fragile text diff):

```fish
# Managed by Atlas: development/starship activation (RFC-0031). Do not edit.
# Reversible: run 'atlas deactivate development/starship' to remove this file.
fish_add_path -gp $HOME/.local/bin
if status is-interactive
    set -gx STARSHIP_CONFIG $HOME/.config/atlas/starship/starship.toml
    starship init fish | source
end
```

Notes on the content, all grounded in the live snippet and the starship module:

- `STARSHIP_CONFIG` points at `$HOME/.config/atlas/starship/starship.toml`, which
  is exactly `_starship_config_file` (`${ATLAS_CONFIG_HOME:-${XDG_CONFIG_HOME:-
  $HOME/.config}/atlas}/starship/starship.toml`) in the default environment. The
  emitter uses the literal `$HOME/.config/atlas/...` form (the live snippet's
  form, evaluated by fish at shell start) rather than baking an absolute path, so
  the file is user-portable and its hash is stable across users. Under a
  non-default `ATLAS_CONFIG_HOME`/`XDG_CONFIG_HOME`, activation additionally
  verifies `_starship_config_file` resolves under `$HOME/.config/atlas/starship/`
  and refuses with guidance otherwise (the literal wiring would not point at the
  managed config) — an honest limitation of a fixed, hashable template.
- `fish_add_path -gp $HOME/.local/bin` ensures Starship (installed to
  `~/.local/bin` in live use) is on `PATH` for the `starship init` call and for
  the user. It is idempotent in fish (`fish_add_path` deduplicates).
- The `status is-interactive` guard means the snippet is inert in
  non-interactive/script fish, so it cannot break scripts or CI shells.

**Ownership check (mode 644, atomic write) — by RECORDED hash, not the template
(F3).** Reusing the `development/fish` discipline but escrow-aware:

- `_starship_act_snippet_content()` emits the bytes above;
  `_starship_act_snippet_hash()` is its `sha256sum`. This is the hash Atlas
  writes *and records* at activation.
- `_starship_act_snippet_matches_recorded()` returns true iff the on-disk file is
  a regular (non-symlink) file whose hash equals **the `snippet_sha256` recorded
  in the state file** (§5.4) — *not* the current in-code template hash. This is
  the F3 fix: if a future Atlas release edits the template, an already-activated
  machine's recorded hash still identifies the exact bytes Atlas wrote, so both
  verbs keep working across upgrades.
- Writes go through a `mktemp` in the target dir + `chmod 644` + `mv -f` (atomic
  replace), identical to `_fish_config_write` / `_theme_write_asset`.
- The snippet is world-readable config (644), not 600 — it is shell config fish
  reads, like `00-atlas.fish`. The **state file and the prior backup** (§5.4) are
  600, under the state tree.

### 5.4 Activation state file

Per RFC-0029 §5.2, separate from the install marker:

```
$ATLAS_STATE_DIR/activated/development-starship
  schema=1
  state=activating | active | inactive
  prior_conf=__ATLAS_ABSENT__ | present     # present only while state is activating|active
  prior_conf_sha256=<64-hex>                # present iff prior_conf=present
  backup_ref=<mktemp basename>              # present iff prior_conf=present
  snippet_sha256=<64-hex>                   # present only while state is activating|active

$ATLAS_STATE_DIR/activated/backups/development-starship/<backup_ref>
  # exact prior bytes, mode 600, uniquely named per activation, present iff prior_conf=present
```

- Mode 600, atomic write, strict line parser — the same
  `_theme_act_load` / `_theme_act_write` shape (reject unknown keys, reject
  unknown `state`, require `schema=1`), extended for the new keys.
- **Presence rules the parser enforces (both directions):**
  - `prior_conf`, `snippet_sha256` are present **iff** `state` is `activating` or
    `active`. A clean `inactive` record carries none of them — the escrow is
    consumed. `prior_conf`/`snippet_sha256` under `inactive` ⇒ parse error;
    missing either under `activating`/`active` ⇒ parse error (exactly as the theme
    parser does for `prior_colorscheme`).
  - `prior_conf_sha256` and `backup_ref` are each present **iff**
    `prior_conf=present`. Either under `prior_conf=__ATLAS_ABSENT__` ⇒ parse error;
    either missing when `prior_conf=present` ⇒ parse error.
  - `prior_conf` must be exactly `__ATLAS_ABSENT__` or `present`; any other value
    ⇒ parse error. `prior_conf_sha256` and `snippet_sha256` must each be 64 lower-
    hex (`_starship_hash_valid`); otherwise ⇒ parse error (a corrupted record is
    rejected, not silently restored). `backup_ref` must be a single path component
    (no `/`, not `.`/`..`) naming a file in the backups dir; otherwise ⇒ parse
    error (it is never an attacker-influenced path — it is a name Atlas minted).
- A missing `activated/development-starship` file means "never activated by
  Atlas" — the valid default; deleting it by hand is the supported **disown**
  operation (RFC-0029 §5.5). Because each backup is uniquely named (`backup_ref`),
  a disown leaves an inert, uniquely-named orphan that a later activation can never
  overwrite (the B2 guarantee); the user may delete leftover backups for a full
  reset, but Atlas never needs to and never overwrites one. A backup is only ever
  read via the `backup_ref` of a live `prior_conf=present` record.

### 5.5 `module::activate` (write-once escrow via transitional state)

Mirrors `desktop/theme`'s `module::activate` shape, extended for the file backup:

1. **Preconditions (§5.1):** install marker `installed` (`_starship_marker_load`
   + `module::check`-equivalent config match) else fail; `os::has_cmd starship`
   else fail; managed config path resolves under `~/.config/atlas/starship/` else
   fail. All tool/validate stdout is redirected away so the runner reads only the
   hook's `__SKIP__`/exit status (the RFC-0029 §5.3 discipline).
2. **Load activation state** (`_starship_act_load`). Inspect the on-disk snippet.
3. **If `state=active`:**
   - snippet present **and** its hash equals the recorded `snippet_sha256`
     (`_starship_act_snippet_matches_recorded`, §5.3) ⇒ **no-op** (idempotent
     success). Do not touch `prior_*` or the backup.
   - otherwise (snippet deleted, or edited since activation so it no longer hashes
     to the recorded value) ⇒ **refuse-to-clobber**: report "the Atlas Starship
     snippet was removed or edited since activation; refusing to clobber — delete
     `$ATLAS_STATE_DIR/activated/development-starship` to disown." Do **not** touch
     `prior_*` or the backup.
4. **Otherwise (state is `inactive`, `activating`, or no record)** — the
   transition, possibly resumed after interruption:
   - **Determine/reuse the prior write-once (F1 record-verbatim).** If the record
     already has `prior_conf` (an interrupted `activating`), **reuse it and the
     existing backup unchanged** — never re-read disk to recompute a prior. Only
     if there is no `prior_conf` yet, compute it from disk exactly once:
     - no file at the path ⇒ `prior_conf=__ATLAS_ABSENT__` (no backup, no
       `backup_ref`).
     - a file present (regular, non-symlink) ⇒ **back it up verbatim** to a
       **uniquely-named** `mktemp` file in
       `activated/backups/development-starship/` (mode 600, atomic), and record
       `prior_conf=present`, `prior_conf_sha256=<hash of the backup>`, and
       `backup_ref=<basename of that mktemp file>` (the B2 fix — a fresh generation
       never reuses an earlier backup's name). No content inspection, no template
       comparison — any bytes are recorded. (If the path is a symlink or non-regular
       file, refuse: Atlas will not back up or overwrite a non-regular path.)
   - **Guard the write against an interruption-window foreign file (F2a).** Before
     writing the snippet, re-inspect the on-disk file and require it to be one of:
     absent; OR byte-identical to the recorded backup (`prior_conf_sha256`); OR
     already the Atlas snippet — matching **either** the hash Atlas is about to
     write **or** the recorded `snippet_sha256` (the N1 fix: after a template
     upgrade, Atlas's own previously-written snippet still counts as owned, not
     foreign). If it is **any other content** (something new appeared in the window
     since the prior was recorded), **refuse and stop** — do not `mv -f` over it:
     "the file at `~/.config/fish/conf.d/10-atlas-starship.fish` changed during
     activation and is neither the recorded prior nor the Atlas snippet; refusing to
     overwrite — re-run after moving it aside, or delete
     `$ATLAS_STATE_DIR/activated/development-starship` to disown." This closes the
     Rev 1 unconditional-`mv -f`-on-resume hole.
   - Write `{schema=1, state=activating, prior_conf=…, [prior_conf_sha256=…,
     backup_ref=…,] snippet_sha256=<hash Atlas will write>}` atomically **before**
     writing the snippet. Recording `snippet_sha256` here (not the template) is the
     F3 fix.
   - Write the snippet atomically (mktemp+chmod 644+mv). If it already matches the
     recorded hash, this is a no-op copy.
   - On success, write `{schema=1, state=active, prior_conf=…, [prior_conf_sha256=…,
     backup_ref=…,] snippet_sha256=…}` (same values).
   - Report: "Atlas Starship prompt activated; open a new interactive fish (or
     `source ~/.config/fish/conf.d/10-atlas-starship.fish`) to see it — already-
     open shells are unchanged."

The transitional `activating` state is the write-once guarantee: if the process
dies between recording the prior and reaching `state=active`, the record stays
`activating` with the true `prior_conf`/`prior_conf_sha256`/backup preserved; a
re-run re-enters step 4, sees the existing `prior_conf`, and never recomputes it
or re-reads a possibly-changed disk into the escrow. A failed snippet write is
thus never mistaken for user drift (drift is judged only in step 3 under
`state=active`), and a foreign file appearing mid-window is refused, not
overwritten.

### 5.6 `module::deactivate`

Mirrors `desktop/theme`'s `module::deactivate`, extended for verbatim restore. The
delete/restore is **always guarded by the recorded `snippet_sha256`** (F2b/F3):

1. **Load state.** If no record or `state=inactive` ⇒ nothing to do (success):
   "development/starship is not activated by Atlas."
2. **Inspect the on-disk snippet and establish ownership BEFORE any destructive
   step.** Compute the on-disk hash and compare to the recorded `snippet_sha256`.
   Branch (this applies under **both** `state=active` and `state=activating` — the
   Rev 1 bug was that the guard only ran under `active`):
   - **Snippet absent** and `prior_conf=__ATLAS_ABSENT__` ⇒ **already-restored
     finalize** (interrupted-deactivate: the deletion landed, only the state write
     was lost). Write `state=inactive`, drop `prior_*`/`snippet_sha256`, succeed. No
     clobber. (Under `__ATLAS_ABSENT__` there is no `backup_ref`, so there is no
     backup to remove — Atlas never scans or cleans the backups dir, preserving any
     unrelated orphans per §5.4/B2.)
   - **Snippet absent** and `prior_conf=present` ⇒ the Atlas snippet is gone but a
     prior must be restored. Proceed to step 3 (restore-from-backup); there is no
     on-disk file to guard, so restoring the recorded prior bytes is safe and
     correct.
   - **Snippet present and its hash == recorded `snippet_sha256`** ⇒ Atlas owns
     this file; proceed to step 3.
   - **Snippet present, `prior_conf=present`, and its hash == recorded
     `prior_conf_sha256`** ⇒ **already-restored finalize** (the B1 fix). This is an
     interrupted deactivate: the restore `mv` already landed (the on-disk file *is*
     the recorded prior) but the `state=inactive` write was lost. Do **not** treat
     this as drift. Finalize: write `state=inactive`, drop
     `prior_*`/`backup_ref`/`snippet_sha256`, then remove the backup, succeed. (This
     branch is checked *before* the drift branch below, so a normal
     crash-mid-restore never produces a false drift refusal — the exact Rev 2 hole.)
   - **Snippet present and its hash matches neither `snippet_sha256` nor (when
     `prior_conf=present`) `prior_conf_sha256`** (the user genuinely edited or
     replaced it) ⇒ **refuse-to-clobber**: report "the Starship snippet was edited
     or replaced since activation; refusing to remove it — delete
     `$ATLAS_STATE_DIR/activated/development-starship` to disown" and stop. Atlas
     will **not** `rm` a file it cannot prove it owns. This is the F2b fix: the
     guard is by recorded hash and runs before any delete, in every state.
3. **Restore the recorded prior (verbatim).**
   - `prior_conf=__ATLAS_ABSENT__` ⇒ **delete the Atlas snippet** (`rm -f` the
     exact path — proven Atlas-owned in step 2, or already absent). Then `rmdir`
     the `conf.d` dir only if empty (`rmdir … 2>/dev/null || true`), never touching
     `00-atlas.fish` or other files.
   - `prior_conf=present` ⇒ **restore the backed-up bytes.** Verify the backup named
     by the recorded `backup_ref` (in `activated/backups/development-starship/`)
     still hashes to `prior_conf_sha256`; if it does not (backup tampered/missing),
     report and leave `state` unchanged (do not clear the escrow, do not delete the
     on-disk snippet) — the user must disown. Otherwise write the backup bytes back
     to the path atomically (mktemp+chmod 644+mv). **Do not remove the backup yet**
     (see step 4 ordering).
   - If any restore/delete step fails, report and leave `state` unchanged (do not
     clear the escrow), per RFC-0029 §5.5.
4. **Write `{schema=1, state=inactive}` (no `prior_*`/`backup_ref`/`snippet_sha256`)
   FIRST — escrow consumed — and only THEN remove the backup file** named by
   `backup_ref` (the B1 ordering fix). This ordering makes deactivate resumable: a
   crash after the restore `mv` but before the state write is recovered by step 2's
   already-restored finalize (the backup is still present); a crash after
   `state=inactive` but before backup removal leaves only an inert, uniquely-named
   orphan backup — harmless, and never overwritten by a future activation (B2).
   Report: "Atlas Starship prompt deactivated; new interactive fish shells will use
   your previous prompt — already-open shells are unchanged." (When a prior file was
   restored, add: "your previous `10-atlas-starship.fish` has been restored.")

### 5.7 Live-effect honesty (no DBus apply) and the post-activation failure class

This is the sharpest departure from the RFC-0029 reference. `desktop/theme` can
apply *live* via `plasma-apply-colorscheme`'s DBus path when a Plasma session is
present. **There is no equivalent here.** Fish sources `conf.d/*.fish` only at
shell startup; writing or deleting `10-atlas-starship.fish` changes nothing in an
already-running shell. So:

- `activate` and `deactivate` are **config-time-only**. Their effect is
  deterministic for *new* interactive fish shells and for a shell that explicitly
  `source`s the file, and that is exactly what the messages promise. Neither hook
  claims a live apply.
- There is no session-presence branch (unlike theme's §5.4): the behavior is
  identical headless, over SSH, in CI, or on a live desktop — write/delete/restore
  a file. This actually makes the hook *simpler and more testable* than the theme
  reference, at the cost of no instant visual change.

**Honest failure class after activation (RFC-0024a framing).** Activation checks
`os::has_cmd starship` at activation time (§5.1), but it does **not** own the
binary's continued presence. If, *after* a successful activation, the user
deletes `~/.local/bin/starship` (or removes it from `PATH`), every **new**
interactive fish will run the wired `starship init fish` against a missing binary
and print a per-shell startup error — while `atlas verify development/starship`
still passes, because `verify` is install-health only and the install marker plus
the managed config are both intact (§6). This is precisely RFC-0024a's headline
failure class: *a module reporting healthy for software that cannot actually
function.* Rev 2 does not paper over it:

- The activation success message names the dependency explicitly: "…active in new
  interactive fish; this wiring runs the `starship` binary at shell start — if you
  later remove it from `~/.local/bin`/`PATH`, run `atlas deactivate
  development/starship` (or re-install the binary) to avoid per-shell errors."
- Unlike RFC-0024a (which widened `install`/`verify` to own its runtime plugin),
  this RFC deliberately does **not** make activation own the binary's lifecycle —
  that is the binary-install boundary deferred to a future RFC-0011 amendment
  (§5.1, §7). A future `atlas doctor` extension that inspects `activated/` records
  and warns when a wired binary went missing is the right home for a live health
  signal; it is out of this RFC's scope but named here so the gap is on record,
  not hidden.

## 6. Ownership analysis

- **Atlas owns only what it creates.** `activate` creates the state record, one
  file (`conf.d/10-atlas-starship.fish`, bytes fixed, hash **recorded** at write
  time), and — when a prior file existed — one 600-mode backup under the state
  tree. `deactivate` removes exactly that file (only when it still hashes to the
  recorded `snippet_sha256`) or restores the recorded prior bytes verbatim, and
  nothing else. The user's `config.fish`, functions, completions, aliases, and
  `PATH` entries other than the one `fish_add_path` line are never touched.
- **No collision with `development/fish`.** That module owns
  `conf.d/00-atlas.fish` (a distinct filename, verified in its `module.sh`); this
  activation owns `conf.d/10-atlas-starship.fish`. Different files, different
  markers (`installed/development-fish` vs `activated/development-starship`),
  independent lifecycles. `deactivate` here never reads or writes `00-atlas.fish`.
  The numeric prefixes (`00-` then `10-`) also give a deterministic source order
  if both are present.
- **A fresh Fedora is valid state.** `activate` is never automatic; an
  un-activated machine (snippet absent, no `activated/` record) is fully valid and
  `deactivate` on it is a no-op.
- **The live hand-written machine is a normal case, not a refuse.** Its snippet's
  bytes differ from Atlas's template (verified: live `23b220…` vs template
  `dccf4c…`), so Rev 2 backs them up verbatim, writes the Atlas snippet, and
  restores those exact bytes on `deactivate`. No byte-identity guess, no deletion
  of divergent user bytes.
- **Never destroys divergent user bytes.** A pre-existing file is recorded and
  restored, not clobbered. A *new* foreign file appearing during the activation
  window is refused, not overwritten (§5.5, F2a). An edited/replaced snippet at
  `deactivate` — anything not hashing to the recorded `snippet_sha256` — is
  refused, not removed (§5.6, F2b). The disown path (delete the `activated/`
  record) is the always-available escape, identical to the theme/SSH discipline.
- **Reversible across Atlas upgrades.** Ownership is judged by the
  `snippet_sha256` recorded at activation, not the current in-code template
  (§5.3, F3), so a later template edit does not brick already-activated machines.
- **`verify` is unaffected — with the honest caveat of §5.7.** Activation state
  lives under `activated/`, separate from the install marker; `module::verify`
  (install-health) does not consult it, so activating/deactivating never makes
  `verify` fail — consistent with RFC-0029 §6 and AGENTS.md. §5.7 records the
  RFC-0024a-class hazard that this same separation creates (a removed binary
  leaves `verify` green while new shells error), and states plainly why owning the
  binary's lifecycle is out of scope here.

## 7. Alternatives considered

- **Adopt-iff-byte-identical to the template, treat as absent-prior, delete on
  deactivate (Rev 1's design).** Rejected — and it was the Rev 1 RED. It is (a)
  **false on the real machine**: the live snippet's comment header differs from
  the template, so their hashes differ and the rule would misfire into
  refuse-to-clobber, not adoption; and (b) **destructive even when it did fire**:
  it deleted a file whose bytes it only proved matched *Atlas's own* template, on
  the theory that the file's comment "documents deletion as its undo." Recording
  the prior bytes verbatim (§5.2) is strictly safer and needs no fragile identity
  claim.
- **Store the prior file's bytes inside the state marker.** Rejected — the strict
  `key=value` parser cannot hold multi-line content, and shoehorning file bytes
  into a marker value (escaped, base64'd, whatever) is fragile and unreadable. A
  sibling 600-mode backup file under the same state tree keeps the marker strict
  and the bytes exact.
- **Refuse activation on any pre-existing file at the path.** Rejected for the
  live machine — the entire point is to adopt the existing hand-written wiring
  reversibly. Recording-verbatim lets Atlas own it and hand it back unchanged;
  refusing would force manual file-shuffling and fail the "returns to precisely
  its pre-activation state" invariant for the exact machine this RFC targets.
- **Edit an existing rc file (`config.fish`) instead of a dedicated `conf.d`
  snippet.** Rejected. Editing a user-owned multi-purpose file means Atlas must
  parse, splice, and later un-splice a region inside a file it does not own —
  fragile, and a direct violation of "never silently overwrite user
  configuration." A dedicated `conf.d/*.fish` file is a clean, whole-file
  ownership unit that fish sources natively.
- **Install the Starship binary as part of `activate`.** Rejected for this RFC.
  Fetching a SHA256-verified GitHub binary into `~/.local/bin` is a network +
  integrity + update-lifecycle concern that belongs in a module's **install**
  hook (an amendment to RFC-0011), reviewed on its own security surface. Coupling
  it to `activate` would make an offline, filesystem-only, trivially reversible
  operation suddenly depend on the network and on binary provenance. `activate`
  therefore **requires** the binary present and fails with install guidance —
  the same stance `desktop/theme` takes toward `plasma-apply-colorscheme`.
- **Judge ownership by comparing the on-disk file to the current in-code template
  (Rev 1).** Rejected — a one-byte template edit in a future Atlas release would
  make every already-activated machine's snippet "not match," permanently forcing
  both verbs into the disown branch. Recording `snippet_sha256` at activation
  (§5.3) fixes this.
- **Ship the wiring in `development/fish`'s `00-atlas.fish` install.** Rejected.
  That would make the prompt active at *install* time (not opt-in), couple the
  fish module to the starship module and its binary, and violate RFC-0029's
  install/activation separation.
- **A live-apply via re-`exec`ing the shell.** Rejected. Atlas has no business
  restarting a user's interactive shell; the honest, safe contract is
  config-time-only with a clear message (§5.7).

## 8. Testing strategy

New cases in `tests/test_activation.sh` (or a sibling
`tests/test_activation_starship.sh` following the same harness), mirroring the
existing theme suite: a temp `HOME`, `ATLAS_STATE_DIR`/`XDG_CONFIG_HOME` under it,
`os::has_cmd starship` mocked to return true/false, and the install marker seeded
via `module::install` (with `os::is_fedora`/dnf mocked as the fish/theme tests do).
The snippet path, the `activated/development-starship` file, and the backup sibling
are asserted directly on disk.

1. **Verb plumbing / skip accounting.** `activate`/`deactivate` resolve to the
   right hooks (already covered generically by RFC-0029's engine test); a module
   with the hooks runs and is counted *ok*, not skipped.
2. **Requires installed.** `activate` fails (exit 1) and writes no `activated/`
   record when the starship install marker is not `installed`.
3. **Requires binary.** With `os::has_cmd starship` mocked false, `activate` fails
   with the install-guidance message and writes no snippet and no record.
4. **Records prior (absent) and writes the snippet.** From a clean state,
   `activate` writes `conf.d/10-atlas-starship.fish`, and the record has
   `state=active`, `prior_conf=__ATLAS_ABSENT__`, `snippet_sha256=<hash of the
   written bytes>`, and no backup file. The on-disk snippet hashes to the recorded
   `snippet_sha256`.
5. **Idempotent.** A second `activate` is a byte-for-byte no-op (record unchanged,
   snippet unchanged, still `state=active`).
6. **Real live-snippet backup/restore (F1).** Pre-seed the path with the **actual
   live hand-written bytes** (the exact 373-byte snippet whose sha256 is
   `23b220686fb64f87620020470614a174ddd2e15b60ccb364c19787b48537b696`, comment
   header and all — *not* the template). `activate`: succeeds, records
   `prior_conf=present` + `prior_conf_sha256=<that live hash>`, writes the backup
   sibling containing those exact bytes, and installs the Atlas snippet (hashing to
   the recorded `snippet_sha256`). Then `deactivate`: restores the path to the
   **exact live bytes** (assert byte-for-byte equality and the live sha256), and
   removes the backup. This replaces Rev 1's false "adopts a byte-identical
   pre-existing snippet" test.
7. **Restores exactly (removes the snippet when prior was absent).** From a clean
   activate (prior absent), `deactivate` deletes `10-atlas-starship.fish`, writes
   `state=inactive`, drops `prior_*`/`snippet_sha256`, and leaves any co-present
   `00-atlas.fish` untouched (assert it still exists).
8. **Activate refuse-to-clobber under `state=active` with an edited snippet.**
   After `activate`, overwrite the snippet with different bytes; a second
   `activate` **refuses** (does not touch `prior_*` or the backup), leaves the
   edited file intact, and leaves `state=active` (disown message emitted).
9. **Activate refuse-to-clobber under `state=active` with a removed snippet.**
   After `activate`, delete the snippet; a second `activate` **refuses** (does not
   silently re-write), leaves `state=active`, emits the disown message. (Together
   with test 8, this covers the §5.5 step-3 drift branch in both directions.)
10. **Foreign file during `activating` (F2a).** Seed `state=activating` with
    `prior_conf=__ATLAS_ABSENT__` + `snippet_sha256=<template hash>` and place a
    **new foreign file** (neither absent, nor the recorded backup, nor the Atlas
    snippet) at the path. Re-run `activate`: it **refuses**, leaves the foreign
    file byte-for-byte intact, does **not** `mv -f` over it, and never recomputes
    the prior.
11. **Deactivate under `state=activating` guards the delete (F2b).** Seed
    `state=activating` with `prior_conf=__ATLAS_ABSENT__` +
    `snippet_sha256=<recorded>` and place at the path a file that does **not**
    hash to `snippet_sha256`. `deactivate` **refuses** (no `rm`), leaves the file
    intact, leaves `state` unchanged, emits the disown message.
12. **Template change after activation does not break deactivate (F3).** `activate`
    from clean (records `snippet_sha256` = current template hash, snippet on disk).
    Then simulate an Atlas upgrade by mocking `_starship_act_snippet_content` /
    `_starship_act_snippet_hash` to emit **different** bytes (a template edit),
    without touching the on-disk file. `deactivate` **still succeeds**: it matches
    the on-disk file against the recorded `snippet_sha256` (not the new template),
    deletes the snippet, and finalizes `inactive`. A parallel assertion: a second
    `activate` under the changed template on the same `state=active` record is
    still a correct no-op/idempotent (recorded hash still matches disk).
13. **Interrupted activation is write-once (verbatim prior).** Seed
    `state=activating` + `prior_conf=present` + `prior_conf_sha256=<X>` with the
    backup sibling present and the snippet already written; re-run `activate`: it
    settles to `state=active`, **reuses** the recorded `prior_conf`/backup, never
    re-reads disk into the escrow. Then `deactivate` restores the backed-up bytes
    verbatim.
14. **Interrupted deactivate finalizes (prior absent).** Seed `state=active` +
    `prior_conf=__ATLAS_ABSENT__` + `snippet_sha256=<recorded>` with the snippet
    **already deleted** (restore landed, state write lost); `deactivate` finalizes
    to `state=inactive`, drops `prior_*`/`snippet_sha256`, does not misreport
    drift.
15. **Interrupted deactivate finalizes (prior present) — B1.** Seed `state=active`
    + `prior_conf=present` + `prior_conf_sha256=<P>` + `backup_ref=<B>` with the
    backup present and the on-disk snippet **already replaced by the restored prior
    bytes** (restore `mv` landed, state write lost). `deactivate` must take the
    already-restored finalize branch (on-disk hash == `prior_conf_sha256`, checked
    before the drift branch): it **does not** misreport drift, writes `state=inactive`
    first, then removes the backup, and succeeds. (This is the exact Rev 2 hole:
    under Rev 2 this seed produced a false drift refusal.)
15a. **Interrupted deactivate, crash after state write (prior present) — B1
    ordering.** Seed `state=inactive` (escrow already consumed) but leave an orphan
    backup file present (crash after `state=inactive`, before backup removal). A
    re-run `deactivate` is a no-op (no record semantics: `inactive` ⇒ nothing to
    do), and the orphan backup is inert and untouched — proving the write-state-
    before-remove-backup ordering is resumable and leaks only a harmless orphan.
16. **Refuse on a symlink / non-regular path.** Pre-seed the path as a symlink;
    `activate` refuses (will not back up or overwrite a non-regular path), writes
    no record.
17. **Disown-then-reactivate never destroys the orphan backup — B2.** Activate from
    a real pre-existing file (so `prior_conf=present` with backup `B1` recorded),
    then **disown** (delete the `activated/development-starship` record) — leaving
    `B1` as an orphan and the Atlas snippet on disk. Re-`activate`: it treats the
    module as fresh, backs up the on-disk snippet to a **new, uniquely-named**
    backup `B2` (`mktemp`, `B2 != B1`), records `backup_ref=B2`, writes the snippet,
    `state=active`. Assert **`B1` still exists with its original bytes** (the sole
    copy of the user's true pre-Atlas config is never overwritten — the Rev 2 hole,
    now closed by unique naming). A subsequent `deactivate` restores from `B2`
    verbatim.
18. **Non-default config path guard.** With `ATLAS_CONFIG_HOME` pointing outside
    `~/.config/atlas/starship`, `activate` refuses with the path-mismatch guidance
    and writes nothing.
19. **Strict parser.** The `activated/development-starship` loader rejects:
    `prior_conf` or `snippet_sha256` under `state=inactive`; missing `prior_conf`
    or missing `snippet_sha256` under `active`; `prior_conf_sha256` or `backup_ref`
    present under `prior_conf=__ATLAS_ABSENT__`; missing `prior_conf_sha256` or
    missing `backup_ref` under `prior_conf=present`; an invalid (non-64-hex)
    `prior_conf_sha256` / `snippet_sha256`; a `backup_ref` that is not a single safe
    path component (contains `/`, or is `.`/`..`); an out-of-range `prior_conf`
    value; an unknown key; an unknown `state`; a wrong `schema`.
20. **Deactivate is a no-op before activation** (no record ⇒ exit 0, nothing
    written).
21. Full suite stays green; `atlas install` behavior is unchanged.

## 9. Decision required

1. Accept hosting Starship activation in `development/starship` via
   `module::activate` / `module::deactivate`, with **no engine change** (the
   RFC-0029 verbs, hooks, skip accounting, and state contract are reused as-is).
2. Accept the **binary-required-but-not-installed** boundary (§5.1, §7): `activate`
   requires `starship` on `PATH` and fails with install guidance otherwise;
   installing the binary is deferred to a `development/starship` install-hook
   change (an RFC-0011 amendment), out of scope here.
3. Accept the switched state being **one Atlas-owned fish `conf.d` snippet**
   (`10-atlas-starship.fish`, exact content per §5.3) whose ownership is judged by
   a **recorded `snippet_sha256`** (F3), with the prior recorded **verbatim** —
   either `prior_conf=__ATLAS_ABSENT__` (delete on deactivate) or
   `prior_conf=present` + `prior_conf_sha256` + a 600-mode backup sibling under the
   state tree that `deactivate` restores byte-for-byte (F1). Reuse the RFC-0029
   transitional-`activating` write-once escrow, interrupted-deactivate finalize,
   and disown.
4. Accept the **refuse-never-clobber** guards (F2): a *new* foreign file appearing
   during the activation window is refused, not overwritten (§5.5); an on-disk file
   that does not hash to the recorded `snippet_sha256` is refused, not removed, on
   `deactivate` — in **every** state, guard-before-delete (§5.6).
5. Accept the **config-time-only** live-effect contract (no DBus apply; §5.7) and
   the honest acknowledgement of the RFC-0024a-class post-activation hazard (a
   binary removed after activation leaves `verify` green while new shells error),
   with owning the binary's lifecycle explicitly out of scope here.
