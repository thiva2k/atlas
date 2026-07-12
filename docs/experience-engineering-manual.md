# Atlas Experience Engineering Manual

## Part 3 of 4: Identity

Atlas's experience layer is internally known as **Thivarrakesh OS**.

This is not a Linux rice, an anime desktop, an RGB showcase, or KDE
customization for its own sake. It is a workstation for someone who spends
10-16 hours a day writing code, reviewing systems, studying cybersecurity, and
operating infrastructure.

Every pixel exists for a reason.

## Design Philosophy

The workstation must feel like:

- Apple-level polish.
- Linux-level power.
- Enterprise-level reliability.

Everything should communicate:

```text
This machine is built for engineering.
```

## Core Design Principles

Every customization must improve at least one of:

- productivity;
- readability;
- discoverability;
- consistency;
- perceived speed;
- workflow efficiency.

If it improves none of them, do not implement it.

## Visual Philosophy

Target words:

- minimal;
- elegant;
- quiet;
- professional;
- premium;
- modern;
- fast.

Avoid:

- RGB;
- gamer aesthetics;
- neon;
- heavy transparency;
- excessive blur;
- over-animation;
- visual clutter.

## Performance Budget

The experience layer must never noticeably reduce workstation responsiveness.

Animations should feel instant. Windows should feel attached to the cursor. No
animation should exist simply because KDE allows it.

If disabling an effect makes the workstation feel faster, disable it.

## Desktop Stack

The experience track owns, in order:

```text
Ghostty
Fonts
Fastfetch
Icons
Cursor
Theme
Wallpaper
KDE
Notifications
Lock Screen
Plymouth
SDDM
Branding
```

Applications remain outside this track.

The desktop should communicate:

```text
This is an engineer's workstation.
```

not:

```text
Someone discovered KDE themes.
```

## Ghostty

Ghostty is the heart. Everything revolves around it.

Ghostty should feel:

- instant;
- clean;
- distraction-free.

Use `JetBrains Mono Nerd Font`.

Fallbacks:

- `FiraCode Nerd Font`.

Never use decorative fonts. Terminal fonts must optimize code readability.

## Terminal Philosophy

Terminal first. GUI second.

Everything should encourage:

- SSH;
- tmux;
- Git;
- Docker;
- Python;
- Node;
- Claude;
- Codex;
- Atlas.

The terminal is the primary interface.

## Shell

Use Fish.

Do not use:

- Zsh;
- Oh My Zsh;
- Powerlevel10k.

Fish provides:

- clean syntax;
- fast startup;
- excellent completions;
- excellent defaults.

## Prompt

Use Starship.

The prompt should expose only useful information. Recommended modules:

- directory;
- git branch;
- git status;
- Python environment;
- Node version;
- Docker context;
- time;
- command duration;
- Atlas status in the future.

Do not display decorative information.

## Fastfetch

Fastfetch should become the workstation identity, not just system information.

Display:

- Atlas version;
- Fedora version;
- kernel;
- CPU;
- memory;
- GPU;
- shell;
- terminal;
- Git;
- Python;
- Node;
- Docker;
- Claude;
- Codex;
- hostname;
- user;
- theme;
- color palette.

Keep it minimal.

## Fonts

Primary:

- `JetBrains Mono Nerd Font`.

Secondary:

- `Inter`.

System UI should prioritize:

- clarity;
- spacing;
- legibility.

Do not install excessive font collections.

## Icons

Icons should be modern, minimal, and professional.

Avoid:

- cartoon icons;
- skeuomorphism.

Consistency matters more than uniqueness.

## Cursor

The cursor should be simple, high contrast, and easy to locate.

Do not use animated cursors.

## Theme

Dark first.

Accent color:

- Atlas Blue.

Avoid:

- pure black;
- pure white;
- extreme contrast.

Prefer slightly elevated surfaces and reduce eye fatigue.

## Wallpaper

The wallpaper should communicate:

- calm;
- engineering;
- focus.

Avoid:

- gaming;
- anime;
- abstract explosions.

Consider:

- minimal geometry;
- mountains;
- architecture;
- deep blue gradients;
- space;
- technical illustrations.

Atlas branding should remain subtle.

## KDE

Configure KDE for work.

- Disable features that increase latency.
- Simplify context menus.
- Reduce notification noise.
- Optimize window management.
- Enable useful shortcuts.
- Prefer keyboard over mouse.

## Dock and Panel

Use a single top panel.

Do not use:

- a floating dock;
- a macOS clone.

The panel should contain:

- launcher;
- workspaces;
- running apps;
- network;
- Bluetooth;
- battery;
- clock;
- notifications.

Nothing else.

Remove unnecessary widgets.

## Notifications

Notifications should be quiet, minimal, and useful.

- Group notifications.
- Reduce interruptions.
- Silence low-value alerts.

## Sounds

Keep Fedora sounds unless replacement sounds are objectively higher quality.

Avoid novelty sounds.

## Lock Screen

The lock screen should be minimal, readable, professional, and free of visual
clutter.

## Boot Experience

The boot flow should feel coherent:

```text
Plymouth -> Login -> Desktop -> Ghostty
```

It should feel like one operating system, not individual components.

## Branding

Subtly reinforce Atlas through:

- boot splash;
- Fastfetch;
- terminal;
- Ghostty;
- theme;
- documentation.

Branding must not become obnoxious.

## Ownership Rules

Atlas owns:

- Atlas theme;
- Atlas wallpapers;
- Atlas icons;
- Atlas configs;
- Atlas branding.

Atlas never owns:

- user wallpapers;
- user themes;
- user shell customizations;
- user keybindings;
- user desktop layouts;
- user plugins.

The user always wins.
