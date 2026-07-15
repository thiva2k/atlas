# Atlas RFCs

Design decisions for Atlas are proposed and recorded here as numbered RFCs
("Request for Comments"). An RFC is written **before** the code it describes.

Atlas v1.0 froze the architecture (`docs/architecture.md`). From v1.1 onward,
every module — and any change that affects the module contract, the engine, or a
cross-cutting convention — starts as an RFC so the design is reviewed once, in
writing, before implementation.

## Process

1. **Draft.** Author writes `RFC-NNNN-<slug>.md` (copy the shape of RFC-0001).
   Status: `Proposed`.
2. **Review.** The maintainer reviews the design and the "Decisions requiring
   approval" section. Amendments happen in the RFC, not in code.
3. **Accept.** On approval the status becomes `Accepted` and the RFC is merged.
   Only then does implementation begin (its own branch / commit series / review).
4. **Supersede.** An RFC is never rewritten after acceptance; a later RFC
   supersedes it and links back.

## Status values

`Proposed` → under review · `Accepted` → approved, implement · `Implemented` →
shipped · `Superseded by RFC-NNNN` · `Rejected`.

## Index

| RFC | Title | Status |
|-----|-------|--------|
| [0001](RFC-0001-git-module.md) | Git module (reference implementation) | Accepted |
| [0002](RFC-0002-remove-verb.md) | Platform verb: `remove` | Proposed |
| [0003](RFC-0003-github-cli-module.md) | GitHub CLI module — credentials & unattended auth | Accepted |
| [0004](RFC-0004-ssh-module.md) | SSH module — persistent state, ownership & the backup contract | Accepted |
| [0005](RFC-0005-docker-module.md) | Docker module — container infrastructure ownership boundary | Accepted |
| [0006](RFC-0006-python-module.md) | Python module — Fedora-packaged language runtime | Accepted |
| [0007](RFC-0007-ghostty-module.md) | Ghostty module — developer desktop application lifecycle | Accepted |
| [0008](RFC-0008-fonts-module.md) | Fonts module — typography foundation for the experience layer | Accepted |
| [0009](RFC-0009-uv-module.md) | uv module — Fedora-packaged Python package manager CLI | Accepted |
| [0010](RFC-0010-fastfetch-module.md) | Fastfetch module — workstation identity | Accepted |
| [0011](RFC-0011-starship-module.md) | Starship prompt theme module | Accepted |
| [0012](RFC-0012-kde-profile-module.md) | KDE workstation profile module | Accepted |
| [0013](RFC-0013-node-module.md) | Node.js module — Fedora-packaged JavaScript runtime | Accepted |
| [0014](RFC-0014-fish-module.md) | Fish module — shell installation and isolated config contract | Accepted |
| [0015](RFC-0015-pnpm-module.md) | pnpm module — Fedora-packaged JavaScript package-manager CLI | Accepted |
| [0016](RFC-0016-claude-module.md) | Claude Code module — signed RPM package boundary for AI coding CLI | Accepted |
| [0017](RFC-0017-theme-module.md) | Atlas theme module | Accepted |
| [0018](RFC-0018-icons-module.md) | Icons module | Accepted |
| [0019](RFC-0019-cursor-module.md) | Cursor module | Accepted |
| [0020](RFC-0020-utilities-module.md) | Engineering utilities module | Accepted |
| [0021](RFC-0021-wallpapers-module.md) | Wallpapers module | Accepted |
| [0022](RFC-0022-power-module.md) | Power module | Accepted |
| [0023](RFC-0023-notifications-module.md) | Notifications module | Accepted |
| [0024](RFC-0024-plymouth-module.md) | Plymouth module | Accepted |
| [0024a](RFC-0024a-plymouth-plugin-dependency.md) | Plymouth — script-plugin dependency (amends 0024) | Accepted |
| [0024b](RFC-0024b-plymouth-passphrase-prompt.md) | Plymouth — LUKS passphrase prompt (amends 0024) | Proposed |
| [0024c](RFC-0024c-plymouth-visual-redesign.md) | Plymouth — HUD boot-ignition redesign (amends 0024) | Proposed |
| [0025](RFC-0025-sddm-module.md) | SDDM module | Accepted |
| [0026](RFC-0026-codex-module.md) | Codex module — npm-packaged AI coding CLI lifecycle | Accepted |
| [0027](RFC-0027-atlas-self-management.md) | Atlas self-management and self-update command | Accepted |
| [0028](RFC-0028-rpm-query-cache.md) | RPM query cache — engine `os::pkg_*` helpers | Accepted |
| [0029](RFC-0029-activation-framework.md) | Activation framework — `activate`/`deactivate`, `desktop/theme` reference | Accepted |
| [0030](RFC-0030-kde-look-activation.md) | KDE look activation — icons/cursor/fonts (reuses 0029) | Accepted |
| [0031](RFC-0031-starship-prompt-activation.md) | Starship prompt activation — reversible fish conf.d wiring | Accepted |
| [0032](RFC-0032-plymouth-boot-activation.md) | Plymouth boot-splash activation — default theme + initramfs | Accepted |
| [0033](RFC-0033-wallpaper-activation.md) | Wallpaper activation — per-containment, discovery-based (reuses 0029) | Accepted |
| [0034](RFC-0034-atlas-hud-identity-terminal.md) | Atlas HUD — identity (`desktop/identity`) + terminal; fish/fastfetch in-place-upgrade fix | Accepted |
| [0035](RFC-0035-lockscreen-hud.md) | Lock-screen HUD — `desktop/lockscreen` LnF package + reversible activation | Accepted |
