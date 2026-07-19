# RFC-0038: Hyprland Desktop Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-19 |
| **Phase / order** | Desktop — dual-session compositor, module 1 of 1 |
| **Depends on** | Nothing in the Atlas module graph — `MODULE_DEPENDS=()`. Host runtime: `python3` (see §8 / §14). |
| **Establishes** | Ownership, adoption, install-safety & rollback contract for `desktop/hyprland`, gating Part B's `module.sh` |

## 0. Why this RFC exists

Part A of `docs/superpowers/plans/2026-07-19-hyprland-source-build.md` unblocks
Hyprland on this machine by rebuilding `aquamarine` locally and installing the
stack outside the module system. Part B wraps that as a reversible
`modules/desktop/hyprland/module.sh`. Sol (escalation authority) reviewed the
Part B plan and returned **APPROVED_WITH_MANDATES**: implementation may proceed
only after an RFC defines ownership and rollback in writing. Two design
documents already exist —
`docs/superpowers/specs/2026-07-16-atlas-hyprland-desktop-design.md` (the
desktop itself) and
`docs/superpowers/specs/2026-07-19-hyprland-source-build-design.md` (the
aquamarine unblock) — but neither is an RFC, and the Part B plan's illustrative
`module.sh` (§B3) is not itself normative: it deploys config trees
unconditionally and detaches without checking drift, which is safe only by
accident. This RFC is the normative contract. Where it disagrees with the
illustrative code in the plan, this RFC wins.

## 1. Summary

Add `modules/desktop/hyprland` as Atlas's lifecycle manager for a second,
fully-configurable Wayland session — Hyprland — installed alongside Plasma,
which is never removed. Fedora 44 shipped `libdisplay-info` 0.3 before the
`solopasha/hyprland` COPR rebuilt its `aquamarine` renderer dependency against
it, so the module also owns a small, self-superseding local rebuild of that one
package. Atlas takes ownership only of what it creates: the COPR repository
intent, the local `aquamarine` RPM install, a fixed package set, five
Atlas-managed `~/.config` trees, two named wallpaper files, the recorded `dnf`
rollback transaction, and a supersession watcher. Everything else — Plasma, the
user's shell, unrelated themes and packages — is untouched.

The central rule is:

> Atlas owns the Hyprland installation intent and the Atlas-created desktop
> surfaces, never Plasma, never a package outside the fixed set, and never a
> config tree it did not create or verify byte-for-byte.

## 2. Goals and non-goals

**Goals**

- Install Hyprland and its fixed companion package set from the documented
  Fedora COPR source, on top of a locally rebuilt `aquamarine` that satisfies
  Fedora 44's `libdisplay-info.so.3` without exceeding Hyprland's hard
  `libaquamarine.so.8` link requirement.
- Perform the install as exactly one `dnf` transaction, gated additive-only by
  a rehearsal, and record its `dnf history` transaction id in Atlas state
  before anything else durable happens.
- Deploy five Atlas-owned `~/.config` trees and bake two named wallpapers, with
  an explicit, narrow adoption path for state that already matches Atlas
  source byte-for-byte, and a hard refusal otherwise.
- Record ownership with a schema-versioned marker with states
  `installing → installed → detached`.
- Provide idempotent `check`, `install`, `verify`, `update`, `remove`,
  `backup`, and `restore` hooks.
- Own a watcher that detects when the local `aquamarine` rebuild is superseded
  by an official COPR release, and disposes of itself at that point.
- Preserve Plasma as the default, always-selectable session.

**Non-goals**

- Managing Plasma, the login manager's default session choice, the user's
  shell, or any theme/package outside the fixed set in §4.
- `dnf remove`-ing any package on detach. Package rollback is always
  `dnf history undo <recorded-id>`, never a module-driven removal.
- Rewriting a config tree or wallpaper file that exists, differs from Atlas
  source, and carries no Atlas marker. Atlas refuses; it does not merge,
  back up, or silently overwrite.
- Live TTY validation mechanics (Part A of the plan), formal RFC-0034/RFC-0037
  amendments recording the B&W supersession, and reconciliation of legacy
  off-identity ("blue") assets. See §12.

## 3. Ownership

### 3.1 Atlas owns

