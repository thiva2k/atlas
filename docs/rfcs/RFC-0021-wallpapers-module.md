# RFC-0021: Wallpapers Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `desktop/wallpapers` to ship a curated Atlas wallpaper collection.

The module installs Atlas-owned SVG wallpapers under the user's XDG data
directory. It does not change the active wallpaper or inspect user wallpaper
settings.

## Ownership

Atlas owns only:

- `$XDG_DATA_HOME/backgrounds/atlas/*.svg`
- `$ATLAS_STATE_DIR/installed/desktop-wallpapers`

If the target directory already exists without an Atlas marker, install refuses
instead of adopting it.

## Lifecycle

Install writes an `installing` marker, atomically refreshes the Atlas wallpaper
directory, then promotes the marker to `installed`. Verify succeeds before
install and after detach. Remove deletes only unchanged Atlas-owned wallpapers.

Backup and restore are no-ops.

