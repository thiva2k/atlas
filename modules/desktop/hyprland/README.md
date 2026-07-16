# desktop/hyprland

The Atlas Hyprland desktop — a full B&W word-only Wayland session that runs
**alongside** Plasma (pick it at the SDDM login), built to unseal the surfaces
Plasma 6.7 locks down (chiefly the lock screen). See
`docs/superpowers/specs/2026-07-16-atlas-hyprland-desktop-design.md`.

## ⚠ Blocked on a missing dependency (as of 2026-07-16)

**This desktop is fully built and staged, but cannot be installed yet** — not
because of anything here, but an upstream Fedora-44 packaging gap:

- Fedora 44 bumped **`libdisplay-info` 0.2 → 0.3** (`.so.2` → `.so.3`).
- Hyprland's renderer **`aquamarine`** (only packaged in COPR
  `solopasha/hyprland` as `0.9.5-2`) was built against the old `.so.2` and
  **will not install** — dnf reports *"nothing provides libdisplay-info.so.2"*.
- No other repo packages full Hyprland for F44 (Terra and Fedora base ship only
  the low-level libs `hyprlang`/`hyprutils`).
- A compat shim was rejected: `libdisplay-info` has **no symbol versioning**, so
  loading `.so.2` and `.so.3` in one process can clash at runtime.

**Unblocking (either lands it):**
1. **Wait** — solopasha rebuilds `aquamarine` against `.so.3` (a Fedora-wide
   breakage, so this is imminent). A user systemd timer
   (`assets/watch-availability.sh`) checks daily and notifies when it's
   installable, then self-disables.
2. **Build our own** — compile the latest `aquamarine` (which supports
   `libdisplay-info 0.3`) + matching Hyprland from source. Planned for the
   weekend of 2026-07-19.

Everything else (all configs, theming, wallpapers) is done — it's a single
install once the renderer is available.

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