- **The COPR repository intent** — `solopasha/hyprland` enabled with
  `gpgcheck=1`, recorded the way `development/ghostty` (RFC-0007 §3) records
  its COPR: Atlas records the intent and validates the repo file, but does not
  own Fedora's RPM database.
- **The local `aquamarine` RPM install**, `aquamarine-0.9.5-2%{?dist}.atlas1`
  (rendered `aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm`), **only while the
  official COPR build still requires `libdisplay-info.so.2`**. Ownership here
  is intentionally transient: see §5.
- **The fixed package set**: `hyprland`, `xdg-desktop-portal-hyprland`,
  `hyprlock`, `hypridle`, `hyprpaper`, `waybar`, `wofi`, `mako`, `kitty`,
  `grim`, `slurp`, `brightnessctl`, `playerctl`. No other package is Atlas's to
  install, upgrade, or remove under this module.
- **Five Atlas-managed config trees**, under the adoption rule in §6:
  `~/.config/hypr`, `~/.config/waybar`, `~/.config/wofi`, `~/.config/mako`,
  `~/.config/kitty`.
- **Two named wallpaper files**, under the adoption rule in §7:
  `~/.local/share/backgrounds/atlas/atlas-lock-bg.png` and
  `~/.local/share/backgrounds/atlas/atlas-wall-bw.png`.
- **The watcher's disposition** — the asset files
  `modules/desktop/hyprland/assets/watch-availability.sh`,
  `atlas-hypr-check.service`, and `atlas-hypr-check.timer`, and the systemd
  user-timer unit they install, including disabling that timer once its job is
  done (§9).
- **The recorded `dnf history` transaction id** for the Part A/B install
  transaction, written into `$ATLAS_STATE_DIR` (§8.4) — not the RPM database
  entries themselves.
- **Its own marker**, `$ATLAS_STATE_DIR/installed/desktop-hyprland`.

### 3.2 Atlas does not own

- The Plasma session, SDDM's default-session choice, or any Plasma
  configuration. Plasma is never a target of `install`, `update`, or `remove`.
- The user's shell, shell startup files, or any workflow tool not in the fixed
  package set.
- Any theme, icon set, cursor theme, or font — those remain the concern of
  `desktop/theme`, `desktop/icons`, `desktop/cursor`, and `desktop/fonts`
  respectively; this module references them by name only, as
  `development/ghostty` does (RFC-0007 §7).
- Any wallpaper file other than the two named in §3.1 — including the
  pre-existing "blue" canvases the desktop design doc flags for a future
  reconciliation pass (§12). This module must not touch, list, or delete them.
- Packages outside the fixed set, even if the same `dnf` transaction happens
  to touch them incidentally (which the additive-only gate in §8.2 is designed
  to prevent).
- Any package removal whatsoever. `remove` never calls `dnf remove` or `dnf
  history undo`; see §10.

## 4. Package source and the one-transaction rule

Hyprland is not in Fedora base repositories; the documented source is the
`solopasha/hyprland` COPR, exactly as recorded in
`2026-07-16-atlas-hyprland-desktop-design.md` §6. `install` may install
`dnf-plugins-core` if `dnf copr` is missing, then:

```
dnf -y copr enable solopasha/hyprland
```

Atlas validates the resulting repo file the same way `development/ghostty`
validates its COPR (RFC-0007 §3): enabled, correct repo id, `baseurl` present,
`gpgcheck=1`. No `--nogpgcheck` path exists or is permitted.

The install itself is **exactly one `dnf` transaction**: the local aquamarine
RPM (§5) plus the fixed package set (§3.1), given to `dnf install` together.
Splitting this into two transactions would let the resolver satisfy Hyprland's
`aquamarine` dependency from a repository copy (if one ever appears) instead of
the local build, silently defeating the version pin in §5. The transaction is
gated additive-only before it runs for real; see §8.2.

## 5. The aquamarine rebuild and its supersession contract

Fedora 44 bumped `libdisplay-info` `0.2` → `0.3`; the COPR's
`aquamarine-0.9.5-2` still links `.so.2` and cannot install. The fix is a
narrow local rebuild, not a source install of Hyprland itself
(`2026-07-19-hyprland-source-build-design.md` §3 rejected both a permanent
`/usr/local` shadow build and a container, because neither can hand off
cleanly to the eventual official package or the GPU/seat that a login-selected
compositor needs).

