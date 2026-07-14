# RFC-0029: Activation Framework — Atlas-owned, reversible look activation

Status: Accepted (Revision 2)

Date: 2026-07-13

Revised: 2026-07-14

## 0. Revision history

- **Rev 1** (Proposed): first draft. Judged RED — five contract-level holes:
  false skip semantics, a self-contradictory tool requirement, no representation
  for an absent KConfig key, a non-write-once escrow (data-loss), and a
  refuse-to-clobber dead end with no disown path.
- **Rev 2** (this): keeps the architecture (two verbs + optional hook pair +
  separate `activated/` state, theme-only reference scope) and fixes all five:
  §4 adds real engine skip accounting; §5.3 requires the apply tool and drops the
  contradiction; §5.2 adds an absent-key sentinel + delete-on-restore; §5.3 makes
  the escrow write-once via a transitional `activating` state that distinguishes a
  failed apply from user drift; §5.5 adds an explicit disown path and the
  prior-deleted case. Lesser honesty fixes throughout.

## 1. Summary

Atlas's look modules (`desktop/theme`, `icons`, `cursor`, `fonts`, `wallpapers`,
`development/starship`, `desktop/plymouth`) install their assets but deliberately
never *activate* them — every RFC draws the line at "activation is user-owned."
The result: a fully "installed" workstation still shows the stock look until the
user flips each setting by hand (as observed in live use — colors, icons, cursor,
fonts, wallpaper, prompt, and boot splash were all installed but off).

This RFC adds a **reversible, opt-in activation model** so activation becomes
Atlas-owned *without* violating the ownership philosophy. The invariant that makes
this safe:

> **Atlas may switch a user-owned setting to its own asset only after recording
> the exact prior value exactly once, and `deactivate` restores that recorded
> value verbatim. Atlas owns the *transition*, never the user's choice. A fresh
> machine, activated then deactivated, returns to precisely its pre-Atlas state —
> including a setting that did not exist before.**

Scope of *this* RFC: the framework (two verbs, one optional hook pair, an
activation-state contract) plus **one reference implementation**, `desktop/theme`
(the KDE color scheme). The other look modules follow in later RFCs, each reusing
this contract.

## 2. Goals

- Activation is **explicit and opt-in** — never part of `atlas install`.
- Activation is **exactly reversible** — `deactivate` restores the recorded prior
  value (or deletes a key that was absent); a drifted/user-changed active value is
  reported, never silently clobbered.
- Activation is **idempotent** — re-activating an already-active module is a no-op,
  and an *interrupted* activation resumes without corrupting the recorded prior.
- The model is **uniform** across look modules, even though their mechanisms
  differ (KConfig keys, wallpaper, shell wiring, initramfs).

## 3. Non-goals

- **No "activate everything" in this RFC.** A convenience aggregate
  (`desktop/look`) may come later; here each module is activated explicitly.
- **No activation inside `install`.** Installing ships assets; activation is a
  separate, later, opt-in step.
- **starship and plymouth activation are deferred** to their own follow-up RFCs —
  they need privileged/boot (`plymouth-set-default-theme -R`, initramfs) or shell
  wiring + a binary Atlas does not install, which are materially different from a
  KConfig flip and deserve their own designs. This RFC does the KDE-KConfig
  reference only.
- **No ownership of the user's taste.** Atlas does not re-assert activation if the
  user later deactivates or changes it; activation is a one-shot transition the
  user opts into and can reverse.

## 4. Engine changes

Two new verbs, mapped to two new optional hooks (mirroring how `verify`/`update`
map to single hooks):

```
# internal/runner.sh  _runner_hooks_for_verb
activate)   echo "activate"   ;;
deactivate) echo "deactivate" ;;
```

```
# atlas (CLI entrypoint) verb case
install|update|verify|backup|restore|doctor|status|activate|deactivate)
  runner::run "$verb" "$@" ;;
```

**Skip accounting (Rev 2 fix for the false "skipped, not failed" claim).** In the
real runner, a module that merely lacks a hook hits
`module::has_hook "$hook" || { log::debug "no $hook hook"; continue; }`, the loop
ends, the subshell exits 0 with no `__SKIP__` token, and `runner::run` counts it
as **ok** — so `atlas activate` over all ~25 modules would report "25 ok" when one
actually activated. That is wrong. `_runner_run_module` therefore gains an
explicit skip for these two verbs, mirroring the existing `status` skip path:

