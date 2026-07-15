# RFC-0036: Login Canvas — Atlas wallpaper for the plasma-login-greeter

Status: Accepted

Date: 2026-07-15

Extends: RFC-0029 (Activation framework), RFC-0034 (Atlas HUD identity)

## 1. Summary

The display manager is `plasma-login-manager` (binary `/usr/bin/plasmalogin`,
greeter `/usr/libexec/plasma-login-greeter`). Its greeter UI is **compiled-in and
not themeable** — there is no drop-in QML theme mechanism like SDDM's. The only
Atlas-brandable surface is the **wallpaper** the greeter renders behind the stock
login box, via a `WallpaperPluginId` setting (default `org.kde.image`).

This RFC adds a new module, `desktop/login-canvas`, that:

- Ships a premium Atlas-branded static wallpaper (the orbit/armillary scene, deep
  navy, weighted away from where the greeter centers its password box).
- Adds a reversible, opt-in RFC-0029 activation that switches the greeter's
  **system-scoped** wallpaper config (`/etc/plasmalogin.conf`) to the Atlas image,
  recording the exact prior so it can be restored verbatim.

No display-manager change. No change to greeter behaviour beyond the background
image. The greeter wallpaper is purely cosmetic: a bad, missing, or unreadable
value falls back to the `org.kde.image` plugin's own built-in default — it can
never block login.

## 2. Research: the greeter wallpaper config mechanism

The mechanism is not documented anywhere upstream; it was determined by
inspecting the installed packages and binaries on a live Fedora KDE box running
`plasma-login-manager` (`kde-settings-plasmalogin`, `kcm-plasmalogin`).

**Package layout** (`rpm -ql plasma-login-manager`):

```
/etc/plasmalogin.conf              # the ONE system config file
/etc/plasmalogin.conf.d/           # drop-in directory (also honoured)
/usr/libexec/plasma-login-greeter  # the compiled QML greeter (not themeable)
/usr/bin/plasma-login-wallpaper    # the wallpaper renderer process the greeter spawns
```

**Package layout** (`rpm -ql kcm-plasmalogin`, the System Settings module for
Login Screen):

```
/usr/lib64/qt6/plugins/plasma/kcms/systemsettings/kcm_plasmalogin.so
/usr/libexec/kf6/kauth/kcmplasmalogin_authhelper   # polkit-gated root D-Bus helper
```

`strings` on `plasma-login-greeter` and `plasma-login-wallpaper` surfaced the
property names directly:

```
wallpaperPluginId / WallpaperPluginId / WallpaperPluginIdChanged
defaultWallpaperPluginId / defaultWallpaperPluginIdValue
isWallpaperPluginIdImmutable
org.kde.image            # the compiled-in default plugin id
```

`strings` on `kcm_plasmalogin.so` (the QML/C++ System Settings module) resolved
**where** that setting lives — the QML for the KCM's wallpaper-type picker binds:

```qml
settingName: "WallpaperPluginId"
```

against a `KConfig`-backed settings group named literally `"Greeter"`, and the
strings table contains exactly one config path anywhere in the KCM or its
polkit-gated write helper:

```
/plasmalogin.conf
```

(`strings` on `kcmplasmalogin_authhelper`, the root D-Bus helper the KCM uses for
every privileged write, contains **only** `/etc/plasmalogin.conf` — confirming
there is no second candidate file.) So:

```
/etc/plasmalogin.conf
  [Greeter]
  WallpaperPluginId=org.kde.image
```

The KCM additionally exposes a `wallpaperConfigFile` property (a `QUrl`, resolved
at runtime in C++, not a QML string constant) that feeds the wallpaper plugin's
*own* config editor (`WallpaperConfig { sourceFile: kcm.wallpaperConfigFile }`).
The `org.kde.image` plugin's schema — `/usr/share/plasma/wallpapers/org.kde.image/
contents/config/main.xml` — is shared verbatim with the ordinary desktop
wallpaper engine and defines a `General/Image` string entry (plus `Color`,
`FillMode`, etc.), identical to the schema RFC-0033 already used for the desktop
wallpaper (`plasma-org.kde.plasma.desktop-appletsrc`
`[Containments][C][Wallpaper][org.kde.image][General] Image=`). Applying the same
nested-KConfig-group convention with `Greeter` as the outer group in place of a
containment id gives:

```
/etc/plasmalogin.conf
  [Greeter]
  WallpaperPluginId=org.kde.image

  [Greeter][Wallpaper][org.kde.image][General]
  Image=file:///path/to/atlas-login-canvas.png
