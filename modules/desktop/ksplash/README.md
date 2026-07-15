# desktop/ksplash

Activates the Atlas KSplash startup theme — the splash shown between login and
the desktop appearing. Atlas does not ship a separate KSplash package:
`org.atlas.hud` (installed at
`$XDG_DATA_HOME/plasma/look-and-feel/org.atlas.hud/` by `desktop/lockscreen`)
already carries a `contents/splash/Splash.qml`, so `desktop/ksplash` depends on
`desktop/lockscreen` and is **activation-only** — `install`/`check`/`verify`
just confirm the splash file that ships with that package is present.

## Activating

`atlas activate desktop/ksplash` reversibly switches
`ksplashrc [KSplash] Theme` to `org.atlas.hud`, recording whatever theme was
active before (write-once escrow, per RFC-0029 — same pattern
`desktop/lockscreen` uses for `kscreenlockerrc [Greeter] Theme`). The new
theme takes effect at the **next login/startup**, not live — `ksplashqml`
reads `Theme` only when it spawns between login and the desktop appearing.

`Engine` is not managed by Atlas: on this Plasma 6.7 install,
`Engine=KSplashQML` is already the effective default via the `kdedefaults`
cascade written by the active look-and-feel package, confirmed with
`kreadconfig6 --file ksplashrc --group KSplash --key Engine`. `activate`
checks the resolved `Engine` value and refuses (with guidance) rather than
silently activating a QML theme that would never run if a future environment
resolves something other than `KSplashQML`.

## Reverting

- `atlas deactivate desktop/ksplash` restores the prior theme exactly (or
  removes the `Theme` key if none was set before).
- Manual escape: run
  `kwriteconfig6 --file ksplashrc --group KSplash --key Theme --delete` and
  log in again. With no `Theme` key, `ksplashqml` falls back to its default
  splash theme — a broken or unavailable Atlas QML never blocks startup, it
  just falls back to the system default splash.

## Honesty note on verification

`Splash.qml` was written directly against the real KSplash reference theme
shipped with this system
(`/usr/share/plasma/look-and-feel/org.kde.breeze.desktop/contents/splash/Splash.qml`)
— the stage contract (`property int stage`, the `onStageChanged` reactions at
stages 2 and 5) is copied structurally from that reference. There is no
`qmllint`/`qml6`/`ksplashqml` available in the environment that built this
module, so the QML could **not** be executed or type-checked before shipping.
Treat the first real login as the actual test; a bad theme falls back to the
default KSplash theme and never blocks startup, so this is safe to try live.

See `docs/rfcs/RFC-0037-ksplash.md` for the full design and testing rationale.
