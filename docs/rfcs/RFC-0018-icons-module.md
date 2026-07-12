# RFC-0018: Icons Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `desktop/icons` to install a modern, minimal, professional icon theme
package without changing the user's active icon preference.

## Ownership

Atlas owns package intent and marker state only. Atlas never edits KDE icon
preferences, user icon themes, or user-created icon assets.

## Lifecycle

Install requires Fedora and installs `papirus-icon-theme` only when absent.
Verify succeeds before install and after detach; when installed, it verifies the
package is present. Remove detaches without uninstalling packages.

Backup and restore are no-ops.

