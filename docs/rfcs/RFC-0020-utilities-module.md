# RFC-0020: Engineering Utilities Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `desktop/utilities` to install small engineering CLI utilities used by the
workstation experience: `btop`, `bat`, `fd-find`, `ripgrep`, `eza`, and
`zoxide`.

## Ownership

Atlas owns package intent and marker state only. Atlas never edits user utility
configuration, aliases, shell startup files, or shell integration.

## Lifecycle

Install requires Fedora and installs only missing packages. Verify succeeds
before install and after detach; when installed, it verifies all package intents
are present. Remove detaches without uninstalling packages.

Backup and restore are no-ops.

