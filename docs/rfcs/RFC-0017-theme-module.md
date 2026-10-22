# RFC-0017: Atlas Theme Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `desktop/theme` to ship the Atlas dark KDE color scheme as an Atlas-owned
asset.

The module installs `Atlas.colors` under the user's XDG data directory. It does
not change the active KDE color scheme, rewrite `kdeglobals`, install third-party
themes, or own user cosmetic preferences.

## Ownership

Atlas owns only:

- `$XDG_DATA_HOME/color-schemes/Atlas.colors`
- `$ATLAS_STATE_DIR/installed/desktop-theme`

If the target color scheme already exists without an Atlas marker, install
refuses instead of adopting it.

## Lifecycle

Install writes an `installing` marker, atomically copies the color scheme, then
promotes the marker to `installed`. Verify succeeds before install and after
detach. Remove deletes only an unchanged Atlas-owned color scheme and writes a
detached marker.

Backup and restore are no-ops because the asset is reconstructable.

## UX Decision

The color scheme is dark, quiet, professional, and uses Atlas blue as the accent.
Activation remains user-owned until a separate explicit preference module exists.

