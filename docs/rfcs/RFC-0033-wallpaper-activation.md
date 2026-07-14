# RFC-0033: Wallpaper Activation — Atlas-owned, reversible, per-containment

Status: Accepted

Date: 2026-07-14

Extends: RFC-0029 (Activation framework)

## 0. Revision history

- **Deferred (problem statement)**: split out of RFC-0030 Rev 2 because the
  original attempt was unsound — it hardcoded containment `[1]`, misread a stale
  slideshow group + a panel as "two screens," compared a `file://` URL against a
  plain path (permanent spurious drift), and knowingly activated when the prior was
  unrestorable (deferring the refusal to `deactivate` — a one-way door that breaks
  RFC-0029's record-before-switch invariant).
- **Proposed (this)**: a real design meeting the deferral's §4 requirements —
  containment **discovery** (not a hardcoded id), **per-containment** capture that
  handles multi-monitor, **refuse-at-activate** (never at deactivate) whenever a
  containment's wallpaper is anything other than a single capturable image, and
  **URL normalization** for every comparison. Grounded in the real
  `plasma-org.kde.plasma.desktop-appletsrc` on a live machine.

## 1. Summary

`desktop/wallpapers` installs a *collection* of Atlas SVGs
(`~/.local/share/backgrounds/atlas/{atlas-gradient,atlas-grid,atlas-orbit}.svg`)
and deliberately never changes the user's selection. This RFC adds reversible,
opt-in activation that switches every desktop's wallpaper to the Atlas primary
image (`atlas-gradient.svg`) and restores the exact prior on `deactivate`, reusing
RFC-0029's write-once escrow — extended from one scalar to **one prior per desktop
containment** so a multi-monitor setup round-trips faithfully.

## 2. Goals

- **Explicit, opt-in, exactly reversible.** Each desktop's prior wallpaper image is
  recorded write-once and restored verbatim; a drifted desktop is reported, never
  clobbered.
- **Honest capture boundary.** Activation is refused *up front* if any desktop's
  wallpaper is not a single, capturable `org.kde.image` (e.g. a slideshow, a solid
  colour, or a third-party plugin) — Atlas never switches a setting it cannot put
  back.
- **Multi-monitor faithful.** N desktops with N different wallpapers are captured
  and restored per-containment.

## 3. Non-goals

- No activation inside `install`. No change to what `desktop/wallpapers` installs.
- No support for reversibly activating *over* a slideshow / colour / third-party
  wallpaper plugin — those are refused at activate (§5.3), not half-captured.
- No engine change: RFC-0029 already added `activate`/`deactivate`, the hook
  mapping, `__SKIP__` skip-accounting, and the `usage()` lines.

## 4. What is switched, and the capture model

The wallpaper lives in `plasma-org.kde.plasma.desktop-appletsrc` under, per desktop
containment `C`:

```
[Containments][C]
plugin=org.kde.plasma.folder        # or org.kde.desktopcontainment  (a DESKTOP)
wallpaperplugin=org.kde.image       # the ACTIVE wallpaper plugin
[Containments][C][Wallpaper][org.kde.image][General]
Image=file:///path/to/wallpaper     # the active image (a file:// URL)
```

- **Desktop-containment discovery.** A desktop containment is one whose
  `[Containments][C] plugin` is `org.kde.plasma.folder` **or**
  `org.kde.desktopcontainment`. Panels (`org.kde.panel`) and applet-host
  containments are ignored even though some carry a stray `wallpaperplugin` line.
  Containment ids are session-generated and unstable, so they are **discovered** by
  scanning the appletsrc for `^[Containments][C]$` headers and reading each
  `plugin` — never hardcoded. (kreadconfig6 cannot enumerate groups, so discovery
  reads the ini file directly; all *reads/writes of values* use
  kreadconfig6/kwriteconfig6.)
- **Per-containment capture.** For each discovered desktop containment `C`:
  - read `wallpaperplugin`. If it is **not** `org.kde.image`, **refuse to activate**
    (§5.3) — a slideshow/colour/plugin prior cannot be restored by setting one
    image.
  - read `[…][Wallpaper][org.kde.image][General] Image` with the absent sentinel as
    default. The recorded prior for `C` is this value **verbatim** (including any
    `file://`), or `__ATLAS_ABSENT__` if the key does not exist.
- **URL normalization for comparisons only.** "Is `C` currently the Atlas image?"
  and "is `C` currently its recorded prior?" compare *normalized* forms (strip a
  leading `file://`, then compare filesystem paths). The **recorded** value and the
  **written-back** value are always the verbatim stored form, so restore is exact.

The Atlas primary image is `atlas-gradient.svg`; its stored form is
`file://$(_wallpapers_dir)/atlas-gradient.svg`.

## 5. The activation contract

### 5.1 State file

Per RFC-0029 §5.2, separate from the install marker:

```
$ATLAS_STATE_DIR/activated/desktop-wallpapers
  schema=1
  state=activating | active | inactive
  containments=<space-separated desktop containment ids>   # present iff activating|active
  prior_image_<C>=<verbatim Image value> | __ATLAS_ABSENT__ # one per id in `containments`
```

Mode 600, atomic write, strict parser: reject unknown keys/state/schema; enforce
`containments` present iff state ∈ {activating, active}; require exactly one
`prior_image_<C>` for each `C` listed in `containments` (and none for any other id);
each `<C>` must be a non-negative integer; a `prior_image_*` under `inactive`, or a
missing/extra one under active, is a parse error.

### 5.2 `module::activate` (write-once escrow, transitional state)

1. **Preconditions.** Install marker `installed` (asset present); `kreadconfig6` +
   `kwriteconfig6` present; the appletsrc file exists. Tool stdout is redirected so
   the runner reads only `__SKIP__`/exit.
2. **Discover** the desktop containments (§4). If none are found, refuse with
   guidance (no desktop to activate).
3. **Refuse-at-activate capture check.** For every discovered containment, its
   `wallpaperplugin` must be `org.kde.image`. If any is not, **refuse and stop**
   before writing any state: "desktop <C> uses <plugin>; Atlas can only reversibly
   activate over a single-image wallpaper — switch it to an image first, or leave
   the wallpaper user-owned." (This is the record-before-switch guarantee: Atlas
   never activates when it already knows it cannot restore.)