```
# activate/deactivate: a module with no such hook is genuinely skipped, not "ok"
if { [ "$verb" = "activate" ] || [ "$verb" = "deactivate" ]; } \
     && ! module::has_hook "$hook"; then
  printf '__SKIP__'
  exit 0
fi
```

placed inside the hook loop, before the generic `has_hook || continue`. Because
both verbs map to a single hook, this fully covers them. Now non-look modules are
reported as *skipped*, look modules that ran as *ok*, and a failing hook as
*failed* — the accurate three-way split `runner::run` already prints.

`atlas`'s `usage()` gains `activate <module>` / `deactivate <module>` lines so the
verbs are discoverable. No change to any other verb.

## 5. The activation contract

### 5.1 Optional hooks

- `module::activate` — record the current user value(s) **exactly once**, then
  switch to the Atlas asset. Idempotent and interruption-safe (§5.3). Requires the
  module's own install marker to be `installed` (you cannot activate an asset that
  is not installed) and the module's apply tool to be present; otherwise it fails
  with guidance.
- `module::deactivate` — restore the recorded prior value(s) (or delete a key that
  was absent before), then clear the activation escrow. If the currently-active
  value is **not** the Atlas asset (the user changed it out from under Atlas),
  report and refuse — Atlas will not overwrite a value it no longer owns (§5.5).

### 5.2 Activation state

Separate from the install marker, under a new directory so install and activation
lifecycles stay independent:

```
$ATLAS_STATE_DIR/activated/<category>-<name>
  schema=1
  state=activating | active | inactive
  prior_<key>=<verbatim recorded value>   # present only while activating|active
```

- Mode 600, atomic write (same rigor as install markers: `mktemp` in-dir + `mv -f`,
  strict line parser that rejects unknown keys and unknown `state` values).
- **Absent-key sentinel (Rev 2).** A KConfig key can legitimately not exist
  pre-activation. `prior_<key>=__ATLAS_ABSENT__` records exactly that state —
  the same technique `desktop/kde-profile` already uses
  (`__ATLAS_KDE_PROFILE_ABSENT__` + `kwriteconfig6 --delete`). On restore, the
  sentinel means "delete the key," not "write the literal string."
- **`prior_*` is present only while `state` is `activating` or `active`.** A clean
  `inactive` record (after a completed `deactivate`) carries no `prior_*` — the
  escrow has been consumed. This is what makes recording write-once (§5.3). The
  strict parser enforces this: `prior_colorscheme` under `state=inactive` is a parse
  error, and its absence under `activating`/`active` is a parse error.
- A missing `activated/…` file means "never activated by Atlas" — the valid
  default. Deleting the file by hand is the supported **disown** operation (§5.5).

Honesty note: restore is by scheme *name* via `plasma-apply-colorscheme`. Applying
a scheme rewrites the whole `[Colors:*]` palette in `kdeglobals`; Atlas records and
restores the *selected scheme name*, not every derived color byte. "Verbatim"
refers to the recorded value (the `ColorScheme` name or the absent sentinel), which
is what the user's choice actually is.

### 5.3 Reference implementation: `desktop/theme`

The recorded key is `kdeglobals [General] ColorScheme`; the Atlas asset is the
scheme named `Atlas` (installed by `desktop/theme` as `Atlas.colors`). The apply
tool is `plasma-apply-colorscheme`, which writes config and applies live via DBus
when a Plasma session is present, or just writes config (applies next login) when
not — the tool handles both, so activation does not branch on session presence.

**`module::activate`** — write-once escrow via a transitional state:

1. Require install marker `installed` and the tools `plasma-apply-colorscheme`,
   `kreadconfig6`, and `kwriteconfig6` present; else fail with guidance. (They ship
   with Plasma; a truly absent tool is a real error, not a silent fallback.) All
   apply-tool stdout is redirected away — the runner reads the hook's stdout for the
   `__SKIP__` control token, so a hook must not leak tool chatter there (the same
   discipline `core/ssh` documents for `gh`).
2. Load activation state. Read current `ColorScheme` with the absent sentinel as
   the `kreadconfig6 --default`.
3. If `state=active`:
   - current == `Atlas` → **no-op** (idempotent success).
   - current != `Atlas` → **refuse-to-clobber**: the user changed it since
     activation; report and stop (§5.5). Do **not** touch `prior_*`.
