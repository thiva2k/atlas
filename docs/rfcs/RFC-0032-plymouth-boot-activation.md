# RFC-0032: Plymouth boot-splash activation — privileged, reversible default-theme switch

Status: Accepted (Revision 2)

Date: 2026-07-14

Revised: 2026-07-14

Extends: [RFC-0029](RFC-0029-activation-framework.md) (Accepted) · builds on
[RFC-0024](RFC-0024-plymouth-module.md) / [RFC-0024a](RFC-0024a-plymouth-plugin-dependency.md) (Accepted)

## 0. Revision history

- **Rev 1** (Proposed): first draft. Judged **RED** — three contract-level holes,
  all traceable to claims about `plymouth-set-default-theme` that its real source
  does not support:
  1. **Stale-initramfs laundering on the no-rebuild paths.** The real tool writes
     `Theme=` into `plymouthd.conf` *before* it rebuilds the initramfs, so
     `plymouthd.conf` contents are not proof the initramfs was rebuilt. Rev 1's
     interrupted-deactivate finalize wrote `state=inactive` with "no rebuild (prior
     already default)", which could leave the Atlas splash baked into a stale
     initramfs while Atlas reported fully deactivated — the exact RFC-0024a "healthy
     over a non-functional artifact" failure class. §8 test 7 also asserted a
     resumed interrupted-activate "does not re-rebuild," contradicting §5.4's own
     algorithm (which re-runs `-R`).
  2. **Invented absent-prior tool semantics.** Rev 1 built an `__ATLAS_ABSENT__`
     sentinel on the premise that a no-arg `plymouth-set-default-theme` can print
     empty and that `-R -r` "unsets" the default. The real `get_default_theme`
     *never* prints empty (it resolves through `plymouthd.conf` →
     `plymouthd.defaults` → the `default.plymouth` symlink → hardcoded `text`), and
     `-r -R` does not unset — it deletes the `Theme=` line, then resolves the
     fallback and writes it *back*, rebuilding. The sentinel was unimplementable.
  3. **Wrong privilege preflight.** Rev 1 preflighted with `command -v sudo`, which
     *passes* in the exact non-interactive/no-TTY hazard it must catch — so §5.4
     would then write the `activating` record and the `sudo` call would fail
     *afterward*, contradicting §5.3/Decision 3/test 9's claim of refusal *before*
     writing any state.
- **Rev 2** (this): keeps everything the judge validated — no engine change (§4);
  preconditions grounded in RFC-0024a's real `module::check`; the unprivileged
  no-arg prior read; `_plymouth_run_privileged` reuse; write-once `activating`
  escrow; refuse-to-clobber; disown; latency honesty. Fixes the three holes:
  1. **Write-after-apply state rule (§5.2, §5.4, §5.5).** A terminal state (`active`
     or `inactive`) is written **only after the corresponding `-R` rebuild returns
     success**, so a persisted terminal state *is* proof of a matching initramfs.
     Every apply and every restore rebuilds; the interrupted-deactivate finalize no
     longer skips the rebuild. The sole no-rebuild path is idempotent re-activate
     when the state is **already** `active` (its rebuild already completed, proven by
     the persisted `active` state).
  2. **Sentinel removed (§5.2, §5.4, §5.5).** Plymouth *always* has a resolved
     default theme, so `prior_default_theme` is always a concrete name captured from
     the no-arg read, and restore is always `-R <prior_default_theme>`. Documents the
     one honest nuance: if the prior default was only implicitly resolved (no
     explicit `Theme=` line), deactivate pins it explicitly — acceptable and expected.
  3. **Real privilege preflight (§5.3).** Preflight with `os::is_root || sudo -n true
     2>/dev/null` (a non-interactive `sudo` probe) so a cancellable password prompt
     never starts, and refuse cleanly **before** writing any `activating` record when
     privilege is unavailable. §5.3, §5.4, Decision 3, and test 9 are now mutually
     consistent.
  - Adds the stdout-discipline note (RFC-0029 §5.3.1 style): `-R` rebuilds are
    chatty and the runner parses hook stdout for `__SKIP__`, so the hook redirects
    tool stdout away.

## 1. Summary

`desktop/plymouth` (RFC-0024, amended by RFC-0024a) installs a script-based Atlas
boot-splash theme to `/usr/share/plymouth/themes/atlas` and, since RFC-0024a,
installs the `plymouth-plugin-script` runtime dependency the theme needs to render.
It deliberately **does not** make "atlas" the default boot theme, and it does not
rebuild the initramfs — so a stock Fedora KDE box with the module installed still
boots the stock splash (typically the `bgrt` theme, observed in live use). RFC-0024
and RFC-0024a both explicitly pointed activation at RFC-0029/this follow-up.