- **Version is pinned to exactly `0.9.5`.** Hyprland's installed binary hard-
  links `libaquamarine.so.8()(64bit)`; only `aquamarine` `0.9.5` provides that
  soname. A version bump changes the provided soname and makes the fixed
  Hyprland package unsatisfiable. The build helper must never bump it.
- **Release is pinned to exactly `2%{?dist}.atlas1`**, rendering
  `2.fc44.atlas1`. This is the load-bearing detail: it sorts above the broken
  upstream `2.fc44` (so it installs now) and below a future official `3.fc44`
  (so a routine `dnf upgrade` silently swaps in the official rebuild the
  moment it lands — no Atlas action required). The bare form `2.atlas1`
  (without `%{?dist}`) sorts *below* `2.fc44` and must never be used.
- **The binary RPM is built through `mock` only.** `mock` builds inside a
  disposable chroot and mutates nothing on the host, so the build never
  installs build dependencies onto the running system or creates a second,
  unrecorded host `dnf`/`rpm` transaction outside the one gated install in §8.
  Host `rpmbuild` may be used **only** to re-roll the modified *source* RPM
  (`-bs`) inside a private, disposable `_topdir` — that produces no package
  mutation — and host `dnf builddep` + `rpmbuild -bb` is **not permitted**.
  When `mock` or its prerequisites are unavailable the build fails clearly;
  it does not fall back to a host build. (Amends the original "mock-first,
  rpmbuild fallback" wording: the fallback is removed because it violated the
  one-transaction/no-host-mutation isolation guarantee this RFC depends on.)
- **The build gate** (checked by the build helper, and re-checked by
  `module::install` before the RPM is ever handed to `dnf`) validates the
  built RPM as a whole, not just three soname strings: its exact package
  **name** is `aquamarine`; its **version** is `0.9.5` and **release** is
  `2.fc44.atlas1` (the pin in this section); its **architecture** is
  `x86_64`; its `requires` must include `libdisplay-info.so.3` and must
  **not** include `libdisplay-info.so.2`; its `provides` must include
  `libaquamarine.so.8`; and the RPM must pass `rpm -K` payload/header
  integrity. Soname matching is **exact**, not a prefix: `.so.3` never matches
  `.so.30` and `.so.8` never matches `.so.80` (the soname must be followed by
  the rpm `(...)` decoration, end-of-line, or whitespace). A pre-existing
  artifact at the expected path is **always** re-validated against all of
  these — never trusted by filename. Any other outcome is a build failure, not
  an install candidate.
- **Auto-supersession is the intended end state, not a future migration.**
  Atlas does not need to detect the official `-3` package and swap it in; a
  normal `dnf upgrade` does that on its own once the COPR ships it, because
  RPM version ordering already favors `-3` over `-2.atlas1`. Atlas's job is
  only to notice when it happened (§9) and to stop asserting ownership of a
  package it no longer built.

## 6. Configuration ownership and the adoption flow

The desktop's `~/.config/{hypr,waybar,wofi,mako,kitty}` trees are shipped as
`modules/desktop/hyprland/config/{hypr,waybar,wofi,mako,kitty}`, the source of
truth. Because the desktop was already built and hand-staged before this RFC
(`2026-07-16-atlas-hyprland-desktop-design.md` §5), a real target machine can
have these trees present on disk **before** the module has ever run and before
any marker exists. The existing Atlas pattern of blanket-refusing any
pre-existing state (RFC-0007 §4, RFC-0021, RFC-0008 §title) is not workable
here without special-casing this exact situation, so Sol's mandate defines a
narrow, explicit exception instead of a general adoption mechanism:

- **If a target tree already exists and is byte-identical to the
  corresponding module source** — a full directory manifest match, file names,
  contents, and hashes, computed the same way `desktop/sddm`'s module compares
  its managed theme tree (`find | sha256sum`) — **Atlas may adopt it without
  rewriting it.** `install` writes the marker and treats the tree as
  Atlas-managed from that point forward. No bytes change on disk.
