# RFC-0024a: Plymouth Module — Script-Plugin Dependency (amends RFC-0024)

Status: Accepted

Date: 2026-07-13

Amends: [RFC-0024](RFC-0024-plymouth-module.md) (Accepted)

## 1. Problem

`desktop/plymouth` ships a **script-based** boot theme: `atlas.plymouth` declares
`ModuleName=script`, and `atlas.script` is its logic. A script theme is inert
without Plymouth's script plugin, `/usr/lib64/plymouth/script.so`, provided by the
Fedora package **`plymouth-plugin-script`**.

RFC-0024 scoped the module to "owns only `/usr/share/plymouth/themes/atlas` and
the marker; installs no packages." As a result the module copies the theme files
but never installs the plugin the theme requires. On a stock Fedora KDE install
(which does not ship `plymouth-plugin-script`), activating the theme fails:

```
$ sudo plymouth-set-default-theme -R atlas
/usr/lib64/plymouth/script.so does not exist
```

This was found in live use. It is the audit's headline failure class — a module
reporting healthy for software that cannot actually function: `module::check`
and `module::verify` only hash the theme *files* (`_plymouth_matches`), so
`atlas status`/`doctor desktop/plymouth` report "installed"/healthy for a theme
that is non-functional because its runtime plugin is absent.

## 2. Change

Narrowly widen the module's ownership to include the theme's runtime dependency:

1. `module::install` installs `plymouth-plugin-script` (idempotent, via
   `os::dnf_install`) before writing the theme files.
2. `module::check` and `module::verify` additionally require the plugin to be
   present, so neither reports healthy when the theme cannot render. Presence is
   tested with `os::pkg_installed plymouth-plugin-script` (RFC-0028), which is
   arch-independent and cached.

`plymouth` itself is a base component of a Fedora KDE workstation (it renders the
boot splash at all) and is treated as a given; only the missing *plugin* is
adopted. Activation (`plymouth-set-default-theme -R`) remains **out of scope**, as
in RFC-0024 — that is user-owned (or handled by RFC-0029).

## 3. Ownership & state

- No marker schema change. The plugin's presence is verifiable at any time via
  `rpm`, so the marker stays `schema` + `state` only. Existing markers (already
  written by the shipped module) continue to parse unchanged — important, since
  machines in the field already have `state=installed` markers.
- The module still does **not** own `plymouth` itself, the kernel cmdline, the
  default-theme selection, or the initramfs.

## 4. Behavioural contract after this change

- `check`: `installed` iff marker=installed AND theme files match AND
  `plymouth-plugin-script` installed. (A machine that had the buggy state —
  marker=installed, plugin absent — now correctly reports not-satisfied, so
  `atlas install` re-runs and installs the plugin instead of skipping.)
- `verify`: absent/detached → 0 (fresh is valid); installing → 1; installed →
  fail with a clear message if the plugin is missing or the theme drifted.
- `install`: idempotent; installs the plugin, writes the theme, promotes marker.
- `remove`/`update`/`backup`/`restore`: unchanged. `remove` deliberately does
  **not** uninstall the plugin (Atlas does not remove a shared system package it
  did not exclusively introduce; it only detaches the theme it owns).

## 5. Testing

Extend `tests/test_module_plymouth.sh` (mocks `os::dnf_install`, `rpm`, `sudo`):

1. `install` calls `os::dnf_install plymouth-plugin-script` (assert via the dnf
   log) and still writes the theme.
2. `check`/`verify` FAIL when the theme files match but the plugin is absent
   (mock `rpm -q plymouth-plugin-script` → not installed) — the regression guard
   for this exact bug.
3. `check`/`verify` pass when both theme and plugin are present.
4. Full suite stays green.

## 6. Decision required

1. Accept widening `desktop/plymouth` ownership to include installing
   `plymouth-plugin-script` (a one-package runtime dependency of the theme it
   already ships).
2. Accept that `check`/`verify` now gate on plugin presence (so "healthy" implies
   "renderable"), with no marker schema change.
