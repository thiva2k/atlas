# RFC-0012: KDE Workstation Profile Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `desktop/kde-profile` as Atlas's conservative KDE workstation profile.

The module manages a small set of scalar KDE KConfig keys that improve
responsiveness and engineering ergonomics. It does not install KDE Plasma, own
panel layouts, rewrite user shortcuts wholesale, or adopt existing user desktop
configuration.

## Goals

- Reduce distracting or latency-heavy visual behavior.
- Keep focus behavior predictable.
- Prefer inherited working context for terminal-like workflows.
- Record exact Atlas-owned KConfig keys in an install marker.
- Verify only keys Atlas created.
- Preserve user KDE configuration and refuse silent adoption.

## Non-goals

- Installing KDE Plasma packages.
- Replacing user panel layouts.
- Rewriting user-created shortcuts.
- Managing wallpapers, lock screen, SDDM, cursor, icons, power profiles, or
  notifications. Those are separate experience modules.
- Applying opaque Plasma layout scripts.

## Ownership Model

Atlas owns only KConfig keys listed in:

```
modules/desktop/kde-profile/profile.tsv
```

On first install, every managed key must be absent. If any target key already
exists, Atlas refuses to install rather than adopting a user setting.

After install, ownership is determined only by:

```
$ATLAS_STATE_DIR/installed/desktop-kde-profile
```

The marker records the profile source hash. A detached marker means Atlas no
longer asserts the KDE profile.

## Lifecycle

`install` requires Fedora and the KDE KConfig CLIs `kreadconfig6` and
`kwriteconfig6`. It writes an `installing` marker, applies every profile key,
verifies the result, then promotes the marker to `installed`.

`verify` succeeds before install and after detach. It fails only when Atlas owns
the profile and managed keys are missing or drifted.

`update` reapplies the current profile only when Atlas already owns the keys.

`remove` deletes only Atlas-owned keys when their values still match the profile.
If any key drifted, remove refuses so user edits are not destroyed.

`backup` and `restore` are documented no-ops because the profile is
reconstructable and user KDE configuration is not Atlas-owned.

## Profile Keys

The initial profile deliberately manages only low-risk scalar keys:

- lower global animation duration
- predictable click-to-focus behavior
- reduced focus delay
- reduced focus stealing prevention aggressiveness
- disabled blur and novelty KWin effects

Panel layout, context menus, and broad shortcut ownership remain future work
because KDE does not provide an isolated Atlas-owned fragment for those
surfaces. They require a follow-up RFC if Atlas should manage them.

## Architecture Review

Ownership: Per-key ownership avoids treating full KDE config files as
Atlas-owned.

Idempotency: The profile source and marker hash make repeated install and verify
deterministic.

Security: The module does not execute Plasma JavaScript layout scripts, does not
download themes, and does not weaken Fedora defaults.

Maintainability: A TSV profile keeps the managed surface auditable and small.

User control: Any pre-existing key blocks first install, and any drift blocks
remove. User changes therefore win by preventing destructive Atlas repair.

## Validation Matrix

- clean Fedora KDE config
- existing user KDE key
- missing KConfig tools
- unsupported non-Fedora environment
- Atlas-managed install
- repeated install
- repeated verify
- doctor
- status
- update restores managed drift
- remove deletes only managed keys
- remove refuses drifted keys
- detached reinstall refuses user-created keys
- malformed marker
- insecure marker mode
- backup and restore no-ops
- full-suite regression