- **If a target tree already exists, differs from module source in any way,
  and no `installed` (or `installing`) marker exists for this module, `install`
  must refuse** for every affected tree, and must do so **before any package
  mutation** — before the COPR is enabled, before the aquamarine RPM is built
  or staged, before `dnf install` runs. A config conflict is cheap to fix by
  hand; an additive-only package transaction that then can't be finished
  cleanly is not.
- **Ownership is recorded per tree, not implied by the marker.** A tree becomes
  Atlas-managed only once Atlas has actually created it or adopted it
  byte-for-byte, and that fact is recorded in a durable ownership record
  (`$ATLAS_STATE_DIR/hypr-owned-trees`, mode `600`), consistent with the
  standing rule that ownership is *recorded, never inferred*
  (`docs/conventions.md` "Owning persistent state"). The record is itself a
  **trust boundary**: it must be a regular, non-symlink, mode-`600` file whose
  every line is exactly one of the five known tree names, with no duplicates and
  no unknown entries. A wrong-mode, symlink, directory, partial, or otherwise
  malformed record authorizes **nothing** — Atlas treats it as "no trees owned"
  and refuses to rewrite or detach based on it. Writes replace the path with
  `mv -T` semantics so a forged directory at the ownership path can never be
  written-through. For a tree Atlas owns, `install` and `update` may rewrite
  drift from source, and drift is a `verify` failure (§10), exactly as in
  RFC-0007 §4/§6.3. A tree that is **not** in a *valid* ownership record and
  differs from Atlas source is refused and never destroyed — even under an
  `installing`/`installed` marker. This closes the crash-window in which a
  marker written before any tree existed could otherwise let a reconciling
  retry delete unrelated content that appeared in the gap. The marker records
  lifecycle state (`installing`/`installed`/`detached`); it is not a blanket
  ownership claim over the five paths.
- This exception applies only to the five named trees at their exact paths.
  It is not a general "adopt if it matches" primitive for other modules to
  reuse without their own RFC — RFC-0031 §2.2/§4 found "adopt iff
  byte-identical" fragile as a *general* mechanism and replaced it with a
  backup-and-recreate scheme for its narrower single-file case. Here the
  match is a full five-directory manifest against content this same weekend's
  work staged, which is why the narrow exception is acceptable for this one
  module, this one time.

## 7. Wallpaper ownership and its adoption flow

The wallpaper bake (`assets/generate.sh`) writes exactly two files:
`~/.local/share/backgrounds/atlas/atlas-lock-bg.png` and
`~/.local/share/backgrounds/atlas/atlas-wall-bw.png`. The same rule as §6
applies, scoped to only these two filenames:

- Wallpaper ownership is recorded in the sidecar hash file
  (`.atlas-hypr-wall.sha256`), the wallpaper analogue of §6's per-tree
  ownership record; a file is Atlas-owned only once Atlas has staged it, never
  because a marker exists.
- If either file already exists and is byte-identical (sha256) to what
  `generate.sh` would produce, Atlas adopts it without regenerating.
- If either file exists, differs, and is not Atlas-owned, `install` refuses —
  before any package mutation — exactly as in §6.
- A wallpaper target that is a **symlink** is refused outright (it could
  redirect a write anywhere), and every write is staged into a same-directory
  temp then atomically renamed into place, so a reader never sees a partial
  file and a symlinked path is never followed.
- Every other file under `~/.local/share/backgrounds/atlas/` — including the
  legacy off-identity ("blue") wallpaper assets the desktop design doc flags
  for a future cleanup (`2026-07-16-atlas-hyprland-desktop-design.md` §8) — is
  left alone unconditionally. This module must not enumerate, hash, move, or
  delete any file in that directory other than the two named above.

## 8. Install safety contract

`install` follows this exact ordering; any step failing stops the sequence
without proceeding to the next:

1. **Fedora 44 gate, before the marker is touched.** This module's package
   set and local rebuild are pinned to Fedora 44's specific
   `libdisplay-info.so.3` ABI break; a generic "is this Fedora" check is not
   enough. `install` reads the Fedora release version and refuses on anything
   other than 44, before writing `installing`.
2. **Load and validate any existing marker** (§9). An `installing` marker from
   a prior interrupted run is a valid starting point for reconciliation, not
   a hard failure.
3. **Config and wallpaper adoption/refusal** (§6, §7), evaluated for every
   tree and both filenames, entirely before any COPR or package step. A
   refusal here exits `install` with no repository enabled and no package
   touched.
