# RFC-0030: KDE look activation — icons, cursor, fonts

Status: Accepted (Revision 2)

Date: 2026-07-14

Revised: 2026-07-14

## 0. Revision history

- **Rev 1** (Proposed): first draft, covering icons, cursor, fonts, and
  wallpapers in one RFC. Judged **RED** by adversarial review — five
  contract-level or factual holes: (a) the fonts restore was a dead end across a
  mid-restore crash — two sequential writes with no transitional state, so a crash
  between them left `state=active` with one key at its prior and one still at
  Atlas's value, and the "both keys must equal prior to finalize / else drift"
  rule then misclassified Atlas's own half-finished restore as *user drift*,
  causing disown to delete the escrow while one key still held Atlas — losing a
  prior; (b) icons invoked `/usr/libexec/plasma-changeicons` by absolute path, so
  a shell-function mock could not shadow it and the tests would run the real
  binary against the dev session (which already happened, corrupting `[Icons]
  Theme`); (c) the icons "restore reports a tool error if the prior package was
  removed" claim was false — `plasma-changeicons` does **not** validate its
  argument and writes it verbatim into `[Icons] Theme`; (d) the cursor design's
  "best-effort live nudge via `qdbus6`" could never fire — `qdbus6` does not exist
  on this Fedora KDE machine; (e) several "verified on this machine … currently X"
  live-value claims the reviewer could not substantiate.
- **Rev 2** (this): **drops wallpapers entirely** — deferred to a future
  **RFC-0033** (§3), because faithful reversible wallpaper capture needs
  desktop-containment discovery, multi-monitor handling, and URL normalization,
  which is a redesign rather than an edit to this contract. Rev 2 now covers
  **only icons, cursor, and fonts**, and fixes the five holes: §5.3 specifies a
  **per-key resumable** fonts deactivate (evaluate each activated key on its own —
  restore if it holds the Atlas value, skip if it already holds its prior, refuse
  before touching either key if it holds a real third value), removing the dead
  end without any schema change; §5.1 requires icons to invoke
  `plasma-changeicons` through a **tool-path indirection variable**
  (`ATLAS_ICONS_CHANGEICONS`) so tests mock it with a temp executable; §5.1 states
  the **honest** `plasma-changeicons` restore semantics (it writes the recorded
  name best-effort, never validates, KDE falls back at render time if the theme's
  package was removed — Atlas still restored the recorded *selection*); §5.2 drops
  the `qdbus6` live nudge and states flatly that a cursor change applies at **next
  login**; and every "verified" claim is now grounded in a read-only check only
  (`kreadconfig6` reads, `ls`, `command -v`), never a mutating probe.

## 1. Summary

RFC-0029 added the reversible, opt-in **activation framework** (`atlas activate` /
`atlas deactivate`, the optional `module::activate` / `module::deactivate` hook
pair, and the separate `$ATLAS_STATE_DIR/activated/<category>-<name>` state file),
and shipped **`desktop/theme`** (the KDE `ColorScheme`) as its one reference
implementation. It explicitly deferred icons, cursor, fonts, and wallpapers to a
follow-up RFC.

This RFC is that follow-up for the three KConfig-key look modules. It adds
`module::activate` / `module::deactivate` to the three remaining KDE *look*
modules that install an asset but never switch to it:

- **`desktop/icons`** — KDE icon theme (installs `papirus-icon-theme`).
- **`desktop/cursor`** — X cursor theme (installs `adwaita-cursor-theme`).
- **`desktop/fonts`** — the general/fixed UI font families (installs Inter + a
  JetBrains Mono Nerd Font).

Wallpapers are **not** in this RFC — see the non-goal in §3.

These three are grouped in one RFC because they **reuse the RFC-0029 contract
verbatim** — same two verbs, same optional hook pair, same `activated/` state file
(`schema=1`, `state=activating|active|inactive`, one or more `prior_<key>=<verbatim>`
lines), same write-once escrow via the transitional `activating` state, same
`__ATLAS_ABSENT__` sentinel + delete-on-restore, same refuse-to-clobber, same
interrupted-activate / interrupted-deactivate finalize, same file-deletion disown.
Nothing in RFC-0029's design is redesigned here.

What *is* per-module — and what this RFC must specify precisely — is the exact
activation **key(s)** and **apply mechanism**, because they differ per asset, and
two of the three carry an honest degradation that RFC-0029's clean `desktop/theme`
case did not have:

