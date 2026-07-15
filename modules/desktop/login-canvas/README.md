# desktop/login-canvas

Installs the Atlas login canvas — a premium Atlas-branded wallpaper for the
STOCK `plasma-login-greeter` — at
`$XDG_DATA_HOME/backgrounds/atlas/atlas-login-canvas.png` (user scope, no
root). Installing does **not** change the greeter's wallpaper; Atlas never
touches `/etc/plasmalogin.conf` on `install`.

The `plasma-login-manager` greeter UI is compiled-in and not themeable — the
only Atlas-brandable surface is the wallpaper it renders via its
`WallpaperPluginId` setting (default `org.kde.image`).

## Activating

`atlas activate desktop/login-canvas` reversibly switches the greeter's
wallpaper config in `/etc/plasmalogin.conf`:

- `[Greeter] WallpaperPluginId` → `org.kde.image`
- `[Greeter][Wallpaper][org.kde.image][General] Image` → the Atlas canvas

recording whatever plugin/image were set before (write-once escrow, per
RFC-0029). Because this file is system-scoped, activation requires root —
run with `sudo`, or as root directly:

```
sudo atlas activate desktop/login-canvas
```

The change takes effect at the **next login screen**, not live —
`plasma-login-wallpaper` reads these keys only when it spawns for a fresh
greeter session.

## Reverting

```
sudo atlas deactivate desktop/login-canvas
```

restores the prior plugin/image exactly (or removes the keys if neither was
set before Atlas).

## Safety

The greeter wallpaper is purely cosmetic and read by a separate process from
the authentication path. A missing, malformed, or unreadable value only ever
falls back to the `org.kde.image` plugin's own built-in default — it can
never block login.

See `docs/rfcs/RFC-0036-login-canvas.md` for the full research into the
config mechanism and the activation design.