4. **Write the `installing` marker.**
5. **Ensure the aquamarine build artifact exists and passes the build gate**
   (§5), building it via the module's build helper if it does not.
6. **Transaction rehearsal — the gate that protects Plasma.** Resolve the full
   transaction (local aquamarine RPM + the fixed package set) with a
   non-committing dnf invocation (`--assumeno` or equivalent). The rehearsal
   must show **zero removals, erasures, or obsoletions, and zero
   upgrades/downgrades of any package outside the aquamarine/hypr\* set**.
   Nothing in Plasma links aquamarine; any other line means the resolver is
   doing something unexpected, and `install` aborts here — no package has been
   installed and the host is unchanged.
7. **Run the single real `dnf install` transaction** (§4).
8. **Record the transaction id immediately, using a before/after boundary.**
   `install` captures the newest `dnf history` id *before* the transaction in
   step 7, and reads it again *after*. Both boundary reads must succeed: a
   *failed* history lookup is distinguished from a *confirmed-empty* history (a
   real table with no rows, boundary value `0`), so a lookup failure aborts
   rather than being mistaken for an empty history that would let a stale id be
   recorded. It records the new id only when a new transaction actually appeared
   (`after > before`, with a well-formed numeric boundary), and only when
   `dnf history info <id> --json` proves the transaction's **identity**: exactly
   one transaction with that id, `status` `Ok`, an `Install` of the exact
   `aquamarine` NEVRA (`0.9.5` / `2.fc44.atlas1` / `x86_64`) and of `hyprland`,
   and **no** `Remove`/`Downgrade`/`Obsolete`/unknown action on any package
   (an `Upgrade`/`Reinstall` is tolerated only for the exact hypr/aquamarine
   allowlist). The documented, stable JSON output is parsed rather than the
   human-readable layout. The id is written atomically (same-dir temp then
   `mv`), mode `600`, into `$ATLAS_STATE_DIR` — a plain file distinct from the
   marker, so the exact `dnf history undo <id>` command is recoverable from a
   bare TTY with the state directory as the only thing that has to be readable.
   If the packages were installed but a valid id cannot be recorded, `install`
   leaves the marker at `installing` and prints a precise recovery command; it
   never records an unrelated, failed, or no-op transaction, and a reconciling
   retry never runs a second `dnf` transaction to "fix" the missing id.
9. **Deploy the five config trees** (§6) and **bake the two wallpapers**
   (§7), applying the adoption rule to any tree/file not already covered by
   step 3's evaluation (a config tree can appear between steps 3 and 9 only if
   something else raced the filesystem, which is itself worth failing loudly
   on rather than silently overwriting).
10. **Re-verify** everything `verify` (§10) checks.
11. **Promote the marker to `installed`.**

An interrupted install leaves the marker at `installing` (step 4's write is
never rolled back by a later failure). `installing` **persists on failure** —
`install` never deletes or downgrades its own marker on an error path. A
subsequent `install` call reconciles: it re-checks whatever already
succeeded (repo enabled, RPM built, packages installed, transaction id
recorded, configs deployed) and only performs the remaining steps, promoting
to `installed` only once every check in step 10 passes. This mirrors the
`development/ghostty` reconciliation model (RFC-0007 §6.2).

Two invariants make reconciliation safe rather than merely convenient:

- **The completed package transaction is detected before any package
  mutation.** On a retry, `install` checks whether both `aquamarine` and
  `hyprland` are already installed *before* enabling the COPR, installing
  `dnf-plugins-core`, or building/handing anything to `dnf`. If they are, it
  runs no repository or package mutation at all — it only validates the
  recorded rollback id (refusing, with a recovery command, if it is missing)
  and continues with the config/wallpaper/watcher phases. This guarantees the
  "exactly one `dnf` transaction" rule survives an arbitrary number of
  interrupted retries.
- **Ownership is re-evaluated per target on every path, before mutation.** The
  adoption/refusal gate (§6/§7) runs on `absent`, `installing`, and reconciling
  `installed` paths alike, keyed off the per-target ownership records rather
  than the marker, so content that appeared in an interrupted run's crash window
  is refused, never destroyed.

