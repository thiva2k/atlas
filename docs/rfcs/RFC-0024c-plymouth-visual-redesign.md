# RFC-0024c: Plymouth Theme — Visual Redesign (amends RFC-0024)

Status: Proposed

Date: 2026-07-14

Amends: [RFC-0024](RFC-0024-plymouth-module.md) (Accepted), builds on
[RFC-0024a](RFC-0024a-plymouth-plugin-dependency.md) and
[RFC-0024b](RFC-0024b-plymouth-passphrase-prompt.md)

## 1. Problem

The Atlas boot splash shipped as a *minimal* theme (RFC-0024): a single native-size
`Image.Text("ATLAS")` on a near-black background. In live use it read as bare and
unbranded — a tiny word on a black screen during disk unlock. RFC-0024b made it
*functional* (passphrase entry); this RFC makes it *presentable*.

## 2. Change

Replace the wordmark-only script with a designed brand lockup, keeping the
RFC-0024b passphrase callbacks intact:

- **Crisp raster assets** rendered from the Atlas UI font (Inter) rather than the
  built-in bitmap text: `logo.png` (the `ATLAS` wordmark, letter-spaced),
  `tagline.png` (`WORKSTATION`, muted), `accent.png` (a soft accent divider),
  `track.png` (a dim progress rail), `spark.png` (a bright light-sweep). All are
  shipped in the theme dir and hashed by the existing manifest.
- **Layout**: centered lockup — wordmark, accent divider, tagline — above a dim
  track along which a light-sweep animates.
- **Animation** uses only linear arithmetic (a frame counter driving a fade-in and
  a wrapping sweep) — no trig or runtime feature that a given Plymouth build might
  lack, so the theme degrades predictably.
- **Scoping discipline**: all state that must persist across `refresh` frames or is
  read inside callbacks is accessed via `global.*`, so nothing collides with a
  callback parameter or silently becomes a per-call local.
- The passphrase prompt, bullets, and boot messages are restyled to match but keep
  the RFC-0024b callback contract.

`atlas.plymouth` description changes from "Minimal Atlas boot splash" to "Atlas boot
splash". No package, marker, or ownership change.

## 3. Ownership & state

Still owns only `/usr/share/plymouth/themes/atlas` and the marker. The added PNGs
are part of the theme content the manifest already hashes, so a machine with the
old theme reports drift on `check`/`verify` and re-installs via
`atlas install`/`update desktop/plymouth`. As with any theme content change, it
reaches the boot only after the initramfs is rebuilt
(`plymouth-set-default-theme -R` / `dracut -f`).

## 4. Testing

`tests/test_module_plymouth.sh` hashes whatever `assets/` contains, so the new
assets are covered by the existing install/verify/update/drift tests. Two static
guards are added:

1. the shipped `atlas.script` keeps a passphrase handler (RFC-0024b);
2. every `Image("x")` the script loads resolves to a shipped asset — so a future
   edit cannot reference a missing image and render a broken splash.

The rendered result cannot be unit-tested in the Bash harness; the static guards
plus a live `plymouth` preview (`plymouthd` + `plymouth show-splash` on a spare VT)
and a boot are the coverage boundary.

## 5. Decision required

1. Accept replacing the minimal wordmark with the designed, animated brand lockup
   (crisp Inter assets, linear-only animation, `global.*` scoping), keeping the
   RFC-0024b passphrase contract.
2. Accept the added "every referenced image asset is shipped" regression guard.
