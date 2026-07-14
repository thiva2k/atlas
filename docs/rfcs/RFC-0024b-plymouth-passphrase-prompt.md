# RFC-0024b: Plymouth Theme — Passphrase Prompt (amends RFC-0024)

Status: Proposed

Date: 2026-07-14

Amends: [RFC-0024](RFC-0024-plymouth-module.md) (Accepted), builds on
[RFC-0024a](RFC-0024a-plymouth-plugin-dependency.md) (Accepted)

## 1. Problem

The Atlas boot theme's `atlas.script` drew only the "ATLAS" wordmark. A Plymouth
**script** theme that never registers a password callback cannot display the
disk-encryption (LUKS) passphrase field. On a machine with an encrypted root, the
boot therefore showed the Atlas splash with no way to type the passphrase; the
user had to press **Esc** to fall back to the text plugin and enter it there.

Found in live use immediately after RFC-0024a made the theme actually render
(installing `plymouth-plugin-script`). This is the same failure class the audit
targets — a component that looks healthy but cannot perform its core function:
the module hashes the theme files and reports installed/healthy, while the theme
is non-functional for an encrypted boot.

## 2. Change

Extend `assets/atlas.script` to register the standard Plymouth interaction
callbacks so the splash can accept the passphrase:

- `Plymouth.SetDisplayPasswordFunction(cb)` — on each keystroke Plymouth calls
  `cb(prompt, bullets)`; the theme draws the prompt text and one masking glyph per
  typed character, centered under the wordmark.
- `Plymouth.SetDisplayNormalFunction(cb)` — clears the passphrase UI when entry is
  not being requested (removes the prompt/bullet sprites).
- `Plymouth.SetMessageFunction(cb)` / `Plymouth.SetHideMessageFunction(cb)` —
  surface boot messages (e.g. a wrong-passphrase notice) and clear them.

Sprites are held in `global.*` variables and set to `NULL` to remove them, the
standard script-theme idiom. No new files, no package change, no marker schema
change — only the content of the theme asset the module already ships and hashes.

## 3. Ownership & state

- Still "owns only `/usr/share/plymouth/themes/atlas` and the marker." The asset's
  content changes; its manifest hash changes with it, so a machine with the old
  theme installed correctly reports drift on `verify`/`check` and re-installs via
  `atlas install`/`update desktop/plymouth`, exactly as the manifest mechanism
  (RFC-0024) intends.
- Activation (making `atlas` the default and rebuilding the initramfs) remains out
  of scope here — that is RFC-0032. But note that a theme content change only
  reaches the boot after the initramfs is rebuilt (`plymouth-set-default-theme -R`
  or `dracut -f`); this RFC documents that reinstalling the theme is necessary but
  not sufficient — the initramfs must be regenerated for the new script to take
  effect at boot.

## 4. Behavioural contract after this change

- `check`/`verify`: unchanged in structure (marker installed + plugin present +
  theme files match). Because the shipped `atlas.script` now includes the
  callbacks, a matching install is one that can render the passphrase prompt.
- `install`/`update`: idempotent; write the new theme content; the manifest
  reflects the updated `atlas.script`.
- No behavioural change to `remove`/`backup`/`restore`.

## 5. Testing

`tests/test_module_plymouth.sh` already verifies the theme is written and the
manifest matches by hashing whatever `assets/` contains, so the new script is
covered by the existing install/verify/update/drift tests without change. Add one
static assertion that the shipped `atlas.script` registers the password callback,
guarding against a future regression that drops it:

1. `grep -q SetDisplayPasswordFunction assets/atlas.script` — the theme must keep a
   passphrase handler (the regression guard for this exact bug).

The passphrase UI itself renders only under a real Plymouth boot and cannot be
unit-tested in the Bash harness; the static guard plus live boot verification is
the honest coverage boundary.

## 6. Decision required

1. Accept extending `atlas.script` with the standard password/normal/message
   callbacks so the Atlas splash can accept the LUKS passphrase (a correctness fix
   — the theme was non-functional for encrypted boots).
2. Accept the static test guard that the shipped script keeps a passphrase handler.
