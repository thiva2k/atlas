# RFC-0037: KSplash Startup Splash

Status: Accepted

Date: 2026-07-15

Extends: RFC-0029 (Activation framework), RFC-0034 (Atlas HUD identity),
RFC-0035 (Lock-screen HUD)

## 1. Summary

Closes the last cohesion gap between boot and desktop: the stock-blue KSplash
theme currently flashes between login and the desktop appearing, breaking the
boot → login → desktop visual continuity the Plymouth ignition (RFC-0024c)
and lock-screen HUD (RFC-0035) already establish. Atlas does not ship a new
package for this — the `org.atlas.hud` Plasma look-and-feel package
(installed by `desktop/lockscreen`) gains a `contents/splash/Splash.qml`, and
a new **activation-only** module, `desktop/ksplash`, reversibly switches
`ksplashrc [KSplash] Theme` to `org.atlas.hud`, reusing the RFC-0029 escrow
pattern verbatim.

## 2. What is delivered

- **`Splash.qml`** added to the *existing* `org.atlas.hud` package at
  `modules/desktop/lockscreen/assets/org.atlas.hud/contents/splash/Splash.qml`,
  plus a rasterized identity mark at `contents/splash/images/atlas-mark.png`
  (256×256, generated from `modules/desktop/identity/assets/atlas-mark.svg`
  via `magick -background none -density 384 … -resize 256x256 …`, the only
  raster conversion tool available in this environment).
- **No change needed to `desktop/lockscreen`'s install logic.** Its manifest
  hashes every file under the package source
  (`find . -type f | sort | xargs sha256sum`, see `_lockscreen_manifest` in
  `modules/desktop/lockscreen/module.sh`), so adding `contents/splash/*`
  auto-extends install/verify/check coverage with zero code changes. Verified
  directly: a hermetic `module::install` after adding the splash files copies
  and hashes them, and `module::verify`/`module::check` both pass. A new
  assertion was added to `tests/test_module_lockscreen.sh` asserting the
  splash files are present after install, so this stays covered.
- **New module `modules/desktop/ksplash/module.sh`** —
  `MODULE_DEPENDS=(desktop/lockscreen)`. It installs nothing of its own:
  `install`/`check`/`verify`/`update` are thin hooks that confirm
  `org.atlas.hud`'s `contents/splash/Splash.qml` is present (owned by
  `desktop/lockscreen`); `remove`/`backup`/`restore` are no-ops. This
  satisfies the discovery contract (`MODULE_NAME`, `MODULE_DESCRIPTION`,
  `module::check`/`install`/`verify`, a README) that every discovered module
  must meet (`tests/test_modules.sh`).
- **Reversible activation** (`module::activate`/`deactivate`), reusing the
  RFC-0029 escrow exactly as `desktop/lockscreen` does for
  `kscreenlockerrc [Greeter] Theme` — transitional `activating` state,
  write-once prior, refuse-to-clobber on drift, already-restored finalize on
  deactivate, absent-key sentinel + delete-on-restore. The switched setting is
  `ksplashrc [KSplash] Theme` → `org.atlas.hud`. Applies at the **next
  login/startup** — `ksplashqml` reads `Theme` only when it spawns between
  login and the desktop appearing, not live.

### Engine

`ksplashrc [KSplash] Engine` was checked, not assumed. On this Plasma 6.7
install there is no user-scope `~/.config/ksplashrc` at all; the effective
value comes from the `kdedefaults` cascade written by the active
look-and-feel package (`org.kde.breezedark.desktop`'s
`contents/defaults` ships `[ksplashrc][KSplash] Theme=org.kde.breeze.desktop`,
and every stock look-and-feel package's `contents/defaults` — Fedora and
Breeze variants alike — carries `Engine=KSplashQML` at that layer via
`~/.config/kdedefaults/ksplashrc`). Confirmed directly:
`kreadconfig6 --file ksplashrc --group KSplash --key Engine` resolves to
`KSplashQML` even with no override file present. **Atlas therefore does not
manage `Engine`** — only `Theme`. `module::activate` still checks the
resolved `Engine` value defensively and refuses (with guidance to set
`Engine=KSplashQML` first) rather than silently activating a QML theme that
would never run, in case a future environment's default differs — mirroring
how `desktop/fonts` manages two keys where two are actually needed; here one
suffices.

## 3. The QML — stage contract copied from the real KSplash reference

`Splash.qml` is written directly against
`/usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/splash/Splash.qml`,
the real KSplash theme shipped on this system. The stage contract is copied
structurally: a root `Rectangle` sized to the screen, `property int stage`
that `ksplashqml` drives from 1 (earliest) through 6 (session ready), and an
`onStageChanged` handler matching the reference's two reaction points —
content fades in at `stage == 2` (`OpacityAnimator`, same as the reference's
`introAnimation`), and startup-nearly-done work happens at `stage == 5`
(the reference fades out its busy indicator here; Atlas locks its reticle
corner-brackets closed and finishes the hairline progress fill).

