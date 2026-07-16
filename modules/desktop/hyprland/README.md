# desktop/hyprland

The Atlas Hyprland desktop — a full B&W word-only Wayland session that runs
**alongside** Plasma (pick it at the SDDM login), built to unseal the surfaces
Plasma 6.7 locks down (chiefly the lock screen). See
`docs/superpowers/specs/2026-07-16-atlas-hyprland-desktop-design.md`.

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
