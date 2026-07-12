# RFC-0022: Power Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `desktop/power` to apply conservative developer-laptop power defaults through
an Atlas-owned KConfig key set.

The module never forces permanent performance mode and never changes battery
health behavior. It manages only the keys listed in `profile.tsv`, refuses
pre-existing keys, verifies drift only after Atlas ownership, and removes only
unchanged Atlas-owned keys.