4. Otherwise (state is `inactive`, `activating`, or no record) — this is the
   transition or a resumed/interrupted one:
   - **Record prior write-once:** if the record already has `prior_colorscheme`
     (a `state=activating` left by an interrupted attempt), **reuse it unchanged**.
     Only if there is no `prior_colorscheme` yet, record
     `prior_colorscheme=<current value or __ATLAS_ABSENT__>`. Write
     `{schema=1, state=activating, prior_colorscheme=…}` atomically **before**
     applying.
   - `plasma-apply-colorscheme Atlas`.
   - On success, write `{schema=1, state=active, prior_colorscheme=…}` (same prior).

   The transitional `activating` state is what makes this safe: if apply fails or
   the process dies between recording and `state=active`, the record stays
   `activating` with the **true** prior preserved. A re-run re-enters step 4, sees
   the existing `prior_colorscheme`, and does **not** overwrite it — so the
   original pre-Atlas value is never laundered away, and a failed apply is never
   mistaken for user drift (drift is only judged in step 3, under `state=active`).

**`module::deactivate`**:

1. Load activation state. If no record, or `state=inactive` → nothing to do
   (success).
2. Read current `ColorScheme`. If `state=active` and current != `Atlas`:
   - **already-restored finalize** (Rev 2 fix for interrupted deactivate): if
     current == the recorded prior, the restore already landed and only the state
     write was lost; write `state=inactive`, drop `prior_*`, and succeed. No
     clobber, no data loss.
   - otherwise → **refuse-to-clobber**: report "user changed the scheme since
     activation; not restoring — delete the `activated/` file (§5.5) to disown" and
     stop. (Under `state=activating`, current may legitimately not be `Atlas`;
     deactivate then restores the recorded prior to unwind the incomplete
     activation.)
3. Restore the recorded prior:
   - `prior_colorscheme=__ATLAS_ABSENT__` →
     `kwriteconfig6 --file kdeglobals --group General --key ColorScheme --delete ""`
     (the key did not exist before Atlas; remove it).
   - otherwise → `plasma-apply-colorscheme <prior_colorscheme>`.
   - If that apply/delete fails for any reason (the recorded prior scheme no longer
     exists, the tool errored, etc.), report clearly and stop **without** clearing
     state (§5.5) — do not leave the user on a half-restored setting silently.
4. Write `{schema=1, state=inactive}` with **no** `prior_*` — the escrow is
   consumed; the record now documents "Atlas activated this once and has since
   stepped back."

### 5.4 Session dependency

`plasma-apply-colorscheme` needs a running Plasma/DBus session only to apply
*live*. With the tool present but no live session (TTY, SSH, headless CI), it still
writes the KConfig value and the change applies at next login; `activate` reports
which happened. Recording the prior via `kreadconfig6` never needs a GUI. (Rev 2:
the earlier draft's self-contradiction — "fail if the tool is absent" vs. "works
if the tool is absent" — is resolved: the *tool* is required; only a live *session*
is optional.)

### 5.5 Disown and the prior-deleted case (Rev 2)

Refuse-to-clobber must not be a dead end. Two escape paths, mirroring
`core/ssh`'s documented manifest-line disown:

