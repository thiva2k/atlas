# RFC-0035: Lock-Screen HUD

Status: Accepted

Date: 2026-07-15

Extends: RFC-0029 (Activation framework), RFC-0034 (Atlas HUD identity)

## 1. Summary

The Plasma lock screen becomes the Atlas HUD showpiece (the surface seen many times
a day): a giant thin Inter clock framed by a reticle, a slowly drifting armillary,
and a bare hairline password field on the deep-navy field — built from the
`desktop/identity` tokens and the Orbital-A language. It ships as a new
`desktop/lockscreen` module: an installable Plasma look-and-feel package plus a
reversible, opt-in activation. No display-manager change; the lock screen is
user-scope and falls back safely.

## 2. What is delivered

- **A Plasma look-and-feel package** `org.atlas.hud` (shipped in the module's
  assets: `metadata.json` + `contents/lockscreen/LockScreen.qml` +
  `LockScreenUi.qml`), installed **user-scope** to
  `${XDG_DATA_HOME:-$HOME/.local/share}/plasma/look-and-feel/org.atlas.hud/`. No
  root.
- **`desktop/lockscreen/module.sh`** — install/check/verify/update/remove with the
  standard Atlas discipline (mode-600 marker, manifest hash of the shipped files,
  refuse-unmanaged preflight, atomic writes). It uses the **in-place-upgrade-safe**
  marker pattern (marker-load validates structure only; drift is on-disk-vs-source;
  update refreshes the marker) — i.e. it does not reintroduce the fish/fastfetch bug
  fixed in RFC-0034.
- **Reversible activation** (`module::activate`/`deactivate`), reusing the RFC-0029
  escrow verbatim (transitional `activating` state, write-once prior, refuse-to-
  clobber, already-restored finalize, absent-key sentinel + delete-on-restore). The
  switched setting is `kscreenlockerrc [Greeter] Theme` (read/written via
  kreadconfig6/kwriteconfig6): activate records the prior theme (or the absent
  sentinel) once, then sets it to `org.atlas.hud`; deactivate restores the prior
  verbatim (or deletes the key if it was absent). Applies at the **next lock** —
  kscreenlocker reads the key when it spawns its greeter, not live.

## 3. The QML — design + the auth wiring that must work

Visual (per the Atlas HUD design bible): deep navy gradient + a faint grid; a large,
off-center armillary rotating at constant velocity (~240s/rev, linear — an
instrument, not a toy); a giant clock in Inter Thin, framed by four reticle
corner-brackets that lock on once at wake then hold still; the password field as a
**bare hairline underline** (not a boxed field) with a cyan (`#57e5ff`) caret and a
focus-sweep; a wrong-password reaction (warm flash + one 3px shake + a single
satellite pulse). Refusals: no frosted-glass panel, no avatar-in-a-ring, no card.

Auth wiring is copied structurally from the real kscreenlocker greeter reference
(the part that must be correct, so the screen actually unlocks): the greeter injects
an `authenticator` (`org.kde.kscreenlocker`'s `ScreenLocker.Authenticator`); the
password field calls `authenticator.respond(password)` (not `tryUnlock()`), and a
`Connections { target: authenticator }` block handles `succeeded` / `failed` /
`infoMessageChanged`. Imports mirror the reference (`org.kde.kscreenlocker`,
`org.kde.plasma.private.sessions`, `org.kde.plasma.clock`, keyboard indicator,
Kirigami).

## 4. Safety, verification, and revert

**Honest limitation:** the build machine has no `qmllint`/`qml6`/
`kscreenlocker_greet`, so the QML **could not be validated or rendered offline**.
The module lifecycle and activation are fully unit-tested; the QML render/unlock is
verified by **locking the screen** — a bounded, reversible test:

- A lock-screen theme that fails to load falls back to kscreenlocker's default
  locker (kscreenlocker behavior) — a broken theme degrades the *lock* only, never
  the *login* path (plasma-login-manager is untouched). It cannot lock the user out.
- **Revert:** `atlas deactivate desktop/lockscreen` restores the prior theme. Manual
  escape from a TTY or System Settings:
  `kwriteconfig6 --file kscreenlockerrc --group Greeter --key Theme --delete ""`
  then relock (or `loginctl unlock-session`).
- Activation is never part of a default `atlas activate` sweep — it is an explicit,
  named, opt-in step, verified by a canary lock before being trusted.

## 5. Testing

23 module tests + 20 activation tests (part of the full suite, 1152 passing):
install/verify/marker discipline; the in-place-upgrade path (marker-load tolerates a
source change; update reconciles + refreshes); and the RFC-0029 activation contract
(records prior, idempotent, restores exactly, refuse-to-clobber, absent sentinel,
interrupted-activate write-once, interrupted-deactivate finalize). Mocks
kreadconfig6/kwriteconfig6 over a temp store, as the theme/activation tests do. The
rendered QML is out of unit-test scope (see §4).

## 6. Decision required

1. Accept `desktop/lockscreen` shipping the `org.atlas.hud` look-and-feel package
   (user-scope) with the standard reversible install lifecycle.
2. Accept the RFC-0029 activation of `kscreenlockerrc [Greeter] Theme` (record-prior
   / restore-verbatim), applied at next lock, never automatic.
3. Accept that the QML is verified by a reversible canary lock (no offline renderer
   available), with the documented fallback + revert path.