- **cursor** has no reliable live-apply tool on this machine, so its change
  applies at **next login** (§5.2);
- **fonts** activates **two** keys and must restore them *independently and
  resumably*, because a crash mid-restore can leave one restored and one not
  (§5.3).

Both are handled with the honest degraded design RFC-0029 set the precedent for
(its §5.2 honesty note, its §5.4 no-live-session path), not papered over.

## 2. Goals

- Bring icons, cursor, and fonts under the **same** reversible, opt-in activation
  model already accepted for `desktop/theme` — no new engine surface, no new state
  schema.
- Specify, per module, the **exact** KConfig key(s) switched, the exact apply
  mechanism, and how the prior is recorded (including the absent-key sentinel) and
  restored verbatim.
- Handle honestly the two cases where the RFC-0029 clean path does not hold: a
  cursor theme change that only applies at next login (no reliable live-apply
  tool), and a two-key fonts restore that must survive a mid-restore crash without
  losing a prior.
- Keep each module independently activatable; no aggregate "activate the whole
  look" here (that stays future work, RFC-0029 §3).

## 3. Non-goals

- **No engine change** (see §4). The verbs, hook mapping, skip accounting, and
  `usage()` lines already shipped with RFC-0029.
- **Wallpaper activation is deferred to a future RFC-0033.** Rev 1 tried to cover
  it here; the adversarial review and re-scoping showed that a *faithful,
  reversible* wallpaper capture is not an edit to the RFC-0029 single-key,
  single-tool contract but a **redesign**. Unlike a color scheme or an icon theme,
  the desktop wallpaper is not stored in one KConfig key: it lives in
  `plasma-org.kde.plasma.desktop-appletsrc` spread across **per-screen containment
  groups**, the active plugin may not be `org.kde.image` at all (slideshow, plain
  color, third-party), and image values are `file://` URLs that need normalization.
  A correct design needs desktop-containment discovery, multi-monitor handling,
  and URL normalization — its own RFC (RFC-0033), not a subsection here. This RFC
  ships the three modules whose prior *is* a single KConfig key and *is* faithfully
  round-trippable today.
- **No `desktop/look` aggregate** and no activation inside `install` — unchanged
  from RFC-0029 §3.
- **No new activation state schema.** The `activated/` file format is reused as-is;
  the only new thing is that `desktop/fonts` writes *two* `prior_<key>` lines, which
  the RFC-0029 schema already permits (`prior_<key>` is defined as repeatable).
- **No ownership of Noto Sans / secondary font roles.** `desktop/fonts` installs
  Inter and a Nerd Font; it only activates the two keys those assets back
  (`[General] font`, `[General] fixed`). It does **not** touch
  `smallestReadableFont`, `toolBarFont`, `menuFont`, or `[WM] activeFont` — those
  are Noto Sans / user-owned on a stock system and Atlas installs no asset for them
  (§5.3). Activating a key for which Atlas ships no asset would be switching a user
  setting to *another user's* value, which the ownership philosophy forbids.
- **No plasmashell restart / logout on the user's behalf.** Where a change only
  takes effect at next login (cursor, and any config write made without a live
  session), Atlas records that fact and reports it; it never forcibly restarts the
  session.

## 4. Engine changes

**None.** This is the load-bearing claim of this RFC.

RFC-0029 §4 already added both verbs to the CLI entrypoint and
`internal/runner.sh`:

```
# internal/runner.sh  _runner_hooks_for_verb  (already present)
activate)   echo "activate"   ;;
deactivate) echo "deactivate" ;;
```

and the `activate|deactivate` cases in the `atlas` verb dispatch, the explicit
`__SKIP__` accounting for a module lacking the hook, and the `usage()` lines. All
of that is live. A module gains activation purely by defining `module::activate` /
`module::deactivate`; the three modules in this RFC do exactly that and change no
shared code. Adding three modules' hooks therefore correctly reports, under
`atlas activate`, the accurate three-way split RFC-0029 §4 describes: modules with
a hook that ran are *ok*, modules without are *skipped*, a failing hook is *failed*.

## 5. Per-module activation contract

