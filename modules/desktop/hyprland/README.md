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

Configs are the source of truth here and are currently **deployed directly to
`~/.config/`** (user scope, no root) so the Hyprland session is live-ready. A
reversible `module.sh` (package install + config deploy + wallpaper generation,
check/install/verify/remove) is a follow-up once the desktop is validated live.

## Install

Hyprland comes from COPR `solopasha/hyprland` (not Fedora base). As of 2026-07-16
the COPR's `aquamarine` is stale against Fedora 44's `libdisplay-info 0.3` — see
the spec §7. Once rebuilt:

```
sudo dnf copr enable -y solopasha/hyprland
sudo dnf install -y hyprland hyprlock hypridle hyprpaper xdg-desktop-portal-hyprland \
  waybar wofi mako kitty grim slurp brightnessctl playerctl
bash modules/desktop/hyprland/assets/generate.sh    # (re)bake the wallpapers
```

Then log out → pick "Hyprland" at the Atlas login. Plasma stays as fallback.