RFC-0029 §3 deferred plymouth activation on purpose: it is "privileged/boot
(`plymouth-set-default-theme -R`, initramfs) ... materially different from a KConfig
flip." This RFC designs that follow-up, reusing the RFC-0029 activation contract
(two verbs, one optional hook pair, a separate `activated/<category>-<name>` state
file with a write-once escrow) and honoring RFC-0029's invariant:

> Atlas may switch a user-owned setting to its own asset only after recording the
> exact prior value exactly once, and `deactivate` restores that recorded value
> verbatim. A fresh machine, activated then deactivated, returns to precisely its
> pre-Atlas state.

For plymouth the borrowed setting is the **system default plymouth theme name**
(e.g. `bgrt`), captured via `plymouth-set-default-theme` (no args). The Atlas asset
is the `atlas` theme. Applying it is `sudo plymouth-set-default-theme -R atlas`,
where `-R` rebuilds the initramfs so the change takes effect at next boot.
Restoring is `sudo plymouth-set-default-theme -R <prior>`.

Two hazards make this genuinely different from `desktop/theme` and shape the whole
design: **privilege** (both apply and restore need root and a `sudo` password
prompt, so they cannot run non-interactively/headless) and **latency** (every apply
or restore triggers an initramfs rebuild — seconds to minutes; not instant).

**Grounding note (why Rev 2 differs).** The design below is grounded in the *actual*
`/usr/bin/plymouth-set-default-theme` on this Fedora box, not in an assumed
interface. Two facts from its source drive the whole contract:

- **A no-arg read never returns empty.** `get_default_theme` resolves the current
  default through `plymouthd.conf` (`Theme=`), then `plymouthd.defaults`, then the
  `default.plymouth` symlink, and finally a hardcoded `text` — so it *always* prints
  a concrete theme name. There is no "no default set" state for the tool to report,
  and therefore no absent-prior sentinel is possible or needed (§5.2).
- **The tool writes config before it rebuilds.** For `-R <theme>` it validates the
  theme, writes `Theme=<theme>` into `plymouthd.conf`, and *then* runs
  `plymouth-update-initrd`. `plymouthd.conf` is written whether or not the rebuild
  later succeeds, so its contents are **not** proof that the initramfs matches. Only
  a completed `-R` proves the initramfs matches. This is the fact that forces the
  write-after-apply state rule (§5.2).

## 2. Goals

- Boot-splash activation is **explicit and opt-in** — never part of `atlas install`
  (RFC-0024/0024a keep install limited to shipping the theme + plugin).
- Activation is **exactly reversible** — `deactivate` restores the recorded prior
  default theme verbatim; a user-changed default is reported, never silently
  clobbered.
- Activation is **idempotent and rebuild-frugal where it is honest to be** —
  re-activating an already-`active` module is a no-op that does **not** rebuild the
  initramfs (its rebuild already completed and is proven by the persisted `active`
  state); an interrupted apply resumes without corrupting the recorded prior, and
  re-runs the rebuild before claiming success.
- **A persisted terminal state proves a matching initramfs.** `active` is written
  only after `-R atlas` succeeds; `inactive` only after `-R <prior>` succeeds. Atlas
  never reports a terminal state over a stale initramfs.
- **Honest about privilege and latency** — the hook refuses cleanly, before writing
  any state, when it cannot obtain root non-interactively; it tells the user the
  initramfs rebuild is slow; it does not pretend a non-interactive/headless run can
  rebuild the initramfs.
- Reuses the RFC-0029 contract unchanged (no engine change; §4).

## 3. Non-goals

- **No engine change.** The `activate`/`deactivate` verbs, their hook mapping, the
  skip-accounting fix, and the stdout-discipline convention all landed with RFC-0029
  (§4).
- **No ownership of plymouth, the kernel cmdline, or the initramfs tooling.** Atlas
  owns the `atlas` theme it ships (RFC-0024) and the *default-theme selection
  transition* (this RFC). It does not own `plymouth`, `dracut`/the initramfs
  generator, or boot configuration. `deactivate` restores the user's prior default
  theme; it does **not** delete the atlas theme files — that is `module::remove()`
  (RFC-0024).
- **No removal of the atlas theme on deactivate.** Install lifecycle (theme files +
  plugin) and activation lifecycle (default-theme selection) stay independent, per
  RFC-0029's separate `activated/` directory.
- **No `--force`/no-prompt privilege escalation.** Atlas will not attempt to bypass
  the `sudo` password prompt; a run that cannot obtain privilege non-interactively
  fails cleanly before touching state.
- **No unattended activation of the boot splash.** Because apply/restore need
  `sudo` and a slow rebuild, this hook is never wired into any automatic or
  scheduled path.