4. **Load activation state.**
   - If `state=active`: if **every** containment's current image (normalized) is the
     Atlas image → no-op (idempotent). If **any** differs → **refuse-to-clobber**
     ("the wallpaper changed since activation; delete
     `$(…)/activated/desktop-wallpapers` to disown").
   - Otherwise (inactive/activating/none) — the transition, possibly resumed.
5. **Record prior write-once.** If the record already has `containments`/`prior_*`
   (an interrupted `activating`), **reuse them unchanged** — never re-read the
   current wallpapers into the escrow. Only if there is no recorded prior yet,
   capture each containment's current `Image` verbatim (or the absent sentinel) and
   the containment id list, then write `{schema=1, state=activating, containments=…,
   prior_image_<C>=…}` atomically **before** applying.
6. **Apply.** For each discovered containment, `kwriteconfig6` its
   `[…][Wallpaper][org.kde.image][General] Image` to the Atlas image's `file://`
   URL. Best-effort live nudge: if `plasma-apply-wallpaperimage` is present, call it
   with the Atlas image path (applies live to all screens); otherwise the change
   applies at next login. Report which happened. (`wallpaperplugin` is already
   `org.kde.image` for every containment — guaranteed by step 3 — so no plugin
   switch is needed.)
7. On success, write `{schema=1, state=active, containments=…, prior_image_<C>=…}`
   (same recorded priors).

The transitional `activating` state makes recording write-once: a crash between
recording and `state=active` leaves the true priors preserved; a re-run reuses them
(step 5) and never launders the now-Atlas wallpaper into the escrow. Drift is judged
only in step 4 under `state=active`.

### 5.3 `module::deactivate`

1. Load state. If no record or `state=inactive` → nothing to do (success).
2. Require `kwriteconfig6` present. Re-discover is **not** needed — restore targets
   exactly the containments recorded in `containments` (if a recorded containment no
   longer exists, its restore is skipped with a warning; no data is at risk).
3. **Per-containment classification (before any write).** For each recorded `C`,
   read its current image and classify against the Atlas image and its recorded
   prior (all normalized):
   - current == Atlas image → **restore** this containment.
   - current == recorded prior (normalized) → **skip** (already restored).
   - otherwise (a real third value) → **drift**.
   If **any** containment is drift **and** `state=active`, **refuse-to-clobber**
   across the whole set before touching any containment (no partial restore); report
   and stop with the disown instruction.
4. **Restore** each containment classified `restore`: if its recorded prior is
   `__ATLAS_ABSENT__`, `kwriteconfig6 --delete` its `Image` key; else `kwriteconfig6`
   the verbatim recorded prior back. Best-effort live nudge via
   `plasma-apply-wallpaperimage` only when every restored value is the same single
   image and the tool is present; otherwise report "applies at next login."
5. Write `{schema=1, state=inactive}` (no `containments`/`prior_*`) — escrow consumed.

The `current == prior` skip makes an interrupted deactivate resumable (the finalize
case): a crash after some containments were restored but before `state=inactive` is
recovered on re-run — already-restored containments skip, the rest restore, and a
half-finished restore is never misread as drift.

### 5.4 Disown / refuse recovery

Deleting `$ATLAS_STATE_DIR/activated/desktop-wallpapers` clears activation (RFC-0029
§5.5); a later `activate` captures the then-current wallpapers as the new prior.
Both refuse messages point at this file. There is no dead end.

## 6. Ownership analysis

Atlas owns the activation *transition* and the escrow record; each desktop's
wallpaper is borrowed with its prior held in write-once escrow and returned exactly
(or its key deleted if it was absent). Activation is refused up front whenever the
prior cannot be captured faithfully, so Atlas never switches a setting it cannot
restore — satisfying RFC-0029's record-before-switch invariant and AGENTS.md's
"never silently overwrites user configuration." An un-activated machine is fully
valid; `verify`/`install` of `desktop/wallpapers` is untouched.

Honesty notes: (a) restore is by the recorded `Image` value; Atlas does not capture
or restore unrelated wallpaper sub-keys (e.g. `FillMode`, `Color`) — it records what
it switches (`Image`) and refuses whenever the active plugin is not a plain image,
which is where those extra keys would matter. (b) Live apply depends on
`plasma-apply-wallpaperimage` + a running session; without them the change applies
at next login, and activation says so — it never claims "applied live" it cannot
substantiate.

## 7. Alternatives considered

- **plasma-apply-wallpaperimage for everything.** Rejected as the capture/restore
  primitive: it sets one uniform image across all screens and cannot restore
  divergent per-monitor wallpapers, and it does not *read* the prior. It is used
  only as a best-effort live nudge on top of the authoritative per-containment
  kwriteconfig6.
- **Refuse unless exactly one desktop containment.** Rejected as too restrictive —
  per-containment capture handles multi-monitor correctly; the honest refusal is on
  the *plugin type*, not the *count*.
- **Half-capture a slideshow/colour prior and refuse at deactivate.** Rejected —
  that is the Rev-deferred one-way door. Refusal must be at activate.

## 8. Testing strategy

New `tests/test_activation_wallpapers.sh`, mirroring `tests/test_activation.sh`.
Mock `kreadconfig6`/`kwriteconfig6` as shell functions backed by a temp ini-like
store (keyed by the group path), a discoverable set of containments seeded into a
fake appletsrc, and `plasma-apply-wallpaperimage` as a recording stub. Install the
module first so the marker is `installed`. Cases:

1. Verb plumbing (activate/deactivate resolve; hookless skip is generic to RFC-0029).
2. Requires installed; requires kreadconfig6/kwriteconfig6.
3. **Discovery**: with a folder desktop `[1]`, a panel `[2]`, and an applet host,
   only `[1]` is captured/applied; the panel is ignored.
4. **Refuse-at-activate** when a desktop's `wallpaperplugin` is `org.kde.slideshow`
   (and `org.kde.color`) — no state written, prior untouched.
5. Records prior verbatim (incl. `file://`) and applies the Atlas image; idempotent
   second activate is a no-op.
6. **URL normalization**: a prior stored as `file://…/foo.png` and the Atlas image as
   a `file://` URL compare correctly — no spurious drift right after activation.
7. **Multi-monitor**: two desktop containments with two different images → both
   captured with distinct `prior_image_<C>`, both set to Atlas, both restored to
   their own prior on deactivate.
8. Absent-sentinel: a containment with no `Image` key → `__ATLAS_ABSENT__`; restore
   deletes the key.
9. Restores exactly; deactivate writes `state=inactive`, drops `containments`/`prior_*`.
10. Refuse-to-clobber (activate and deactivate) when a desktop's current image is a
    third value; no partial restore.
11. **Interrupted-activate write-once**: seed `state=activating` with recorded
    priors and the images already set to Atlas; re-run reuses the priors, never
    launders Atlas into the escrow, settles `active`.
12. **Interrupted-deactivate finalize**: seed `state=active` with one containment
    already restored (current == prior) and one still Atlas; deactivate finishes the
    rest, skips the restored one, ends `inactive`, loses no prior.
13. Disown: deleting the record makes a fresh activate capture the current wallpapers
    as the new prior.
14. Strict parser: `prior_image_*` under inactive; a `prior_image_<C>` with no
    matching id in `containments`; a missing one for a listed id; non-integer id;
    unknown key/state/schema.
15. No-live path: without `plasma-apply-wallpaperimage`, activate/deactivate still
    write config and report "applies at next login."
16. Full suite stays green; `atlas install desktop/wallpapers` unchanged.

## 9. Decision required

1. Accept per-containment capture/restore keyed on **discovered** desktop
   containments (§4), reusing RFC-0029's write-once escrow with one `prior_image_<C>`
   per containment.
2. Accept **refuse-at-activate** whenever any desktop's active wallpaper plugin is
   not `org.kde.image` (the honest capture boundary), and URL-normalized comparisons
   with verbatim record/restore.
3. Accept the authoritative-kwriteconfig6 + best-effort-live-nudge apply model, with
   `plasma-apply-wallpaperimage`/session absence degrading to next-login.
