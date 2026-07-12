# RFC-0024: Plymouth Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `desktop/plymouth` to install a fast, minimal Atlas boot splash theme.

Atlas owns only `/usr/share/plymouth/themes/atlas` and the install marker. It
does not run `plymouth-set-default-theme` in this RFC; boot-theme activation
requires explicit real-machine validation and may be added later.