```

**This was verified experimentally**, not just inferred from strings: writing
both keys with `kwriteconfig6 --file <tmp> --group Greeter --key
WallpaperPluginId --type string org.kde.image` and `kwriteconfig6 --file <tmp>
--group Greeter --group Wallpaper --group org.kde.image --group General --key
Image --type string file:///…` (both tools support repeated `--group` for nested
groups) and reading them back with the matching `kreadconfig6` invocations
round-trips exactly, producing:

```ini
[Greeter]
WallpaperPluginId=org.kde.image

[Greeter][Wallpaper][org.kde.image][General]
Image=file:///usr/share/backgrounds/atlas/atlas-login.png
```

which is a syntactically ordinary nested-group KConfig ini — exactly the shape
`kreadconfig6`/`kwriteconfig6` (and the greeter, which uses `KConfig` under the
hood) already understand.

**Conclusion**: the config mechanism **is** reliably scriptable. File
`/etc/plasmalogin.conf`, group `Greeter`, key `WallpaperPluginId` (string,
`org.kde.image`); nested group `Greeter → Wallpaper → org.kde.image → General`,
key `Image` (string, a `file://` URL). No GUI, no D-Bus call, and no
`kcmplasmalogin_authhelper` round-trip is required — `kwriteconfig6` against the
plain file is sufficient and is exactly what the polkit-gated helper itself
would do on Atlas's behalf if it were used instead. Because the file lives under
`/etc`, writing it requires root, handled the same way `desktop/sddm` and
`desktop/plymouth` already do (`_run_privileged`: root direct, otherwise `sudo`).

The greeter reads this file when `plasma-login-wallpaper` spawns for a fresh
login screen — **not live**. Activation and deactivation both apply at the next
login screen, never mid-session, matching every other Atlas activation that
touches a compiled/spawned surface (RFC-0032 Plymouth, RFC-0035 lock screen).

## 3. What is delivered

- **A wallpaper asset**, built from `modules/desktop/identity/assets/atlas-mark.svg`
  (the Orbital-A monogram) and `modules/desktop/wallpapers/assets/atlas-orbit.svg`
  (the armillary/orbit motif) as starting points, composed fresh as
  `modules/desktop/login-canvas/assets/atlas-login-canvas.svg` and rasterized with
  ImageMagick to a crisp `atlas-login-canvas.png` at **2560×1440**. Palette from
  `desktop/identity/tokens.env` (RFC-0034): deep-navy ground
  `#0d1420 → #0b121c → #0a0e14`, a faint `#5aa2ff` grid fading toward the bottom,
  large armillary/orbit rings in `#5aa2ff`, one bright `#57e5ff`/white live node,
  and the Orbital-A mark rendered small and quiet in a corner (not centered — it
  is a signature, not a logo splash). The composition is weighted into the
  upper-right quadrant; a radial vignette darkens and flattens the lower-center
  third, where `plasma-login-greeter` centers its password box, so the stock login
  UI stays legible over it at every screen size.
- **`modules/desktop/login-canvas/module.sh`** — install/check/verify/update/
  remove with the standard Atlas discipline: mode-600 marker, refuse-unmanaged
  preflight, atomic staged writes, and the **in-place-upgrade-safe** marker
  pattern (marker_load validates only its own structure — schema/state — and
  never encodes or checks the shipped asset's content hash; content drift is
  judged separately, only by `_login_canvas_asset_matches`, from
  `check`/`verify`/`update`). This is the same discipline `desktop/theme`,
  `desktop/wallpapers`, and `desktop/lockscreen` use, and deliberately avoids
  reintroducing the fish/fastfetch marker bug fixed in RFC-0034 (a marker that
  hard-fails load because a *new Atlas release* changed the source bytes it had
  pinned). The asset installs **user-scope**, no root:
  `${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/atlas/atlas-login-canvas.png`.