## 9. Watcher disposition

Before install, the machine's existing watcher
(`modules/desktop/hyprland/assets/watch-availability.sh`, wired to
`atlas-hypr-check.timer`) polls for the **official** COPR rebuild becoming
available — the pre-unblock question. After this module installs the local
`.atlas1` rebuild, that question is answered and stays answered; the old
"is the official package out yet" check would only ever fire once, on the
next-to-official rebuild it can no longer distinguish from the local one.

The module therefore owns and repurposes the watcher's detection logic so that,
**once installed**, it watches the *installed* aquamarine's RPM `%{RELEASE}`
for the disappearance of the `.atlas1` suffix — supersession, not
availability:

- release still ends `.atlas1` → still on the Atlas local build; watcher stays
  enabled and logs quietly.
- aquamarine is not installed at all → nothing to watch; the watcher disables
  its own timer.
- release no longer ends `.atlas1` → the official rebuild has replaced it via
  a routine `dnf upgrade` (§5); the watcher notifies once and disables its own
  timer. This is an all-clear notification, not an error.

This module owns the watcher's assets (the script and the two systemd user
units) and its disposition (when it disables itself). It does not own
`dnf upgrade` scheduling, which remains ordinary Fedora/DNF policy.

## 10. Lifecycle contract

### 10.1 `check`

Returns `0` only when the marker is valid, state is `installed`, Hyprland is
present (binary on `PATH` or RPM-owned), `aquamarine` is installed, all five
config trees match Atlas source exactly, both wallpapers match their recorded
hashes, the recorded rollback transaction still exists and corresponds to this
install, and the supersession watcher is in its expected state (§9). Any other
state returns non-zero so `install` can decide whether reconciliation or a
fresh install is appropriate.

### 10.2 `install`

As specified in §8. Idempotent, and specifically **zero-mutation** on a healthy
system: a second `install` against a fully `installed` marker first evaluates
the complete health predicate (§10.1) and, when everything is already
satisfied, returns immediately — performing no `dnf` call, no rehearsal, no
build, no config/wallpaper/watcher rewrite, and not even a no-op marker write.
Re-promoting a marker that is already `installed` would be a redundant write on
the hot path; the health check is the idempotency guarantee. Only when the
health predicate fails (drift, an interrupted `installing` marker, a missing
owned surface) does `install` proceed into the reconciling steps of §8.

### 10.3 `verify`

Verification is asymmetric, matching the standing Atlas rule
(`AGENTS.md`, RFC-0006 §"Verify", RFC-0007 §6.3):

- **No marker (absent):** `verify` returns `0` and reports Hyprland as absent
  or user-owned. A machine that has never run this module, or on which
  Hyprland was installed by hand outside Atlas, is valid state.
- **`detached` marker:** `verify` returns `0` and reports that Atlas is no
  longer asserting health, consistent with `development/ghostty` (RFC-0007
  §5).
- **`installing` marker:** `verify` fails — an interrupted install is not
  healthy state, and failing loudly is what prompts a reconciling `install`.
- **`installed` marker:** `verify` fails only when Atlas-owned state is
  broken: any of the five config trees drifted from Atlas source, either
  wallpaper file drifted from its recorded hash, the recorded rollback
  transaction is missing/unreadable/malformed or no longer names this module's
  `aquamarine`+`hyprland` install in `dnf history`, Hyprland or `aquamarine` is
  no longer installed, or the supersession watcher is not in its expected
  state (deployed files must match repository source, and while the local
  `.atlas1` build is still installed the timer must be enabled and active;
  after supersession a self-disabled timer is valid — §9). The recorded
  transaction is validated for identity (§8 step 8): a successful (`status`
  `Ok`) transaction that installed the exact `aquamarine` NEVRA and `hyprland`
  with no forbidden package operations, not merely a well-formed number. The
  recorded id file must itself be a regular, non-symlink, mode-`600` file.
  Otherwise it succeeds.

`verify` never launches Hyprland, never inspects Plasma, and never checks
packages outside the fixed set.

### 10.4 `update`

Re-applies the latest Atlas config trees and wallpaper files (through the same
adoption/refusal evaluation as install, since an operator may have hand-edited
a tree between runs) and refreshes the marker. `update` never re-runs the
package transaction and never rebuilds aquamarine; package currency is
Fedora/DNF policy, exactly as in `development/ghostty` (RFC-0007 §6.4).

