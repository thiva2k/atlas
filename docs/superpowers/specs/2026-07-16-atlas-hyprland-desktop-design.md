# Atlas on Hyprland — full desktop design

Status: Approved 2026-07-16 (user chose "full build before switching", tiling-first
with full mouse support, recommended stack). Build complete and staged; install
blocked only by an upstream Fedora-44 packaging lag (see §7).

## 1. Why

Plasma 6.7 seals both the login greeter and the lock screen against customization
(login greeter compiled-in; kscreenlocker sources its QML from the Plasma *shell*
package and rejects look-and-feel overrides via `verifyPackageApi` — "Lockscreen
QML outdated, falling back to default"). Login was worked around by swapping to
classic SDDM; the lock screen has no clean in-Plasma escape. Hyprland uses
standalone, fully-configurable parts (hyprlock, waybar, …) — "everything is a
file" — so every surface becomes ours. See memory `atlas-hyprland-pivot`.

## 2. Architecture & safety

Two parallel Wayland sessions sharing one `$HOME`. Plasma is **never removed** and
stays the default session until Hyprland is proven solid; you pick "Hyprland" or
"Plasma (Wayland)" at the Atlas SDDM greeter (its session dropdown lists both
automatically once `hyprland.desktop` is installed). Safety floor: any Hyprland
failure drops back to the greeter → pick Plasma. TTY (Ctrl+Alt+F3) is the hard
floor; **SSH is off**, so every step stays TTY-recoverable.

## 3. Component stack (all B&W word-only, Fable spec — see the config files)

| Surface | Tool | Config |
|---|---|---|
| compositor | hyprland | `config/hypr/hyprland.conf` — tiling + full mouse, 1px hairline borders (active `#f2f2f2` / inactive `#2a2a2a`), 0px rounding, 6/12 gaps, no blur/shadow, <150ms ease-out motion, sane keybinds (`Super+Return` term, `Super+Space`/`D` launcher, `Super+Q` close, `Super+L` lock, workspaces 1-10, `Super+drag` move/resize) |
| lock | hyprlock | `config/hypr/hyprlock.conf` — two-tone ATLAS masthead **baked into the bg PNG** (pixel-perfect), live 128px clock + date + password field; red only on fail/capslock |
| idle | hypridle | `config/hypr/hypridle.conf` — dim 270s → lock 300s → dpms 330s → suspend 1800s; lid/sleep-aware |
| bar | waybar | `config/waybar/{config.jsonc,style.css}` — 28px word-only bar (`cpu`/`mem`/`vol`/`net`/`bat`), no icons, red only on alerts |
| launcher | wofi | `config/wofi/{config,style.css}` — centered 640×400, selection = solid white inversion |
| notifications | mako | `config/mako/config` — top-right, red border only on critical |
| terminal | kitty | `config/kitty/kitty.conf` — B&W chrome, greyscale ANSI ramp + the one red |
| wallpaper | hyprpaper | `config/hypr/hyprpaper.conf` + `assets/generate.sh` bakes `atlas-lock-bg.png` (masthead top) and `atlas-wall-bw.png` (masthead engraved bottom-right) |

Tokens (canonical): bg `#070707`, fg `#f2f2f2`, shadow `#5a5a5a`, dim `#6a6a6a`,
hairline `#2a2a2a`, engrave `#161616`/`#0f0f0f`, alert `#E5484D`. Font everywhere:
JetBrainsMono Nerd Font. 0px radius, flat two-tone ink on black.

Red inventory (five alert-only appearances): hyprlock auth-fail + capslock;
waybar battery ≤10%; waybar `net down`; waybar urgent workspace; mako critical.

## 4. Carries over untouched (DE-agnostic, already shipping)

plymouth (boot), sddm (login), fastfetch (terminal masthead), fonts, cursor,
icons, identity tokens. The Atlas identity at boot/login/terminal is already
B&W-consistent; Hyprland extends it into the live desktop.

## 5. Packaging (the Atlas way)

Configs live in `modules/desktop/hyprland/config/` (source of truth) and are
deployed to `~/.config/` (user scope, no sudo). Wallpapers bake to
`~/.local/share/backgrounds/atlas/` (distinct filenames — the old blue canvases
are left in place for the reconciliation pass, §8). A reversible module.sh
(package install + config deploy + wallpaper gen, check/install/verify/remove)
is a follow-up once the desktop is validated live (§8).

## 6. Install

Hyprland is not in Fedora base repos; it comes from COPR `solopasha/hyprland`.
Install command (when unblocked, §7):

```
sudo dnf copr enable -y solopasha/hyprland
sudo dnf install -y hyprland hyprlock hypridle hyprpaper xdg-desktop-portal-hyprland \
  waybar wofi mako kitty grim slurp brightnessctl playerctl
```

Then log out → pick "Hyprland" at the Atlas login. Plasma stays as fallback.

## 7. Current blocker (upstream, transient)

Fedora 44 bumped `libdisplay-info` 0.2 → 0.3 (`.so.2` → `.so.3`). The COPR's
`aquamarine-0.9.5-2` (Hyprland's renderer) was built against `.so.2` and won't
install until rebuilt. No other repo packages full Hyprland for F44 (Terra and
Fedora base ship only the low-level libs `hyprlang`/`hyprutils`). This is a
Fedora-wide breakage every Hyprland user hits; solopasha rebuilds fast (hours–
days). A compat shim was rejected as unreliable: `libdisplay-info` has no symbol
versioning, so `.so.2`+`.so.3` coexisting in one process can clash at runtime.
The reliable path is to install once the rebuild lands — everything else is done.

## 8. Follow-ups (explicitly deferred)

- Formal RFC amendments recording the B&W word-only supersession of RFC-0034
  (fastfetch orbital-A greeting) and RFC-0037 (lockscreen orbital-A mark). Tests
  updated to match the shipped B&W design; RFC docs not auto-rewritten.
- Reconcile off-identity blue assets Fable flagged: `~/atlas-boot-preview.png`,
  the old `~/.local/share/backgrounds/atlas/atlas-login-canvas.png` + SVGs, and
  the ghostty `atlas-reference` theme (cyan, `#0f141b`).
- Reversible `modules/desktop/hyprland/module.sh` + split into finer modules if
  desired, after the desktop is validated live.
- **Font must be system-wide for greeters.** The SDDM greeter runs as the `sddm`
  system user and cannot read `~/.local/share/fonts`, so the ASCII masthead
  rendered in a fallback font ("crooked"). Fixed 2026-07-16 by installing
  JetBrainsMono Nerd Font to `/usr/share/fonts/atlas-jbm/` — but that was a
  manual step. Bake "ensure the theme font is system-wide" into the SDDM module
  (or the fonts module) so a fresh machine never hits this.
- Retire the vestigial Plasma-only lock module (`org.atlas.hud`) once Hyprland is
  primary (kscreenlockerrc Theme override is inert on Plasma 6.7 anyway).
