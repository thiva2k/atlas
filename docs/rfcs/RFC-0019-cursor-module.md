# RFC-0019: Cursor Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `desktop/cursor` to install a simple, visible, professional cursor theme
package without changing the user's active cursor preference.

## Ownership

Atlas owns package intent and marker state only. Atlas never edits user cursor
preferences or user cursor themes.

## Lifecycle

Install requires Fedora and installs `adwaita-cursor-theme` only when absent.
Verify succeeds before install and after detach; when installed, it verifies the
package is present. Remove detaches without uninstalling packages.

Backup and restore are no-ops.