Visual: deep navy gradient (`#0d1420` → `#0a0e14`) + the same faint grid
`Canvas` used on the lock screen; the Orbital-A identity mark centered
(`images/atlas-mark.png`, async `Image`, sized via `Kirigami.Units.gridUnit`
like the reference's own logo sizing); the `#57e5ff` live node riding the
edge of a thin hairline progress fill tied to `stage`; four reticle
corner-brackets around the mark that lock closed at `stage == 5`, echoing
both the lock-screen HUD's reticle reveal and the Plymouth boot ignition's
bracket lock-on — so boot → splash → desktop reads as one continuous
instrument power-on. Restraint matches the brief: the splash is on screen for
roughly a second, so there is no heavy animation — one fade-in, one bracket
lock, one progress fill. Fonts: Inter (via `Kirigami.Units`-scaled default
text sizing; the splash carries no body text, only the mark and the
progress hairline, so no explicit `font.family` is needed here beyond what
the reference already inherits). Colors are the Atlas HUD tokens
(`modules/desktop/identity/tokens.env`), inlined since QML cannot source a
shell env file — the same discipline `LockScreenUi.qml` documents.

## 4. Safety, verification, and revert

**Honest limitation:** the build machine has no `qmllint`/`qml6`/
`ksplashqml`, so the QML **could not be validated or rendered offline** — the
same limitation `desktop/lockscreen`'s QML shipped under (see its README's
honesty note). The stage contract was copied structurally from the real
breeze reference rather than freehanded, to minimize the risk of a
KSplash-incompatible theme.

- A KSplash theme that fails to load or errors falls back to the system's
  default splash theme (`ksplashqml`'s own behavior) — a broken Atlas splash
  degrades the *splash* only, for one screen, for about a second. It never
  blocks or delays startup, and it cannot lock the user out (login and the
  lock screen are untouched by this module).
- **Revert:** `atlas deactivate desktop/ksplash` restores the prior theme.
  Manual escape:
  `kwriteconfig6 --file ksplashrc --group KSplash --key Theme --delete ""`
  and log in again.
- Activation is never part of a default `atlas activate` sweep — it is an
  explicit, named, opt-in step, best verified by a login (or
  `ksplashqml org.atlas.hud --test` if available) before being trusted.

## 5. Testing

Two new hermetic test files (mocking `kreadconfig6`/`kwriteconfig6` over a
temp store, exactly as `tests/test_activation_lockscreen.sh` does):

- `tests/test_module_ksplash.sh` — the thin install/check/verify/update
  contract (fails before the splash package exists, passes once it does),
  remove/backup/restore no-ops, and the `MODULE_DEPENDS=(desktop/lockscreen)`
  declaration.
- `tests/test_activation_ksplash.sh` — the full RFC-0029 activation contract
  against `ksplashrc [KSplash] Theme`: records prior, idempotent, restores
  exactly, refuse-to-clobber (both directions), absent-key sentinel +
  delete-on-restore, interrupted-activate write-once, interrupted-deactivate
  finalize, prior-write-failure leaves state unchanged, disown then fresh
  prior, and the strict marker parser's rejections — plus one case unique to
  this module: `activate` refuses when the resolved `Engine` is not
  `KSplashQML`.

`tests/test_module_lockscreen.sh` gained one assertion that `Splash.qml` and
`images/atlas-mark.png` are present after install. `tests/test_modules.sh`'s
fixed discovered-module list was updated from twenty-eight to twenty-nine
modules to include `desktop/ksplash`.

Full suite: `bash tests/run.sh` — 1179 passed, 0 failed among all
KSplash/lockscreen-related tests (the suite's 2 pre-existing failures belong
to an unrelated, already-in-flight `desktop/login-canvas` module left in the
working tree by other work; untouched by and out of scope for this RFC).

## 6. Decision required

1. Accept adding `contents/splash/Splash.qml` (+ a rasterized identity mark)
   to the existing `org.atlas.hud` look-and-feel package, installed by
   `desktop/lockscreen` with no changes to its install/manifest logic.
2. Accept `desktop/ksplash` as a new, dependency-only, activation-focused
   module (`MODULE_DEPENDS=(desktop/lockscreen)`) whose install/check/verify
   are thin presence checks against the package `desktop/lockscreen` owns.
3. Accept the RFC-0029 activation of `ksplashrc [KSplash] Theme`
   (record-prior / restore-verbatim), applied at next login/startup, never
   automatic, with `Engine` checked defensively but not managed by Atlas.
4. Accept that the QML is verified by structural fidelity to the real breeze
   KSplash reference plus a safe, reversible fallback (no offline renderer
   available), matching the precedent already accepted for
   `desktop/lockscreen` in RFC-0035.