- **Reversible activation** (`module::activate`/`module::deactivate`), reusing the
  RFC-0029 escrow **exactly** as `desktop/theme` does (transitional `activating`
  state, write-once prior, refuse-to-clobber, absent-key sentinel + delete-on-
  restore, already-restored finalize on deactivate) — extended from one scalar
  key to **two**, `WallpaperPluginId` and `Image`, both captured and restored
  together as a single atomic escrow record (§4). Because the switched file is
  system-scoped (`/etc/plasmalogin.conf`), both verbs require privilege and go
  through `_login_canvas_run_privileged`, the same root-or-`sudo` wrapper
  `desktop/sddm`/`desktop/plymouth` use. Activation prints that it applies at the
  next login screen.

## 4. The activation contract

### 4.1 State file

Per RFC-0029 §5.2, separate from the install marker:

```
$ATLAS_STATE_DIR/activated/desktop-login-canvas
  schema=1
  state=activating | active | inactive
  prior_plugin=<verbatim WallpaperPluginId value> | __ATLAS_ABSENT__   # iff activating|active
  prior_image=<verbatim Image value>              | __ATLAS_ABSENT__   # iff activating|active
```

Mode 600, atomic write (`mktemp` in-dir + `mv -f`), strict line parser: rejects
unknown keys, unknown `state`/`schema` values, `prior_*` present under
`state=inactive`, or missing/empty `prior_*` under `activating`/`active`. Both
keys are captured and restored **together**, as one escrow — there is no
partial-key state, because the two settings are meaningless independently (a
`WallpaperPluginId` with no matching `Image` just falls back to the plugin's
default, and vice versa).

### 4.2 `module::activate`