All three modules mirror the `desktop/theme` shape from RFC-0029 §5.3: a small
`_<mod>_act_marker` / `_<mod>_act_load` / `_<mod>_act_write` trio (the strict
600-mode line parser that enforces "`prior_*` present iff `state` ∈
{activating, active}"), plus `module::activate` / `module::deactivate` hooks with
the identical control flow:

1. `activate` requires the module's **install marker** to be `installed` and the
   required tool(s) present, else fails with guidance.
2. Load activation state; read current value(s) with `__ATLAS_ABSENT__` as the
   `kreadconfig6 --default`.
3. If `state=active`: current == Atlas asset → idempotent no-op; current != Atlas
   asset → refuse-to-clobber, do not touch `prior_*`.
4. Otherwise (transition / resumed `activating` / `inactive`): reuse an existing
   recorded prior unchanged, else record the current value (or the absent
   sentinel); write `state=activating` **before** applying; apply; write
   `state=active`.
5. `deactivate`: no record / `inactive` → no-op; otherwise restore the recorded
   prior(s) (or delete the key(s) that were absent), evaluating **each activated
   key on its own** so a mid-restore crash is resumable (see §5.3 for the
   two-key case, whose reasoning also grounds the single-key rule); then write
   `state=inactive` dropping `prior_*`; on a failed restore leave `state`
   unchanged and report.

All apply-tool stdout is redirected to `/dev/null` inside the hooks — the runner
reads the hook's stdout for the `__SKIP__` control token, so a hook must not leak
tool chatter there (RFC-0029 §5.3, first bullet). Below, only the parts that
*differ per module* are specified.

### 5.1 `desktop/icons`

- **Recorded key:** `kdeglobals [Icons] Theme`. The Atlas asset value is
  `Papirus-Dark`; the module reads the current value read-only via `kreadconfig6`
  and records it as the prior. (This RFC does not assert a fixed "current live
  value" — the current value is whatever `kreadconfig6` returns at `activate`
  time, recorded verbatim.)
- **Atlas asset / target value:** `Papirus-Dark`. The module installs
  `papirus-icon-theme`, which provides the `Papirus`, `Papirus-Dark`, and
  `Papirus-Light` theme directories under `/usr/share/icons`; Atlas activates the
  dark variant to match the Atlas dark look. The activation constant is
  `_ICONS_SCHEME_NAME="Papirus-Dark"`.
- **Apply tool — via a path-indirection variable (Rev 2, load-bearing for
  testability).** `plasma-changeicons` is **not** on `$PATH` and there is no
  `plasma-apply-icons` binary on this system (verified read-only: `command -v
  plasma-apply-icons` fails; `ls -l /usr/libexec/plasma-changeicons` shows an
  executable at that absolute libexec path). If the module hard-codes the absolute
  path, a shell-function mock cannot shadow it and tests would execute the **real**
  binary — which, run against the dev session, mutates `kdeglobals [Icons] Theme`
  (exactly how this machine's `[Icons] Theme` was once corrupted). The module
  therefore MUST resolve the tool through an overridable variable and invoke it
  **only** via that variable:

  ```sh
  _ICONS_CHANGEICONS="${ATLAS_ICONS_CHANGEICONS:-/usr/libexec/plasma-changeicons}"
  # ...
  [ -x "$_ICONS_CHANGEICONS" ] || { log::error "plasma-changeicons not found at $_ICONS_CHANGEICONS; cannot activate icons"; return 1; }
  "$_ICONS_CHANGEICONS" "$_ICONS_SCHEME_NAME" >/dev/null 2>&1 || { log::error "failed to apply the Atlas icon theme"; return 1; }
  ```

  In production `ATLAS_ICONS_CHANGEICONS` is unset and the default libexec path is
  used; in tests it is set to a temp executable that records its argv (§8). The
  `[ -x "$_ICONS_CHANGEICONS" ]` guard is the module's "required tool present"
  check.
- **Apply behaviour.** `plasma-changeicons <theme>` writes `kdeglobals [Icons]
  Theme` and issues the KDE `reconfigure`/`ThemeChanged` signal so icons update
  live when a Plasma session is present; with no live session it still writes the
  key and the change applies at next login — the same live-or-next-login behaviour
  as `plasma-apply-colorscheme`, so `activate` does not branch on session presence
  for icons.
- **Record prior:** `_icons_read_theme` =
  `kreadconfig6 --file kdeglobals --group Icons --key Theme --default __ATLAS_ABSENT__`.
  Recorded write-once as `prior_icons_theme=<current or __ATLAS_ABSENT__>`.
- **Restore — honest `plasma-changeicons` semantics (Rev 2 correction).** If
  `prior_icons_theme=__ATLAS_ABSENT__`,
  `kwriteconfig6 --file kdeglobals --group Icons --key Theme --delete ""` (the same
  `--delete` idiom `desktop/kde-profile` uses). Otherwise
  `"$_ICONS_CHANGEICONS" <prior>`. `plasma-changeicons` **does not validate** the
  theme name — it accepts an arbitrary string and writes it verbatim into
  `[Icons] Theme` (this is precisely how `Theme=--help` was once written to this
  machine). Restore therefore **always succeeds at writing the recorded prior
  name**; there is no "the tool rejects a missing theme" error path to design for.
  If that theme's *package* was since removed, KDE silently falls back to a default
  icon set at **render** time — Atlas has still faithfully restored the recorded
  *selection* (the name the user had chosen), which is what the escrow holds. This
  mirrors `desktop/theme`'s honesty note (record and restore the recorded *name*,
  not every derived byte); this RFC does **not** invent a tool-error branch that
  the tool's behaviour cannot produce.
- **Refuse-to-clobber:** if `state=active` and the current `[Icons] Theme` is
  neither `Papirus-Dark` (idempotent) nor the recorded prior (finalize), the user
  changed it; report and stop, pointing at the `activated/` file to disown.

Apart from the tool-path indirection and the honest restore semantics above, this
module is structurally identical to `desktop/theme` — only the key name, tool, and
asset value differ.

### 5.2 `desktop/cursor` — applies at next login (honest degradation)

- **Recorded key:** `kcminputrc [Mouse] cursorTheme`. The Atlas asset value is
  `Adwaita`; the current value is read read-only via `kreadconfig6` and recorded
  as the prior. (As with icons, no fixed "current live value" is asserted here.)
- **Atlas asset / target value:** `Adwaita`. The module installs
  `adwaita-cursor-theme`, providing the `Adwaita` cursor directory under
  `/usr/share/icons`. Activation constant `_CURSOR_SCHEME_NAME="Adwaita"`.
- **Apply mechanism — direct KConfig write, applies at next login (Rev 2).**
  Cursor activation does **not** attempt a live nudge. The earlier draft proposed a
  best-effort `qdbus6 org.kde.KWin /KWin reconfigure`, but **`qdbus6` does not
  exist on this Fedora KDE machine** (verified read-only: `command -v qdbus6` and
  `command -v qdbus` both fail), so that nudge could never fire and reporting
  "applied live" would be a distinction the tool cannot substantiate. Cursor
  activation is therefore a plain KConfig write:

  1. record the prior (below);
  2. write the key:
     `kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme Adwaita`.

  The new cursor theme applies at **next login**. `activate` reports exactly that
  ("cursor theme recorded and written; applies at next login") and never claims a
  live apply. The required tools for cursor activation are `kreadconfig6` /
  `kwriteconfig6` **only**; no `plasma-apply-cursortheme`, no `qdbus6`, no
  `busctl`. (A future RFC may add a live refresh if a mechanism can be shown to
  actually reload the cursor theme in a running session — this RFC does not, rather
  than ship an unsubstantiated "applied live" claim.)
- **Record prior:** `_cursor_read_theme` =
  `kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme --default __ATLAS_ABSENT__`,
  recorded write-once as `prior_cursor_theme=<current or __ATLAS_ABSENT__>`.
- **Restore:** `prior_cursor_theme=__ATLAS_ABSENT__` →
  `kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme --delete ""`;
  otherwise `kwriteconfig6 … --key cursorTheme <prior>`. Because restore is a plain
  KConfig write (not a tool that can reject an argument), the write always lands.
  (If the prior cursor *package* was removed, the key still restores to the
  recorded name; KDE falls back to a default cursor at render time — the pre-Atlas
  behaviour that name would have produced. Atlas restores the recorded *choice*,
  per RFC-0029's honesty note, not the rendered pixels.) The restored theme, like
  activation, takes effect at next login.
- **Refuse-to-clobber / finalize:** identical to §5.1, on `[Mouse] cursorTheme`.

### 5.3 `desktop/fonts` — multi-key prior, per-key resumable restore

- **Recorded keys (two):**
  - `kdeglobals [General] font` — the general UI font. Atlas installs the **Inter**
    family, so this key is Atlas-backed; the target descriptor is
    `Inter,10,-1,5,50,0,0,0,0,0`.
  - `kdeglobals [General] fixed` — the fixed-width (monospace) font. Atlas installs
    the **JetBrains Mono Nerd Font**, so this key is Atlas-backed; the target
    descriptor is `JetBrainsMono Nerd Font,10,-1,5,50,0,0,0,0,0`.

  The current value of each key is read read-only via `kreadconfig6` at `activate`
  time and recorded as that key's prior; this RFC does not assert a fixed live value.
- **Why only these two.** `desktop/fonts` installs exactly two families (Inter and
  a JetBrains Mono Nerd Font — see the module's `_FONTS_INTER_PACKAGE` and Nerd Font
  fetch). The other KDE font roles (`smallestReadableFont`, `toolBarFont`,
  `menuFont`, `[WM] activeFont`) are Noto Sans / empty on a stock system — Atlas
  ships **no asset** for them, so switching them would violate "Atlas owns only what
  it creates" (§3 non-goal). This RFC activates precisely the two keys whose target
  value is an Atlas-installed family.
- **Atlas asset / target values.** The full Qt font descriptor for each key. Atlas
  writes `Inter,10,-1,5,50,0,0,0,0,0` for `font` and
  `JetBrainsMono Nerd Font,10,-1,5,50,0,0,0,0,0` for `fixed` — the family name is
  the Atlas-owned part; the size/style suffix uses KDE's standard descriptor at the
  observed default point size. These target descriptors are module constants
  (`_FONTS_ACT_GENERAL`, `_FONTS_ACT_FIXED`) so activate/deactivate compare against
  a fixed expected string.
- **Apply mechanism:** *none.* Font selection is a pure KConfig write — there is no
  `plasma-apply-fonts` equivalent. `activate` writes both keys with
  `kwriteconfig6 --file kdeglobals --group General --key {font,fixed} <descriptor>`.
  The change applies at **next login** (like cursor, and for the same
  `qdbus6`-absent reason, this RFC attempts no live nudge and claims none). The
  required tools are `kreadconfig6` / `kwriteconfig6` only.
- **Record prior — two lines, atomically.** The RFC-0029 state file supports
  multiple `prior_<key>` lines, and this module uses that: it records **both**
  `prior_font_general=<current [General] font or __ATLAS_ABSENT__>` and
  `prior_font_fixed=<current [General] fixed or __ATLAS_ABSENT__>`. Each key gets
  its **own** absent sentinel independently — a machine could have `font` set but
  `fixed` absent, and each must round-trip on its own. The write-once escrow, the
  strict "`prior_*` present iff activating|active" parser rule, and the
  transitional `activating` state all apply to the pair: the `_fonts_act_write`
  helper emits both `prior_font_general` and `prior_font_fixed` (or neither, under
  `inactive`) in one atomic `mktemp`+`mv` file write, so the two priors are never
  half-*recorded*. (Half-*restored* is a separate concern, handled below.)
- **Restore — PER-KEY, resumable (Rev 2, the fix for the Rev 1 dead end).** Rev 1
  restored the two keys as two sequential `kwriteconfig6` writes with no
  transitional state and then judged "both keys must equal their priors to
  finalize, else drift." A crash **between** the two writes left `state=active` with
  one key already at its prior and the other still at Atlas's value; on re-run the
  all-or-nothing drift rule read that mixed state as *user drift* and refused,
  after which disown deleted the escrow while one key still held Atlas — **losing a
  prior**. That is the dead end. Rev 2 removes it with **no schema change** by
  evaluating **each of the two keys independently** at `deactivate` time. Read the
  current value of each key; then, for each key on its own:

  1. **current == that key's Atlas asset descriptor** → this key still holds
     Atlas's value; restore it to that key's recorded prior (or delete it, if the
     recorded prior is `__ATLAS_ABSENT__`).
  2. **current == that key's recorded prior** → this key is **already restored**
     (a prior partial restore landed for it); **skip** it — do not rewrite, do not
     treat it as drift.
  3. **current is anything else** (a real third value the user set) → this is
     genuine drift on this key → **refuse-to-clobber for the whole module BEFORE
     touching EITHER key**, report, and stop, pointing at the `activated/` file to
     disown.

  Because case (2) treats a key already sitting at its prior as *done* rather than
  as *drift*, a half-finished restore is **resumable**: re-running `deactivate`
  finishes restoring whichever key still holds Atlas and leaves the already-restored
  one alone, and neither prior is ever lost. Only case (3) — a value that is neither
  Atlas nor the recorded prior — is drift, and the refusal is evaluated across both
  keys *before* any write, so a mixed Atlas/third-value state never causes a partial
  restore. Only after both keys satisfy case (1)-or-(2) (i.e. both now hold their
  priors or are deleted) does `deactivate` write `state=inactive` dropping `prior_*`.
  If a `kwriteconfig6` write itself fails, `state` is left unchanged and the failure
  reported (RFC-0029 §5.5).
- **Refuse-to-clobber / finalize in `activate` — per key too.** The same per-key
  evaluation applies to `activate`'s drift check under `state=active`. Idempotent
  no-op = **both** keys equal their Atlas descriptors. Finalize-on-re-activate is
  not a fonts concern (activate drives *toward* Atlas), but the drift guard is:
  under `state=active`, if **either** key currently holds a value that is **neither**
  its Atlas descriptor **nor** its recorded prior, that key is user drift → refuse,
  do not touch `prior_*`. A key sitting at its recorded prior (a partially-unwound
  state) is **not** drift under this rule — it is a resumable state, consistent with
  the deactivate logic — so activate re-drives it to Atlas rather than refusing. As
  in §5.1/§5.2, a key equal to its Atlas descriptor is the idempotent case.

## 6. Ownership analysis

Every claim in RFC-0029 §6 carries over unchanged; the additions per module:

- **Atlas owns only the transition, never the taste.** For icons, cursor, and each
  of the two font keys, Atlas records the exact prior in a write-once escrow and
  returns it verbatim on `deactivate` — including deleting a key that was absent
  pre-Atlas (`__ATLAS_ABSENT__` + `kwriteconfig6 --delete`, the
  `desktop/kde-profile` precedent). A fresh Fedora, activated then deactivated,
  returns to precisely its pre-Atlas icon theme / cursor theme / fonts.
- **A fresh Fedora is valid state.** None of these hooks run during `install`;
  `activate` is opt-in and `deactivate` on a never-activated module is a no-op.
- **`verify` is unaffected.** Activation state lives under `activated/`, separate
  from each module's `installed/` marker; none of these hooks change `module::verify`
  (the install-health hook), so an activated-or-not machine both verify clean. This
  matches AGENTS.md: "`verify` fails only when Atlas owns the installation and
  managed state is broken."
- **Refuse-to-clobber + disown everywhere.** All three modules refuse to overwrite
  a value the user changed out from under Atlas and point at the `activated/` file
  for the supported disown (delete-the-file) escape — the RFC-0029 §5.5 contract,
  no new mechanism.
- **The two honest limits are ownership-*preserving*, not ownership-violating.**
  The cursor next-login apply (§5.2) writes only the key Atlas records — Atlas
  touches nothing it does not escrow, and never over-claims a live apply it cannot
  perform. The fonts per-key resumable restore (§5.3) guarantees that a mid-restore
  crash never loses a prior and never partially clobbers, so the two-key escrow is
  as exactly reversible as the single-key one.
- **Fonts multi-key stays within owned assets.** By activating only `[General]
  font` and `[General] fixed` (the two families Atlas installs) and explicitly not
  the Noto-Sans-backed roles (§3, §5.3), Atlas never switches a setting to a value
  it did not create.

## 7. Alternatives considered

- **One RFC per module (three RFCs).** Rejected as needless process overhead: all
  three reuse the RFC-0029 contract with no new primitive; the only per-module
  content is a key name, an apply mechanism, and (for two of them) an honest
  degradation, which fit cleanly in one document's §5 subsections. Splitting would
  duplicate the framework recap three times.
- **Keep wallpapers in this RFC (as Rev 1 did).** Rejected in Rev 2: a faithful
  reversible wallpaper capture needs desktop-containment discovery, multi-monitor
  per-screen handling, and `file://` URL normalization — a redesign of the
  single-key contract, not a §5 subsection. Deferred to RFC-0033 (§3) so this RFC
  ships the three modules that *are* single-key round-trippable today, rather than
  blocking them on the wallpaper design or shipping a dishonest lossy capture.
- **Cursor via `plasma-apply-cursortheme` or a `qdbus6` live nudge.** Rejected
  (§5.2): `qdbus6` is absent on this machine (verified read-only), so a
  `/KWin reconfigure` nudge can never fire, and reporting "applied live" would be
  unsubstantiated. A direct `kcminputrc` write that honestly applies at next login
  is the correct mechanism.
- **Fonts: restore the two keys as two unconditional sequential writes** (Rev 1's
  design). Rejected: a crash between the writes leaves a mixed state that an
  all-or-nothing drift rule misreads as user drift, and disown then deletes the
  escrow while a key still holds Atlas — losing a prior. The per-key resumable
  restore (§5.3) fixes this within the existing schema.
- **Fonts: activate all KDE font roles for a uniform look.** Rejected (§3, §5.3):
  Atlas installs assets only for the general and fixed families; switching
  `menuFont`/`toolBarFont`/etc. would set user keys to Noto Sans, a value Atlas does
  not own — an ownership violation.
- **Overloading the install marker / a new state schema.** Rejected for the same
  reasons as RFC-0029 §7; the `activated/` file and its schema are reused verbatim,
  with fonts simply using the already-permitted repeatable `prior_<key>` lines.

## 8. Testing strategy

Extend `tests/test_activation.sh` (its established style: `set -euo pipefail`, a
throwaway `HOME`, `XDG_DATA_HOME`/`ATLAS_STATE_DIR` under it, `source` the module,
stub `os::is_fedora`, and mock every KDE tool as a shell function so no real Plasma
is required). Add one block per module, mirroring the `desktop/theme` cases.

**Shared mocking pattern (per module).** Back each activated KConfig key with a
file whose presence means "key set" and whose absence means "key absent"; mock
`kreadconfig6` to `cat` it (or echo the `--default`), `kwriteconfig6` to write it
(or `rm` on `--delete`).

- **icons:** mock `kreadconfig6`/`kwriteconfig6` on `[Icons] Theme`. **Do not
  shadow `plasma-changeicons` with a shell function** — the real tool is invoked by
  absolute libexec path, which a function cannot shadow, so the test would run the
  real binary. Instead, create a **temp executable** in `mktemp -d` that records its
  argv (e.g. writes `$1` into the backing key file and appends its args to a log),
  and export `ATLAS_ICONS_CHANGEICONS=<that temp script>` before sourcing/invoking
  the module (§5.1). The absent-tool case sets `ATLAS_ICONS_CHANGEICONS` to a
  non-existent path and asserts `activate` fails the `[ -x … ]` guard cleanly.
- **cursor:** mock `kreadconfig6`/`kwriteconfig6` on `[Mouse] cursorTheme`. **Do
  not** provide `plasma-apply-cursortheme` or `qdbus6` — the whole point is that
  activation depends on neither; assert `activate` still succeeds and reports
  "applies at next login."
- **fonts:** two backing files (`FONT_GENERAL_FILE`, `FONT_FIXED_FILE`); mock
  `kreadconfig6`/`kwriteconfig6` keyed on `--key font` vs `--key fixed`.

**Cases per module** (each asserted against the `activated/` file and the mocked
key state):

1. **Requires installed / requires tool:** `activate` fails cleanly when the module
   is not `installed`; for icons, also when `ATLAS_ICONS_CHANGEICONS` points at a
   non-executable path. For cursor/fonts, `activate` fails when `kwriteconfig6` is
   absent; it must **not** require `plasma-apply-cursortheme`, `qdbus6`, or a fonts
   tool.
2. **Records prior:** `activate` writes the correct `prior_<key>` line(s) and
   `state=active`, and the mocked key(s) now hold the Atlas asset value. For icons,
   assert the temp `plasma-changeicons` mock recorded `Papirus-Dark` as its argv.
3. **Idempotent:** second `activate` is a byte-identical no-op (marker unchanged,
   still `active`).
4. **Restores exactly:** `deactivate` re-writes the recorded prior(s), sets
   `state=inactive`, and drops all `prior_*`.
5. **Absent-key sentinel:** with the key absent pre-activation, `activate` records
   `prior_<key>=__ATLAS_ABSENT__` and `deactivate` **deletes** the key (asserts the
   `--delete` path), returning to key-absent.
6. **Refuse-to-clobber:** with the active value changed to a third value, both
   `activate` and `deactivate` report and do not overwrite; the recorded prior is
   preserved.
7. **Interrupted activate is write-once:** seed `state=activating` with a known
   prior and set the current key to the Atlas value (apply landed, state write
   didn't); re-run `activate` — it must **reuse** the recorded prior, never launder
   it to the Atlas value, and settle `state=active`; then `deactivate` restores the
   seeded prior.
8. **Interrupted deactivate finalizes:** seed `state=active` + prior, set the
   current key to the prior (restore landed, state write didn't); `deactivate`
   finalizes to `inactive` without misreporting drift.
9. **No-live-session path:** for icons, with no session the `plasma-changeicons`
   mock still writes the key and `activate` reports "applies on next login"; for
   cursor/fonts, `activate` always reports "applies at next login" (there is no
   live path to exercise).
10. **Honest restore of a removed prior (icons, Rev 2):** record a prior naming a
    theme whose package is "removed" (the mock just writes whatever name it is
    given); assert `deactivate` **succeeds** at writing the recorded prior name into
    `[Icons] Theme` and sets `state=inactive` — i.e. there is **no** tool-error path;
    Atlas faithfully restored the recorded selection regardless of whether the
    package still exists.

**Module-specific additional cases:**

- **fonts — multi-key prior + per-key resumable restore (the Rev 2 fix):**
  - `activate` records **both** `prior_font_general` and `prior_font_fixed` in one
    marker, and both keys hold their Atlas descriptors after.
  - **independent sentinels:** with `font` set but `fixed` absent pre-activation,
    the marker records `prior_font_general=<value>` and
    `prior_font_fixed=__ATLAS_ABSENT__`; `deactivate` restores the general key and
    **deletes** the fixed key.
  - **one-key-restored crash (the exact Rev 1 data-loss hole):** seed `state=active`
    with both `prior_font_general` and `prior_font_fixed` recorded, then set the
    `font` key to its **recorded prior** (that key's restore landed) and leave the
    `fixed` key at its **Atlas descriptor** (that key's restore didn't). Run
    `deactivate`: it must **finish** — skip the already-restored `font` key (case 2,
    not drift), restore the `fixed` key to its prior (case 1), end `state=inactive`,
    and **lose neither prior**. Assert both keys end at their recorded priors and no
    refuse/drift is reported.
  - **mixed drift refuse (case 3):** with one key at its Atlas value and the other
    changed to a genuine **third** value (neither Atlas nor its prior), `deactivate`
    refuses **before touching either key** (no partial restore) and `activate`
    refuses to re-record over the existing prior; assert neither key was written.
  - **atomicity of recording:** the two `prior_*` lines are always both present
    under `activating`/`active` and both absent under `inactive` (the strict parser
    must reject a marker with only one of them under `active`).

- **cursor — no live-apply dependency:**
  - `activate` succeeds and records the prior **with no `plasma-apply-cursortheme`
    and no `qdbus6` present** (proves neither is a dependency), and reports "applies
    at next login."
  - restore is a plain KConfig write and always lands (no "prior tool rejected the
    argument" failure path).

- **icons — tool-path indirection & honest restore:**
  - the `ATLAS_ICONS_CHANGEICONS` override is honoured: the temp mock is invoked
    (its argv log is non-empty) and the real `/usr/libexec/plasma-changeicons` is
    **never** executed (assert by pointing the override at the mock and checking the
    mock's log).
  - covered by shared case 10 above for the removed-prior honesty.

**Suite-wide:** `activate`/`deactivate` over all modules still produce the correct
skip/ok/failed accounting (the RFC-0029 §4 engine behaviour is unchanged); the full
existing suite stays green; `atlas install` behaviour is untouched.

## 9. Decision required

1. Accept adding `module::activate` / `module::deactivate` to `desktop/icons`,
   `desktop/cursor`, and `desktop/fonts`, reusing the RFC-0029 contract **with no
   engine change** (§4), and **deferring wallpaper activation to RFC-0033** (§3).
2. Accept the per-module activation keys and mechanisms of §5: icons via
   `kdeglobals [Icons] Theme` + `plasma-changeicons` **invoked through the
   `ATLAS_ICONS_CHANGEICONS` path-indirection variable** (§5.1); cursor via a
   direct `kcminputrc [Mouse] cursorTheme` write that **applies at next login**,
   with **no `qdbus6`/`plasma-apply-cursortheme` dependency** (§5.2); fonts via a
   two-key (`[General] font`, `[General] fixed`) multi-`prior_*` KConfig write with
   a **per-key resumable restore**, and no other font role (§5.3).
3. Accept the two **honest degradations**: cursor's next-login apply (§5.2), and
   the honest `plasma-changeicons` restore semantics (it writes the recorded name
   best-effort and never validates; KDE falls back at render time if the package is
   gone — Atlas still restored the recorded selection, §5.1) — versus the rejected
   `qdbus6`-nudge and invented-tool-error alternatives (§7).
