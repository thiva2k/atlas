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
- **Gate:** exact NEVRA `aquamarine-0.9.5-2.fc44.atlas1.x86_64`, requires
  `libdisplay-info.so.3`, never `.so.2`, provides `libaquamarine.so.8`, and
  passes `rpm -K` integrity — re-validated on every use, never trusted by name
- **Build:** `build/build-aquamarine.sh` — **mock only** (disposable chroot; no
  host build dependencies, no second host transaction). Host `rpmbuild` is used
  only to re-roll the source RPM; there is no host binary-rebuild fallback

Kitty aims at **Windows Terminal UX**, not a generic dark theme: pure black
host (`#000000`), Microsoft Campbell ANSI palette, selection `#264F78`, and a
**thin blinking vertical bar cursor** (`cursor_shape beam`, thickness `1.0`) —
never a block. Font prefers Cascadia Mono (WT default) with JetBrainsMono as
fallback.

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
| `check` | marker `installed` + hyprland/aquamarine present + configs + wallpapers + recorded txn + watcher all healthy |
| `install` | Fedora 44 gate → adopt/refuse → COPR → gate RPM → additive rehearsal → **one** dnf txn (before/after history boundary) → record+validate txn id → deploy configs/wallpapers → deploy watcher → re-verify → `installed` |
| `verify` | absent/detached OK; installing fails; installed fails only on config/wallpaper drift, a missing/unrelated recorded txn, a missing hyprland/aquamarine, or an unhealthy watcher |
| `update` | re-deploy configs/wallpapers; never re-runs package txn |
| `remove` | detach if no drift; never `dnf remove`; undeploys only Atlas-owned watcher files; prints `dnf history undo <id>` |
| `backup` / `restore` | documented no-ops (reconstructable) |

**Adoption:** byte-identical pre-staged config trees are adopted without
rewrite; differing unmanaged trees refuse **before** any package mutation.

**Reconciliation:** an interrupted install leaves the marker at `installing`
and persists on failure. A later `install` re-evaluates ownership, skips every
already-completed phase, and never runs a second `dnf` transaction once the
packages are installed. A fresh-mode deploy never `rm -rf`s a tree that is not
absent or byte-identical; it fails loudly if the filesystem raced preflight.

**Rollback identity:** the recorded transaction is captured with a before/after
`dnf history` boundary and validated (`dnf history info`) to actually install
`aquamarine`+`hyprland`, written atomically at mode `600` — so a stale, no-op,
or unrelated global transaction can never be mistaken for this install.

## Layout

- `module.sh` — RFC-0038 lifecycle
- `build/build-aquamarine.sh` — gated local rebuild helper
- `config/hypr/` — compositor, hyprlock, hypridle, hyprpaper
- `config/waybar|wofi|mako|kitty/` — bar, launcher, notifications, terminal
- `assets/generate.sh` — wallpaper bake
- `assets/watch-availability.sh` — post-install `.atlas1` supersession watch
  (notifies once when an official rebuild replaces the local build, then
  self-disables its timer; no pre-install COPR polling)

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