- **Disown:** deleting `$ATLAS_STATE_DIR/activated/<category>-<name>` clears
  activation state entirely. Atlas then treats the module as never-activated — a
  fresh `activate` records the *current* value as the new prior. This is the
  supported way out when the user has deliberately taken ownership of the setting
  after a refuse-to-clobber. (A future convenience flag `deactivate --disown` may
  wrap this; not in this RFC's scope.)
- **Prior scheme deleted:** if the recorded prior scheme no longer exists at
  `deactivate` time, the apply fails; Atlas reports it and leaves `state` unchanged
  (not silently cleared), telling the user to pick a scheme and disown. No data is
  lost — the record still names the intended prior.

## 6. Ownership analysis (why this is philosophy-safe)

- Atlas still "owns only what it creates": it creates the activation *record* and
  the transition. The user's setting is borrowed, with the prior value held in a
  **write-once** escrow, and returned exactly on `deactivate` — including deletion
  of a key that never existed pre-Atlas.
- "A fresh Fedora is valid state": `activate` is never automatic; an un-activated
  machine is fully valid and `deactivate` on it is a no-op.
- "verify fails only for broken Atlas-owned state": activation state is separate
  from the install marker and does not make `verify` (the install-health hook)
  fail. (Activation state is inspectable via the `activated/` file; a dedicated
  query verb is future work — `atlas status` stays install-focused.)
- The refuse-to-clobber rule plus the documented disown path mean Atlas never
  destroys a user choice it no longer owns, and the user is never stuck — the same
  discipline as the SSH/theme drift guards.

## 7. Alternatives considered

- **Activation-as-a-module (`desktop/look`)** using only existing verbs: one
  module flips every setting. Rejected as the *primitive* because activation
  mechanisms differ sharply per asset (KConfig vs wallpaper vs initramfs vs shell)
  and a single module would centralise unrelated privilege/session concerns. A
  convenience aggregate can still be built later *on top of* per-module activate
  hooks.
- **`ATLAS_ACTIVATE=1 atlas install`**: couples activation to install and muddies
  reversibility. Rejected — activation must be independently opt-in and undoable.
- **Overloading the install marker with activation state** (Rev 2 note): rejected —
  the install marker's strict parser rejects unknown keys, so this would force a
  schema migration, and `remove`/`detached` flows would clobber activation state.
  A separate `activated/` dir keeps the two lifecycles independent.

## 8. Testing strategy

New `tests/test_activation.sh` + `desktop/theme` cases (mock `plasma-apply-*`,
`kreadconfig6`/`kwriteconfig6` as shell functions, per the existing KDE-module
test style):

1. **Verb plumbing / skip accounting:** `activate`/`deactivate` resolve to the
   right hooks; a module with no activate hook emits `__SKIP__` and is counted
   *skipped*, not *ok* (guards the Rev 2 engine fix).
2. **Records prior:** `activate` writes `prior_colorscheme=BreezeDark` and
   `state=active` before/after applying `Atlas`.
3. **Idempotent:** second `activate` is a no-op (still active, prior unchanged).
4. **Restores exactly:** `deactivate` re-applies the recorded `BreezeDark`, writes
   `state=inactive`, and drops `prior_*`.
5. **Refuse-to-clobber:** with the active scheme changed to something else,
   `deactivate` reports and does not overwrite; `activate` reports and does not
   overwrite the recorded prior.
6. **No-session path:** with a live session absent (apply tool present), `activate`
   still records the prior and writes config, and reports "applies on next login."
7. **Requires installed / requires tool:** `activate` fails cleanly when the theme
   asset isn't installed, and when `plasma-apply-colorscheme` is absent.
8. **Absent-key sentinel (Rev 2):** when `ColorScheme` did not exist pre-activation,
   `activate` records `prior_colorscheme=__ATLAS_ABSENT__` and `deactivate`
   *deletes* the key (asserts `kwriteconfig6 --delete`), returning to key-absent.
9. **Interrupted activation is write-once (Rev 2):** seed `state=activating` with
   `prior_colorscheme=BreezeDark`, set current scheme to `Atlas` (apply landed but
   state write didn't). Re-run `activate`: it must **reuse** `BreezeDark`, never
   overwrite it with `Atlas`, and settle `state=active`. Then `deactivate` restores
   `BreezeDark`. (The exact data-loss hole Rev 1 had.)
10. **Prior-deleted on deactivate (Rev 2):** recorded prior scheme no longer exists;
    `deactivate` reports and leaves `state` unchanged (no silent clear, no clobber).
11. **Disown (Rev 2):** deleting the `activated/` file makes `activate` treat the
    module as fresh and record the current value as the new prior.
12. **Interrupted deactivate (Rev 2):** seed `state=active`, `prior=BreezeDark`, and
    set the current scheme to `BreezeDark` (restore landed, state write didn't).
    `deactivate` must finalize to `inactive` (already restored), not misreport drift.
13. Full suite stays green; `atlas install` behaviour is unchanged.

## 9. Decision required

1. Accept the two verbs (`activate`/`deactivate`) + optional hook pair as the
   activation primitive, **with the explicit skip-accounting engine change** (§4),
   vs. the activation-as-a-module alternative (§7).
2. Accept the **write-once** record-prior (transitional `activating` state) /
   restore-verbatim / absent-key-sentinel / refuse-to-clobber-plus-disown
   reversibility contract and the separate `activated/` state dir (§5).
3. Accept scoping this RFC to the framework + `desktop/theme` reference, with
   icons/cursor/fonts/wallpapers/starship/plymouth activation as follow-up RFCs.
