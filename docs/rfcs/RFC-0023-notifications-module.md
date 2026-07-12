# RFC-0023: Notifications Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `desktop/notifications` to reduce interruption through a small Atlas-owned
KConfig key set.

The module does not disable critical system notifications. It manages only keys
listed in `profile.tsv`, refuses pre-existing keys, and removes only unchanged
Atlas-owned keys.