### 10.5 `remove` (= detach)

The platform still has no `atlas remove` verb (RFC-0002 is `Proposed`), but the
hook is specified now, following the pattern already used by
`development/ghostty` (RFC-0007 §6.5) and every other module with a `remove`
hook:

1. Load the marker. `absent`/`detached` → return `0` (already detached, or
   nothing to detach).
2. **Require complete, valid ownership records** (all five trees in
   `hypr-owned-trees`, both wallpapers in a mode-`600` sidecar) **and** verify
   every managed config tree and both wallpaper files still match Atlas source
   before deleting anything. Byte-identity alone never authorizes deletion. If
   ownership records are missing/malformed/partial, or any tree or file has
   drifted,
   `remove` **refuses** — the whole operation, not just the drifted item — and
   leaves the marker at `installed`. Deleting a file that may now hold
   uncommitted user edits is exactly the silent-data-loss case
   `AGENTS.md` forbids.
3. If everything matches, delete the five config trees and the two wallpaper
   files.
4. Write the marker to `detached`.
5. Print the recorded rollback command,
   `dnf history undo <recorded-id>`, reading `<recorded-id>` from the state
   file written in §8 step 8.

`remove` **never** calls `dnf remove`, `dnf history undo`, or disables the
COPR repository. Package rollback is the user's explicit, one-command choice
from a bare TTY, exactly as designed in
`2026-07-19-hyprland-source-build-design.md` §5 — conservative, because a
module-driven `dnf remove` risks a cascading resolution nobody rehearsed.

### 10.6 `backup` and `restore`

Documented no-ops, as in `development/ghostty` (RFC-0007 §6.6):
Atlas-owned Hyprland state is fully reconstructable from the repository and
the recorded transaction id. There is no irreplaceable state to capture.

## 11. Dual-session safety

Plasma is never a target of any hook in this module and is never removed,
disabled, or reconfigured. Once the fixed package set is installed, SDDM's
session dropdown lists "Hyprland" automatically (the `hyprland` package ships
its own `.desktop` session file; Atlas does not need to author one). SDDM
remembers the last-picked session, so after a first Hyprland login it becomes
the preselected entry — Plasma remains one click away in the same dropdown,
and is the entry a fresh machine boots into by default before any Hyprland
session is ever chosen. Every failure mode collapses to: switch to a TTY,
`dnf history undo <recorded-id>`, reboot, land in untouched Plasma
(`2026-07-19-hyprland-source-build-design.md` §5).

## 12. Out of scope

- **Part A's live TTY validation mechanics** (the five-point go/no-go gate,
  the mock/rpmbuild build session, the manual baseline snapshot) — these are
  one-time, human-driven runbook steps, not module behavior. See
  `docs/superpowers/plans/2026-07-19-hyprland-source-build.md` Part A and
  `docs/superpowers/specs/2026-07-19-hyprland-source-build-design.md`.
- **RFC-0034/RFC-0037 amendments** formally recording the B&W word-only
  supersession of the orbital-A identity on this desktop. Those RFCs are
  unchanged by this one; a future amendment RFC covers them.
- **Reconciliation of legacy off-identity ("blue") assets** —
  `~/atlas-boot-preview.png`, the old `atlas-login-canvas.png`/SVGs, and the
  cyan `ghostty` `atlas-reference` theme
  (`2026-07-16-atlas-hyprland-desktop-design.md` §8). This module must not
  touch them; a separate cleanup pass does.

## 13. Validation matrix

Required test coverage for `modules/desktop/hyprland/module.sh` and its build
helper (`tests/test_module_hyprland.sh`, `tests/test_hyprland_build_helper.sh`,
hermetic — sandboxed `HOME`/XDG/state, mocked `dnf`/`rpm`, no host mutation):

- clean, never-installed Fedora 44 verifies successfully and fails `check`;
- non-Fedora-44 install refuses before any mutation (no marker, no repo, no
  package);
- pre-existing, byte-identical config trees with no marker are adopted by
  `install` without rewriting a single file;
- pre-existing, differing config trees with no marker cause `install` to
  refuse for every affected tree, before the COPR is enabled and before any
  package is touched;