1. **Preconditions.** Install marker `installed`; `kreadconfig6` and
   `kwriteconfig6` present; root or non-interactive `sudo -n` available (checked
   *before* any state is written — a no-privilege environment fails cleanly with
   the `sudo atlas activate desktop/login-canvas` guidance, mirroring
   `desktop/plymouth`'s `_plymouth_privilege_ok`/`_plymouth_sudo_guidance`).
2. **Load activation state.** Read current `WallpaperPluginId` and `Image` (each
   with the absent sentinel as the `kreadconfig6 --default`), through the
   privileged wrapper.
3. **Already active:** if both the current plugin is `org.kde.image` and the
   current image (normalized: strip a leading `file://`) equals the Atlas asset
   path → no-op success. If either differs → refuse-to-clobber: report and stop,
   naming the current plugin/image and the disown path (delete the `activated/`
   file).
4. **Record prior write-once.** If an interrupted `activating` record already
   holds `prior_plugin`/`prior_image`, reuse them unchanged (never re-read the
   current — now possibly Atlas — values into the escrow). Otherwise capture the
   current plugin and image (or the absent sentinel for each) and write
   `{schema=1, state=activating, prior_plugin=…, prior_image=…}` atomically
   **before** applying.
5. **Apply.** `kwriteconfig6` the plugin to `org.kde.image`, then the image to
   `file://<Atlas asset path>`, both through the privileged wrapper. On success,
   write `{schema=1, state=active, prior_plugin=…, prior_image=…}` (same
   recorded priors).

The transitional `activating` state makes recording write-once exactly as in
`desktop/theme`: a crash or failure between recording and `state=active` leaves
the true prior preserved; a re-run reuses it and never launders the Atlas value
into the escrow.

### 4.3 `module::deactivate`

1. Load activation state. No record, or `state=inactive` → nothing to do.
2. Require the tool and privilege (restore is also a privileged write).
3. Read current plugin/image. If `state=active` and the current value is **not**
   the Atlas image:
   - if it equals the recorded prior (plugin and image both) →
     **already-restored finalize**: the restore already landed and only the
     state write was lost; write `state=inactive`, drop `prior_*`, succeed.
   - otherwise → **refuse-to-clobber**: report and stop, naming the disown path.
4. Restore the recorded prior: for each of `prior_plugin`/`prior_image`, delete
   the key if the sentinel was recorded, else `kwriteconfig6` it back verbatim.
   Any failure reports clearly and leaves state unchanged (no silent clear).
5. Write `{schema=1, state=inactive}` with no `prior_*` — escrow consumed.

### 4.4 Session dependency and safety

`plasma-login-greeter` reads `/etc/plasmalogin.conf` only when it spawns a fresh
login screen (via `plasma-login-wallpaper`) — there is no live-apply path and
none is claimed; both verbs report "applies at next login screen." Recording and
restoring never require a running greeter session, only `kreadconfig6`/
`kwriteconfig6` and root.

**This can never break login.** The switched keys are read exclusively by the
wallpaper renderer, a separate process from the authentication path
(`plasmalogin-helper`, PAM, the greeter's session logic). If `/etc/plasmalogin.conf`
is missing, malformed in a way `KConfig` tolerates, or names a plugin/image that
fails to load, `plasma-login-wallpaper` falls back to the `org.kde.image`
plugin's own built-in default (`isWallpaperPluginIdImmutable`/
`defaultWallpaperPluginIdValue` exist precisely for this fallback) — the login
box, PAM prompt, and session picker are unaffected either way. Atlas never
touches any other section of `plasmalogin.conf` (`[Autologin]`, `[Users]`,
`[Wayland]`, `[X11]`), so no authentication or session-launch behaviour changes.

## 5. Non-goals

- No display-manager change, no switch away from `plasma-login-manager`.
- No attempt to theme the greeter's compiled UI (login box, avatar, clock) — that
  surface is not exposed by this DM version; only the wallpaper is.
- No live-apply of the greeter wallpaper — the greeter has no running-session
  D-Bus surface analogous to `plasma-apply-wallpaperimage`; "applies at next
  login screen" is the honest, permanent characterization, not a gap to close
  later.
- No use of `kcmplasmalogin_authhelper`/polkit — `kwriteconfig6` against the
  plain file under root/sudo is sufficient and simpler, and does not require
  wiring a D-Bus call into a shell module.

## 6. Testing strategy

`tests/test_module_login_canvas.sh` — install/verify/marker discipline and the
in-place-upgrade path (asset-hash-free marker load; a changed shipped source
doesn't break `marker_load`; `update` re-syncs after a release), mirroring
`test_module_theme.sh`.

`tests/test_activation_login_canvas.sh` — the RFC-0029 activation contract for
the two-key escrow, mirroring `test_activation_lockscreen.sh`/
`test_activation_plymouth.sh`: preconditions (not-installed, tools absent,
no-privilege refuses before any state write), the sudo-wrapper path (mirroring
`test_module_sddm.sh`'s non-root+sudo-mock case) and the direct-root path,
records-prior-and-applies, idempotent re-activate, exact restore, refuse-to-
clobber on both verbs, the absent-key sentinel on both keys, interrupted-activate
write-once, interrupted-deactivate finalize, disown, and the strict marker
parser's rejections. `kreadconfig6`/`kwriteconfig6` are mocked against a flat
key-value file standing in for `/etc/plasmalogin.conf`'s two nested groups.

Both files are hermetic (temp `$HOME`, mocked `sudo`/`kreadconfig6`/
`kwriteconfig6`, no real `/etc` write, no real Fedora check unless
`FEDORA_OK=0` is set to test the refusal path).

`modules/desktop/login-canvas/README.md` was added (the module contract
requires one) and `tests/test_modules.sh`'s fixed discovered-module list was
updated to include `desktop/login-canvas` (twenty-nine → thirty modules,
following the same pattern RFC-0037/`desktop/ksplash` used one module earlier).

`bash tests/run.sh` → **1221 passed, 0 failed** (full suite, including the 17 new
install/marker cases and 20 new activation cases this RFC adds).

## 7. Applying live

Atlas does not run privileged commands or touch `/etc` itself; the advisor
applies. From the repo root:

```
./atlas install desktop/login-canvas      # ships the wallpaper asset, no root
sudo ./atlas activate desktop/login-canvas   # switches /etc/plasmalogin.conf, applies at next login screen
```

To revert:

```
sudo ./atlas deactivate desktop/login-canvas
```

## 8. Decision required

1. Accept `/etc/plasmalogin.conf` `[Greeter] WallpaperPluginId` +
   `[Greeter][Wallpaper][org.kde.image][General] Image` (nested KConfig groups,
   verified experimentally with `kreadconfig6`/`kwriteconfig6`) as the greeter
   wallpaper mechanism, in place of the deferred manual-KCM fallback.
2. Accept the two-key write-once escrow (single atomic record covering both
   `WallpaperPluginId` and `Image` together) as an extension of RFC-0029's
   one-scalar reference, alongside RFC-0033's per-containment extension.
3. Accept the privileged (`_run_privileged`, root-or-sudo) read/write path for
   this system-scoped file, matching `desktop/sddm`/`desktop/plymouth`, and the
   "applies at next login screen" honesty note (no live-apply path exists for the
   greeter).
