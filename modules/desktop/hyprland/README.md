# desktop/hyprland

The Atlas Hyprland desktop — a dual-session Wayland compositor that runs
**alongside** Plasma (pick it at the SDDM login). Unseals the lock-screen and
chrome surfaces Plasma 6.7 seals. Normative contract: **RFC-0038**. Design:
`docs/superpowers/specs/2026-07-16-atlas-hyprland-desktop-design.md` and
`docs/superpowers/specs/2026-07-19-hyprland-source-build-design.md`.

## Status — shipped via local aquamarine rebuild

Fedora 44 bumped `libdisplay-info` 0.2 → 0.3 before COPR `solopasha/hyprland`
rebuilt `aquamarine`. Atlas unblocks with a gated local rebuild:

- **Version pinned:** `aquamarine` **0.9.5** (provides `libaquamarine.so.8`)
- **Release:** `2%{?dist}.atlas1` → `2.fc44.atlas1` (sorts above broken `-2`,
  below future official `-3`, so a routine `dnf upgrade` auto-supersedes)
- **Gate:** requires `libdisplay-info.so.3`, never `.so.2`, provides `.so.8`
- **Build:** `build/build-aquamarine.sh` (mock-first, rpmbuild fallback)

Kitty chrome follows a Windows Terminal / PowerShell look: pure black host,
Campbell ANSI palette, blinking beam (pipe) cursor.

## Owns / does not own

**Owns:** COPR `solopasha/hyprland` intent; local `aquamarine-*.atlas1` while
needed; fixed package set (hyprland, portals, hyprlock/idle/paper, waybar,
wofi, mako, kitty, grim, slurp, brightnessctl, playerctl); config trees
`~/.config/{hypr,waybar,wofi,mako,kitty}`; wallpapers `atlas-lock-bg.png` and
`atlas-wall-bw.png`; recorded `dnf history` id; watcher disposition.

**Does not own:** Plasma, user shell, unrelated themes, or package removal on
detach (`remove` = detach only).

## Lifecycle

| Hook | Behavior |
|------|----------|
| `check` | marker `installed` + packages + configs + wallpapers match |
| `install` | Fedora 44 gate → adopt/refuse → build RPM → additive rehearsal → one dnf txn → deploy → bake → `installed` |
| `verify` | absent/detached OK; installing fails; installed fails only on drift/missing |
| `update` | re-deploy configs/wallpapers; never re-runs package txn |
| `remove` | detach if no drift; never `dnf remove`; prints `dnf history undo <id>` |
| `backup` / `restore` | documented no-ops (reconstructable) |

Adoption: byte-identical pre-staged config trees are adopted without rewrite;
differing unmanaged trees refuse **before** any package mutation.

## Layout

- `module.sh` — RFC-0038 lifecycle
- `build/build-aquamarine.sh` — gated local rebuild helper
- `config/hypr/` — compositor, hyprlock, hypridle, hyprpaper
- `config/waybar|wofi|mako|kitty/` — bar, launcher, notifications, terminal
- `assets/generate.sh` — wallpaper bake
- `assets/watch-availability.sh` — pre-install COPR readiness; post-install
  `.atlas1` supersession watch

## Install

```bash
# From a managed Atlas checkout on Fedora 44:
./atlasctl install desktop/hyprland

# Or build the RPM alone first:
bash modules/desktop/hyprland/build/build-aquamarine.sh
```

Then log out → pick **Hyprland** at the Atlas SDDM greeter. Plasma stays the
fallback forever. Package rollback from a TTY:

```bash
sudo dnf history undo "$(cat ~/.local/state/atlas/hypr-install-txn)"
```