- **No deferred / config-only ("set now, rebuild later") path.** `-R` is the atomic
  unit; setting `Theme=` without a rebuild leaves a stale initramfs. This is
  rejected as a hazard, not a feature (§7).

## 4. Engine changes

**None.** RFC-0029 §4 already added:

- `activate)`/`deactivate)` to `_runner_hooks_for_verb` (each maps to a single
  same-named optional hook);
- the `activate`/`deactivate` verb case in the `atlas` CLI entrypoint;
- the explicit skip-accounting (`__SKIP__`) for modules lacking the hook, so
  `atlas activate` over all modules reports non-look modules as *skipped*, the
  module that ran as *ok*, and a failing hook as *failed*;
- the `usage()` lines for the two verbs.

`desktop/plymouth` gains `module::activate`/`module::deactivate` hooks; because it
now defines them, the runner runs them for those verbs and skips it for no other
verb. Nothing else in the engine changes.

**Stdout discipline (RFC-0029 §5.3.1).** The runner parses each hook's stdout for
the `__SKIP__` token to distinguish "genuinely skipped" from "ran ok." A `-R`
rebuild (`plymouth-set-default-theme -R …` → `plymouth-update-initrd`) is chatty and
prints progress to stdout. If that leaked into the hook's stdout it could be
mis-parsed and would pollute the runner's ledger. Therefore **every privileged tool
invocation in these hooks redirects tool stdout away** (e.g.
`_plymouth_run_privileged plymouth-set-default-theme -R atlas >/dev/null` — stderr
is preserved for genuine error text, exactly as `desktop/theme`'s hooks redirect
`plasma-apply-colorscheme`). Human-facing progress ("rebuilding the initramfs; this
takes seconds to minutes") is emitted via `log::info`, not by leaking tool stdout.

## 5. Activation contract for `desktop/plymouth`

Mirrors the shape and rigor of `desktop/theme`'s reference implementation
(`_theme_act_load`/`_theme_act_write` + the two hooks): a separate mode-600
activation marker, an atomic write (`mktemp` in-dir + `mv -f`), and a strict line
parser that rejects unknown keys and states. It differs from `desktop/theme` where
plymouth genuinely differs — **privilege** and the **initramfs rebuild** — and
because plymouth always has a resolved default, it has **no absent-key sentinel**.

### 5.1 The two hooks

- `module::activate` — record the current system default plymouth theme name
  **exactly once**, then make `atlas` the default and rebuild the initramfs. On
  rebuild success, write the terminal `active` state. Idempotent (§5.4),
  interruption-safe (§5.4), privilege-aware (§5.3).
- `module::deactivate` — restore the recorded prior default theme **and rebuild**,
  then write the terminal `inactive` state; or, if the restore already landed but the
  state write was lost, re-run the restore rebuild to prove the initramfs before
  writing `inactive`. If the current default is **not** `atlas` under an `active`
  record (the user changed it out from under Atlas), report and refuse — with a
  disown escape (§5.6).

### 5.2 Activation state

Reuses the RFC-0029 `activated/` schema, one key:

```
$ATLAS_STATE_DIR/activated/desktop-plymouth
  schema=1
  state=activating | active | inactive
  prior_default_theme=<recorded theme name>   # present iff state is activating|active
```

- Mode 600, atomic write, strict parser — same rigor as
  `_theme_act_load`/`_theme_act_write`: reject unknown keys, reject unknown `state`
  values, require `prior_default_theme` present **and non-empty** iff `state` is
  `activating|active`, reject it under `inactive`.
- **The recorded prior is the default theme *name*, always concrete.** It is
  captured with `plymouth-set-default-theme` (no args), which — per the real tool's
  `get_default_theme` — resolves `plymouthd.conf` → `plymouthd.defaults` → the
  `default.plymouth` symlink → hardcoded `text`, and therefore **always prints a
  concrete name** (e.g. `bgrt`). This read needs **no** privilege and **no** rebuild.
  Recording a name (not the theme's files) matches ownership: Atlas restores *which
  theme is selected*, not the bytes of a theme it does not own.
- **No absent-prior sentinel.** Because the no-arg read is never empty, there is no
  "no default set" state to represent; `prior_default_theme` is *always* a real theme
  name, and restore is *always* `-R <prior_default_theme>`. (Rev 1's
  `__ATLAS_ABSENT__` + `-R -r` path is removed — the real `-r -R` does not unset a
  default; it deletes the `Theme=` line and then resolves and writes the fallback
  back, which is not "restore verbatim.")
- **Honest nuance — deactivate may pin an implicit default explicitly.** If the prior
  default was only *implicitly* resolved (e.g. via `plymouthd.defaults` or the
  `default.plymouth` symlink, with no explicit `Theme=` line in `plymouthd.conf`),
  then `deactivate`'s `-R <prior>` writes `Theme=<prior>` explicitly into
  `plymouthd.conf`. The *effective* default theme is identical to the pre-Atlas
  state — the machine boots exactly the splash it booted before — but the mechanism
  is now an explicit line rather than an implicit resolution. This is **acceptable
  and expected**: the tool offers no way to reconstruct "which layer resolved the
  default," Atlas restores the observable value verbatim, and an explicit
  `Theme=<same-name>` is the honest, minimal representation of that value.
- **Write-after-apply invariant (the core Rev 2 fix).** A **terminal** state
  (`active` or `inactive`) is written **only after the corresponding `-R` rebuild
  returns success**. Consequently a persisted terminal state is *proof* that the
  initramfs matches it: `active` ⇒ the initramfs boots `atlas`; `inactive` ⇒ the
  initramfs boots `prior_default_theme`. The **transitional** `activating` state
  carries the true prior across an interrupted apply and makes **no** claim about the
  initramfs. This is what closes the stale-initramfs laundering hole: Atlas never
  writes a terminal state over an un-rebuilt initramfs.
- A missing `activated/desktop-plymouth` file means "never activated by Atlas" — the
  valid default. Deleting it by hand is the supported **disown** operation (§5.6).

### 5.3 Privilege (the real hazard)

Both apply (`plymouth-set-default-theme -R atlas`) and restore
(`plymouth-set-default-theme -R <prior>`) require **root** — the real tool exits with
"This program must be run as root" for any mutating invocation. The module already
ships `_plymouth_run_privileged` — `if os::is_root; then "$@"; else sudo "$@"; fi` —
and this RFC reuses it verbatim for the privileged calls.

The honest constraint (parallel to RFC-0029 §5.4's degraded-path honesty): when not
already root, `sudo` needs a **TTY password prompt**. A non-interactive or headless
run (SSH without a TTY, CI, a hook invoked from a non-interactive context) cannot
satisfy that prompt and therefore **cannot rebuild the initramfs**.

**Decision — refuse cleanly, before touching state, rather than half-activate.**
`module::activate` does **not** record the prior and write config while deferring the
rebuild. Reasons:

1. A deferred rebuild would leave the system where Atlas's marker claims
   `active`/`activating` but the boot splash has not actually changed and *cannot*
   change until someone rebuilds the initramfs by hand — exactly the "reports
   healthy for something that does not work" failure class RFC-0024a was written to
   kill.
2. Unlike `plasma-apply-colorscheme` (which cleanly writes config now / applies at
   next login without any privileged, slow, all-or-nothing step),
   `plymouth-set-default-theme -R` *is* the atomic unit — and, per the real tool, a
   bare `plymouth-set-default-theme <theme>` still writes `Theme=` into
   `plymouthd.conf` but skips `plymouth-update-initrd`, leaving a stale initramfs
   whose boot splash is unchanged. There is no clean "config now, effect later"
   split to lean on.
3. Recording the prior is cheap and privilege-free, but recording it and then failing
   the rebuild would still consume the escrow's transition — needless risk for a
   hook that provably cannot complete.

**The preflight (Rev 2 fix).** Rev 1 used `command -v sudo`, which *passes* precisely
in the no-TTY hazard it was meant to catch. Rev 2 preflights with an **actual
non-interactive privilege check**:

```
os::is_root || sudo -n true 2>/dev/null
```

`sudo -n` (`--non-interactive`) never prompts: it succeeds if privilege is available
without a password (already root, or a valid cached/NOPASSWD credential) and fails
immediately otherwise. Two consequences, both required for correctness:

- If the preflight **fails**, `module::activate` fails **before writing any
  `activating` record** — no state is touched — with guidance:

  ```
  plymouth activation requires root to rebuild the initramfs
  (plymouth-set-default-theme -R). Re-run with sudo available and a terminal, e.g.:
    sudo atlas activate desktop/plymouth
  This step rebuilds the initramfs and takes seconds to minutes.
  ```

  This is the honest, refuse-before-state contract that Decision 3 and test 9
  depend on.
- Because the probe is **non-interactive, a cancellable password prompt never
  starts.** This is deliberately option (a) of the two honest choices for the
  "sudo password cancelled" case: rather than letting an interactive prompt begin
  (which the user could cancel *after* Atlas had already written the `activating`
  record), Atlas never starts a prompt it cannot complete atomically. The
  refuse-before-state guarantee therefore holds for *every* no-privilege case —
  no-TTY, no-sudo, and would-have-been-cancelled alike. (An outright-absent `sudo`
  on a non-root run makes `sudo -n true` fail, which is the same clean refusal — the
  same discipline `desktop/theme` uses for an absent apply tool.)

If a real interactive `sudo atlas activate …` is run with a terminal, `sudo -n true`
succeeds against the cached credential (or the user is prompted once, up front, by
the harness) and the subsequent `_plymouth_run_privileged` calls reuse that
credential; no second prompt appears mid-rebuild. Should the actual privileged
rebuild still fail mid-run for a non-privilege reason (e.g. `plymouth-update-initrd`
errors, disk full), the record is left in the recoverable `activating` state (§5.4),
never in a lying `active` state.

### 5.4 `module::activate` — write-once escrow, write-after-apply terminal state

1. **Preconditions.** Require the plymouth install marker to be `installed` (the
   atlas theme files present *and* `plymouth-plugin-script` installed, per RFC-0024a's
   `module::check`); else fail: "run `atlas install desktop/plymouth` before
   activating." Require `plymouth-set-default-theme` present; else fail. **Preflight
   privilege (§5.3) with `os::is_root || sudo -n true` before any state write**; on
   failure, refuse with the sudo-guidance message and write nothing.
2. **Load activation state** (strict parser, §5.2). **Read the current default
   theme** via `plymouth-set-default-theme` (no args, no privilege) — always a
   concrete name.
3. **If `state=active`:**
   - current default == `atlas` → **no-op** (idempotent success). **No rebuild** —
     this is the sole rebuild-frugal path, and it is honest *because* the persisted
     `active` state already proves the initramfs boots `atlas` (§5.2). A second
     `activate` must never re-run `-R` here.
   - current default != `atlas` → **refuse-to-clobber**: the user changed the default
     since activation; report and stop (§5.6). Do **not** touch `prior_*`.
4. **Otherwise** (`inactive`, `activating`, or no record — the transition, or a
   resumed/interrupted one):
   - **Record prior write-once:** if the record already carries
     `prior_default_theme` (a `state=activating` left by an interrupted attempt),
     **reuse it unchanged**. Only if there is none yet, record
     `prior_default_theme=<current default>`. Write `{schema=1, state=activating,
     prior_default_theme=…}` atomically **before** applying.
   - `_plymouth_run_privileged plymouth-set-default-theme -R atlas >/dev/null` (the
     slow initramfs rebuild; stdout redirected per §4). Log up front via `log::info`
     that it may take seconds to minutes.
   - **On rebuild success**, write the terminal `{schema=1, state=active,
     prior_default_theme=…}` (same prior). On rebuild failure, leave the record at
     `activating` and fail.

**Why this re-rebuilds on resume (and why test 7 asserts it does).** A record found
in `state=activating` makes **no** claim about the initramfs — the tool may have
written `Theme=atlas` into `plymouthd.conf` and then died before (or during)
`plymouth-update-initrd`, so the initramfs may still boot the prior splash even
though `plymouthd.conf` reads `atlas`. The persisted `plymouthd.conf` is not proof
(§5.2). Therefore a resume from `activating` **re-runs `-R atlas`** and writes
`state=active` only after that rebuild returns success — the terminal state is earned,
not inherited. The prior is still preserved write-once, so the pre-Atlas default is
never laundered into `atlas`, and a failed apply is never mistaken for user drift
(drift is judged only in step 3, under `state=active`).

### 5.5 `module::deactivate`

1. **Load activation state.** If no record, or `state=inactive` → nothing to do
   (success, no rebuild — `inactive` already proves the initramfs boots the prior).
2. Require `plymouth-set-default-theme` present and **preflight privilege (§5.3) with
   `os::is_root || sudo -n true`**; the restore also rebuilds and needs root. Fail
   cleanly (state unchanged, nothing written) if privilege is unavailable.
3. **Read the current default theme.** If `state=active` and current != `atlas`:
   - **user drift → refuse-to-clobber**: report "the default plymouth theme changed
     since activation (now: `<current>`); not restoring — delete
     `$ATLAS_STATE_DIR/activated/desktop-plymouth` to disown (§5.6)" and stop, state
     unchanged.
   - (Under `state=activating`, current may legitimately not be `atlas` — an
     incomplete activation; deactivate then restores the recorded prior to unwind it,
     rebuilding as below.)

   > **No no-rebuild finalize.** Rev 1 had an "already-restored finalize" branch that,
   > when `current == prior`, wrote `state=inactive` **without** rebuilding, on the
   > theory that "the prior is already the default." That is unsound: the real tool
   > writes `plymouthd.conf` before rebuilding, so `current == prior` (a
   > `plymouthd.conf` read) does **not** prove the initramfs was rebuilt to the prior
   > — the Atlas splash could still be baked into a stale initramfs while Atlas
   > declares itself deactivated. Rev 2 removes that branch. When the recorded prior
   > and the current config already agree, deactivate still runs `-R <prior>` (step
   > 4) to *earn* the `inactive` terminal state; a redundant rebuild is a cheap,
   > honest price for the write-after-apply guarantee.
4. **Restore the recorded prior** (the slow rebuild):
   - `_plymouth_run_privileged plymouth-set-default-theme -R <prior_default_theme>
     >/dev/null` (always a concrete name; no reset form, no sentinel — §5.2). Log via
     `log::info` that it rebuilds and is slow.
   - If the restore fails for any reason (the recorded prior theme no longer exists
     on disk — the real tool exits "does not exist"; the rebuild errored; `sudo`
     unavailable), report clearly and stop **without** clearing state (§5.6) — never
     leave the user on a half-restored boot splash silently, and never launder the
     escrow away.
5. **On rebuild success**, write the terminal `{schema=1, state=inactive}` with
   **no** `prior_*` — the escrow is consumed, and `inactive` now proves the initramfs
   boots the prior. The record documents "Atlas activated this once and has since
   stepped back." The atlas theme files remain installed (removal is
   `module::remove`).

### 5.6 Disown and the prior-deleted case

Refuse-to-clobber and a failed restore must not be dead ends (mirrors RFC-0029 §5.5
and `core/ssh`'s manifest-line disown):

- **Disown:** deleting `$ATLAS_STATE_DIR/activated/desktop-plymouth` clears
  activation state entirely; Atlas then treats the module as never-activated, and a
  fresh `activate` records the *current* default as the new prior. This is the
  supported way out when the user has deliberately taken ownership of the boot splash
  after a refuse-to-clobber. Disowning does **not** touch the theme files or the
  initramfs — the user keeps whatever default they chose.
- **Prior theme deleted:** if the recorded prior theme no longer exists at
  `deactivate` time, `plymouth-set-default-theme -R <prior>` fails ("… does not
  exist"); Atlas reports it and leaves `state` unchanged (not silently cleared),
  telling the user to pick a default theme with
  `sudo plymouth-set-default-theme -R <theme>` and then disown. No data is lost — the
  record still names the intended prior.

## 6. Ownership analysis (why this is philosophy-safe)

- **Atlas owns only what it creates.** It creates the activation *record* and drives
  the *transition* (default-theme selection + the write-once escrow). The system's
  default-theme selection is borrowed, its prior name held write-once, and returned
  verbatim on `deactivate` — including explicitly pinning a previously-implicit
  default to the *same* name (§5.2), which preserves the observable value.
- **A fresh Fedora is valid state.** `activate` is never automatic; an un-activated
  box boots its stock `bgrt` splash and is fully valid. `deactivate` on it is a
  no-op with no rebuild.
- **Atlas does not own plymouth, the kernel cmdline, or the initramfs.** It invokes
  `plymouth-set-default-theme -R` (a plymouth-provided tool) to select *its own*
  theme and to restore the *user's* prior; it never edits boot config or the
  initramfs generator directly.
- **A terminal state never lies about the initramfs.** The write-after-apply rule
  (§5.2) means `active`/`inactive` are written only after the matching `-R` returns
  success — the same discipline that motivated RFC-0024a, now applied to activation.
- **Install and activation lifecycles stay independent.** `deactivate` restores the
  prior default but leaves `/usr/share/plymouth/themes/atlas` in place; only
  `module::remove` (RFC-0024) detaches the theme files. `verify` (the install-health
  hook) is unaffected by activation state.
- **Never silently overwrite a user choice.** Refuse-to-clobber + the disown path
  mean Atlas never overwrites a default it no longer owns, and the user is never
  stuck — the same discipline as the theme/SSH drift guards.

## 7. Alternatives considered

- **Activation inside `install`** (`plymouth-set-default-theme -R atlas` during
  `module::install`, or an `ATLAS_ACTIVATE=1 atlas install`). Rejected: it couples a
  privileged, slow, hard-to-reverse boot change to install, contradicts RFC-0024's
  scope, and muddies reversibility. RFC-0024/0024a explicitly kept the default-theme
  selection out of install and pointed it here.
- **Record-and-defer the rebuild** (write config + escrow now, rebuild later). The
  plymouth analogue of `desktop/theme`'s "applies next login" degraded path. Rejected
  (§5.3): `-R` *is* the atomic unit, and per the real tool a bare
  `plymouth-set-default-theme <theme>` writes `Theme=` but leaves a stale initramfs so
  the splash does not actually change; a marker reading `active` over that is exactly
  the "healthy but non-functional" failure RFC-0024a fixed. Refusing cleanly when
  privilege is unavailable is the honest choice.
- **A no-rebuild "already-restored finalize" on deactivate** (Rev 1's design). This
  is the specific hole the judge caught: because the tool writes `plymouthd.conf`
  before rebuilding, `current == prior` in `plymouthd.conf` does not prove the
  initramfs was rebuilt, so writing `inactive` without a rebuild could declare Atlas
  deactivated while a stale initramfs still boots the Atlas splash. Removed; §5.5
  always re-runs `-R <prior>` to earn `inactive`.
- **An `__ATLAS_ABSENT__` sentinel + `-R -r` reset for an "absent" prior** (Rev 1's
  design). Rejected as unimplementable against the real tool (§5.2): the no-arg read
  never returns empty (it falls back through `plymouthd.defaults`, the symlink, and
  finally `text`), and `-r -R` does not unset — it deletes the `Theme=` line and then
  resolves and writes the fallback back. There is no "absent default" for plymouth to
  represent, so the prior is always a concrete name and restore is always
  `-R <prior>`.
- **A `--no-rebuild` batch mode** (set the theme now, one rebuild later). Rejected as
  a default and out of scope: it produces exactly the stale-initramfs / lying-marker
  hazard above. If a genuine batch-multiple-boot-settings-then-one-rebuild
  optimization is ever wanted, it belongs in a future aggregate-activation RFC
  (`desktop/look`), and must still leave the marker `activating` until a rebuild
  lands so no marker ever claims a terminal state over an un-rebuilt initramfs.
- **Restoring theme files instead of a name.** Rejected: Atlas does not own the prior
  theme's bytes; recording and reselecting the *name* is the minimal, correct,
  ownership-safe escrow.

## 8. Testing strategy

New `tests/test_activation_plymouth.sh`, mirroring `tests/test_activation.sh`'s
style: mock `plymouth-set-default-theme`, `sudo`, and `os::is_root` as shell
functions backed by temp files, so the whole matrix runs without root or a real
initramfs. The mock must model the **real tool's write order** — it writes the config
value first, then (only if `-R` is passed) touches a rebuild sentinel — so tests can
assert the write-after-apply invariant, not just the final config value.

```
# Two separate files model the real split the judge grounded findings in:
#   CONF  = what plymouthd.conf would say (written by the tool BEFORE any rebuild)
#   INITRAMFS = what the initramfs actually boots (only a completed -R updates it)
CONF="$HOME/plymouth-conf"; printf bgrt > "$CONF"
INITRAMFS="$HOME/plymouth-initramfs"; printf bgrt > "$INITRAMFS"
REBUILDS="$HOME/rebuild-count"; printf 0 > "$REBUILDS"
plymouth-set-default-theme() {
  # no args  -> print current default (NEVER empty; falls back, never unset)
  # <name>   -> write CONF=<name>            (config only, like the real tool)
  # -R <name>-> write CONF, then INITRAMFS=<name> and bump REBUILDS (rebuild)
  # -R alone -> resolve CONF, write INITRAMFS, bump REBUILDS
  # a mutating call while ROOT_OK!=1 and sudo denied -> exit 1 ("must be root")
  ...
}
os::is_root() { [ "${ROOT_OK:-0}" = 1 ]; }          # flip per-case
sudo() { case "$1" in -n) shift; [ "${SUDO_OK:-0}" = 1 ] && { shift; "$@"; } || return 1 ;; *) [ "${SUDO_OK:-0}" = 1 ] && "$@" || return 1 ;; esac; }
```

Cases (each asserts state-file contents **and** the rebuild count / INITRAMFS value —
never just CONF):

1. **Requires installed / requires tool:** `activate` fails cleanly when the plymouth
   module is not `installed` (marker/plugin), and when `plymouth-set-default-theme` is
   absent; no `activating` record is written; REBUILDS unchanged.
2. **Records prior and applies:** `activate` writes `prior_default_theme=bgrt` +
   `state=active`, INITRAMFS becomes `atlas`, and REBUILDS incremented **exactly once**.
   `state=active` is written *after* the rebuild (assert order via a mock hook that
   fails the rebuild — see case 9b).
3. **Idempotent no-rebuild:** a second `activate` under `state=active` with current
   default `atlas` is a no-op — marker byte-identical, `state=active`, and REBUILDS
   **unchanged**. Guards the sole honest rebuild-frugal path.
4. **Restores exactly, with a rebuild:** `deactivate` reselects `bgrt`, INITRAMFS
   becomes `bgrt`, **REBUILDS incremented** (no no-rebuild shortcut), writes
   `state=inactive`, drops `prior_*`; theme files untouched.
5. **Prior is always a concrete recorded name; restore re-runs `-R` with it:** seed
   any resolved default (e.g. the fallback `text`), `activate` records
   `prior_default_theme=text` (never a sentinel, never empty), applies `atlas`; then
   `deactivate` runs `-R text`, INITRAMFS returns to `text`, REBUILDS incremented.
   (Replaces Rev 1's fictional empty/`-R -r` case; asserts the strict parser rejects
   an empty `prior_default_theme` under `activating|active`.)
6. **Refuse-to-clobber:** with the default changed to something else under
   `state=active`, both `activate` and `deactivate` report, refuse, leave
   `prior_default_theme=bgrt` and the current default untouched, and REBUILDS
   unchanged.
7. **Interrupted-activate re-rebuilds (write-once + write-after-apply):** seed
   `state=activating`, `prior_default_theme=bgrt`, with CONF=`atlas` but INITRAMFS
   still `bgrt` (tool wrote config then died before the rebuild finished). Re-run
   `activate`: it **reuses** `bgrt` (never launders it to `atlas`), **re-runs
   `-R atlas`** (assert REBUILDS incremented and INITRAMFS becomes `atlas`), and only
   then settles `state=active`. Then `deactivate` restores `bgrt` (rebuild again).
   Asserts the resumed activate *does* rebuild — the correction to Rev 1's contradictory
   test.
8. **Interrupted-deactivate re-rebuilds to earn `inactive`:** seed `state=active`,
   `prior=bgrt`, with CONF=`bgrt` but INITRAMFS still `atlas` (restore's config write
   landed, rebuild/state write lost). `deactivate` runs `-R bgrt` (assert REBUILDS
   incremented, INITRAMFS becomes `bgrt`) and only then writes `inactive`. Asserts
   there is **no** no-rebuild finalize and no drift misreport.
9. **No-privilege refuse-before-state:** `os::is_root`→false and `sudo -n`→fail
   (SUDO_OK=0). `activate` fails **before** writing any `activating` record (assert no
   marker file created) with the sudo-guidance message; `deactivate` on an `active`
   record fails with `state` unchanged and nothing written. REBUILDS untouched in
   both. **9b (mid-run rebuild failure):** privilege OK but the mock `-R` returns
   non-zero — `activate` leaves `state=activating` (not `active`), prior preserved;
   `deactivate` leaves `state=active`, prior preserved. Proves terminal states are
   written only after a successful rebuild.
10. **Prior-theme-deleted on deactivate:** make the mock `-R <prior>` fail ("does not
    exist"); `deactivate` reports and leaves `state=active` + `prior_default_theme=bgrt`
    unchanged (no silent clear, no clobber), REBUILDS unchanged.
11. **Disown:** deleting the marker makes `activate` treat the module as fresh and
    record the *current* default as the new prior.
12. **Strict parser:** rejects `prior_*` under `inactive`, missing/empty `prior_*`
    under `active`/`activating`, and unknown keys — the same malformed-marker guards as
    `tests/test_activation.sh`.
13. Full suite stays green; `atlas install desktop/plymouth` behaviour (RFC-0024/
    0024a) is unchanged; `atlas activate` skip-accounting (RFC-0029 §4) still counts
    non-plymouth modules as *skipped*; hook stdout is clean of rebuild chatter (assert
    the runner's `__SKIP__` parse is unaffected — §4 stdout discipline).

Real-Fedora validation (per AGENTS.md, when applicable) is required for the actual
`sudo plymouth-set-default-theme -R atlas` / restore path and the true initramfs
rebuild — the mocks cover contract logic and the write-after-apply ordering, not the
live boot effect.

## 9. Decision required

1. Accept adding `module::activate`/`module::deactivate` to `desktop/plymouth` under
   the **existing** RFC-0029 activation contract, with **no engine change** (§4),
   honoring the RFC-0029 §5.3.1 stdout discipline for the chatty `-R` rebuilds.
2. Accept the state contract: `activated/desktop-plymouth` with `prior_default_theme`
   (**always a concrete theme name — no sentinel**), write-once via the transitional
   `activating` state, and the **write-after-apply rule** (a terminal `active`/
   `inactive` is written only after the matching `-R` rebuild succeeds, so a persisted
   terminal state proves the initramfs matches); restore-verbatim, refuse-to-clobber,
   disown (§5). Accept that restoring an implicitly-resolved prior may pin it
   explicitly in `plymouthd.conf` while preserving the observable value (§5.2).
3. Accept the **privilege/latency posture** (§5.3): apply and restore require root and
   rebuild the initramfs; privilege is preflighted **non-interactively**
   (`os::is_root || sudo -n true`) so a run that cannot obtain privilege **refuses
   cleanly before writing any state** and never starts a cancellable prompt; every
   apply and every restore rebuilds; only the idempotent re-activate under an existing
   `active` state does not (its rebuild is already proven).
4. Accept the ownership boundary (§6): Atlas owns the atlas theme and the
   default-theme *transition*, not plymouth, the kernel cmdline, or the initramfs
   tooling; `deactivate` restores the prior default and leaves the theme files in
   place.
