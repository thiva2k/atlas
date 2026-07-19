# desktop/hyprland

The Atlas Hyprland desktop — a full B&W word-only Wayland session that runs
**alongside** Plasma (pick it at the SDDM login), built to unseal the surfaces
Plasma 6.7 locks down (chiefly the lock screen). See
`docs/superpowers/specs/2026-07-16-atlas-hyprland-desktop-design.md`.

## Shipped via a local aquamarine rebuild (2026-07-19)

Fedora 44 bumped `libdisplay-info` 0.2 → 0.3 (`.so.2` → `.so.3`), and the COPR's
`aquamarine-0.9.5-2` was still built against the old `.so.2`, so stock Hyprland
would not install. Rather than wait for the upstream rebuild, Atlas ships a local
rebuild of the **same** aquamarine 0.9.5 against `.so.3`, released as
`0.9.5-2.fc44.atlas1`. It installs now and — because `2.fc44.atlas1` sorts below the
future official `-3` — a routine `dnf upgrade` silently hands off to the official
package when it lands. Nothing to do when that happens; `assets/watch-availability.sh`
notices the `.atlas1` release disappear and says so.

- Build the renderer: `bash modules/desktop/hyprland/build/build-aquamarine.sh`
- Install everything (reversible module): `atlas install desktop/hyprland`
- Full runbook: `docs/superpowers/plans/2026-07-19-hyprland-source-build.md`

## Layout

- `config/hypr/` — hyprland.conf (compositor), hyprlock.conf (lock),
  hypridle.conf (idle→lock), hyprpaper.conf (wallpaper)
- `config/waybar/`, `config/wofi/`, `config/mako/`, `config/kitty/` — bar,
  launcher, notifications, terminal
- `assets/generate.sh` — bakes the two B&W masthead PNGs (lock background +
  desktop wallpaper) to `~/.local/share/backgrounds/atlas/`

## Status

Configs are the source of truth here and are deployed via the reversible
`module.sh` (local aquamarine build + package install + config deploy +
wallpaper generation + supersession watcher activation, with
check/install/verify/update/remove hooks). Install it with
`atlas install desktop/hyprland`; `module::remove` detaches the configs and
watcher but leaves the packages in place (roll back with `dnf history undo`).

## Install

Hyprland comes from COPR `solopasha/hyprland` (not Fedora base). As of
2026-07-16 the COPR's `aquamarine` was stale against Fedora 44's
`libdisplay-info 0.3` — see the spec §7 — so Atlas builds and ships a local
`0.9.5-2.fc44.atlas1` rebuild instead of the stock package:

```
sudo dnf copr enable -y solopasha/hyprland
bash modules/desktop/hyprland/build/build-aquamarine.sh    # rebuild aquamarine against .so.3
atlas install desktop/hyprland                              # configs, wallpapers, watcher
```

Then log out → pick "Hyprland" at the Atlas login. Plasma stays as fallback.