- the same two rules hold independently for each of the two named wallpaper
  files, and a third-party file under the same wallpaper directory is never
  inspected or touched;
- a non-additive rehearsal (a synthetic removal/non-hypr upgrade) aborts
  `install` before the real transaction runs;
- the aquamarine build gate failing (`.so.2` present, `.so.3`/`.so.8` absent)
  aborts `install` before `dnf install` runs;
- a successful install writes `installed`, deploys all five config trees,
  bakes both wallpapers, records a transaction id file, and installs the
  aquamarine RPM together with the fixed package set in one transaction;
- repeated `install` and repeated `verify` are idempotent;
- `doctor` follows `verify`;
- a drifted config tree fails `verify`;
- `update` re-applies drifted config and restores a passing `verify`;
- `remove` with all managed trees intact detaches (marker → `detached`,
  trees/wallpapers deleted, transaction id file preserved, no `dnf remove`
  or `dnf history undo` invoked);
- `remove` with any managed tree or wallpaper drifted refuses entirely and
  leaves the marker at `installed`;
- repeated `remove` after a successful detach is a no-op;
- a package/transaction failure mid-`install` leaves the marker at
  `installing`, never promotes it, and a later `install` can reconcile;
- `backup` and `restore` are no-ops;
- the watcher script reports "still on `.atlas1`" while installed, "nothing to
  watch" when aquamarine is absent, and "superseded" (plus timer disable) the
  moment the installed release no longer ends `.atlas1`.

## 14. Architecture review findings

- **Ownership:** every owned path is enumerated in §3.1 by exact name; nothing
  is inferred from a command, package, or file existing on disk (matches the
  standing rule in `AGENTS.md` and `docs/module-authoring.md`).
- **Lifecycle:** `installing → installed → detached`, matching the marker
  state machine already used by `development/ghostty` and
  `modules/desktop/sddm`.
- **Dependency model:** `MODULE_DEPENDS=()`. This module does not depend on
  `desktop/theme`, `desktop/fonts`, `desktop/icons`, or `desktop/cursor`; it
  references their outputs by name only, the same relationship Ghostty has
  with fonts (RFC-0007 §7). Host runtime dependency: **`python3`**, used solely
  to parse the stable dnf5 `history info --json` for rollback-identity
  validation (§8 step 8). This is the second Atlas host-runtime dependency after
  `gpg` (RFC-0004 / `docs/conventions.md`). `install` preflights `python3`
  **before** any package mutation so a missing interpreter never leaves packages
  installed with an unrecordable transaction. Suggested recovery:
  `dnf install python3` or `atlasctl install development/python`.
- **Security:** no `--nogpgcheck`; the COPR is an explicit, narrow trust
  decision matching RFC-0007 §3's precedent; the local aquamarine build is
  `mock`-isolated (§5, no host build fallback), so the only privileged host
  package mutation is the single additive-gated `dnf` transaction. Ownership
  records (`hypr-owned-trees`, wallpaper sidecar) are trust boundaries: regular
  non-symlink mode-`600` files with exact known entries; malformed/partial/
  wrong-mode records authorize nothing and refuse detach.
- **Idempotency:** `install`, `verify`, `update`, `backup`, and `restore` are
  repeatable; `remove` is repeatable after a successful detach and refuses
  cleanly (no partial state) on drift.
- **Rollback:** a single recorded `dnf history` id is the entire package
  rollback path, executable from a bare TTY with no network — the same floor
  Part A already validates by hand. `remove` never performs package rollback
  itself, keeping that one-command path the user's explicit choice.
- **Adoption exception:** §6/§7's byte-identical adoption path is scoped
  narrowly (five named config trees, two named wallpaper files, exact-match
  only, refuse otherwise) specifically because this desktop was staged before
  the module existed; it is not offered as a general Atlas adoption
  primitive, and RFC-0031's experience with a similar idea for a single file
  is called out so a future author does not generalize it without their own
  RFC.
- **Maintainability:** the module is self-contained under
  `modules/desktop/hyprland/`; the build helper is a separate script so
  `module::install` stays fast and deterministic rather than compiling on
  every run.

No architecture or engine change is required. Implementation (Part B of the
plan) may proceed under this contract.
