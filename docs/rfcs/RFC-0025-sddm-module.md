# RFC-0025: SDDM Module

Status: Accepted

Date: 2026-07-12

## Summary

Add `desktop/sddm` to install an Atlas SDDM theme and an Atlas-owned SDDM config
drop-in that selects it.

Atlas owns only `/usr/share/sddm/themes/atlas`,
`/etc/sddm.conf.d/90-atlas-theme.conf`, and its marker. It refuses unmanaged
files at those paths and removes only unchanged Atlas-owned files.

