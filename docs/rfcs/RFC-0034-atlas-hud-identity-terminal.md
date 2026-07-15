# RFC-0034: Atlas HUD — Identity + Daily-Workspace Terminal

Status: Accepted

Date: 2026-07-15

## 1. Summary

Atlas gains a cohesive "starship-console" visual identity — the **Atlas HUD** — with
a single source of truth (`desktop/identity`) and its first consumer surface fully
built: **the terminal**. The full design is captured in a Fable-authored design
bible (an interactive prototype + build spec); this RFC records the identity
primitives and the terminal implementation, and fixes an in-place-upgrade bug the
work surfaced.

Design bible (motion prototype + spec): the "Atlas HUD" and "Daily Workspace"
artifacts. The aesthetic: a deep-navy field, one structural blue, a *scarce* cyan
"live" glow, the Inter (human) / JetBrains Mono (machine) type duality, and a
recurring orbital-node glyph `◐` — one symbol across boot, login, lock, and shell.

## 2. Identity — the single source of truth (`desktop/identity`)

A new assets-only module owns the brand primitives so every surface derives from
one place (never a hand-copied hex):

- **`tokens.env`** — the locked palette (navy ramp `#0a0e14`→`#243247`, ink
  `#e6edf3`, dim `#7d8aa0`, structural accent **`#5aa2ff`**, live glow **`#57e5ff`**
  used on exactly one element per surface, error `#ff6b5a`), the type pairing, the
  `◐` node glyph, and the motion scale.
- **`atlas-mark.svg`** — the **Orbital Monogram "A"**: two orbital arcs converging
  on a bright star node, a faint tilted orbit behind. Authored on a 0–64 viewBox
  with an exact geometry (arc beziers, node radial gradient, glow filter). Reads as
  a letter *and* as a body in orbit; glows on dark.
- **`atlas-mark-16.svg`** — a hand-tuned favicon variant (drops the faint orbit +
  crossbar, heavier strokes) so the mark survives ≤32px.

The accent is unified to `#5aa2ff` (the prior `#4ea1ff` in some assets is retired).

## 3. Terminal — the flagship surface

The daily-driver terminal becomes a glass HUD instrument. Changes, all derived from
the tokens:

- **Ghostty theme** (`atlas-reference.theme`): the 16-colour palette migrated to the
  locked tokens — cursor `#57e5ff` (the cursor earns the scarce cyan), blue
  `#5aa2ff`, cyan `#57e5ff`, red `#ff6b5a`.
- **Ghostty config** (`config.ghostty`): `background-opacity = 0.94` +
  `background-blur-radius = 20` (the navy desktop bleeds through — a glass
  instrument, crisp enough for all-day reading); split-divider colour; and the
  cursor as the one live element — a **blinking bar**.
- **Starship** (`starship.toml`): a console readout, not a powerline — hairline
  colour separation, palette aligned to the tokens, and the character prompt is the
  **`◐` orbital node** (cyan when ready, warm on error) — the through-line glyph.
- **SYSTEM ONLINE greeting** (`fastfetch/config.jsonc`): a fast telemetry readout
  (host / kernel / uptime / shell) beside the orbital-A mark rendered in ASCII, with
  the tool checks collapsed into one line. Restraint: no hardware dump, no per-tool
  wall.
- **Wiring** (`development/fish` snippet): fires the greeting only for a top-level
  interactive shell (never nested), only if fastfetch is present (loose coupling);
  and sets `fish_cursor_default line blink` so the blinking bar survives Ghostty's
  shell-integration cursor hand-off (Ghostty paints it cyan).

Cursor detail: Ghostty's `shell-integration-features = cursor` hands cursor control
to the shell, so `cursor-style-blink` alone is overridden — fish must set the blink
itself, which the snippet now does.

## 4. In-place upgrade fix (`fish`, `fastfetch`)

Applying §3 surfaced a real bug: `development/fish` and `desktop/fastfetch` recorded
their config hash in the install marker and **hard-failed `marker_load` whenever
Atlas's own source content changed** — so every hook (check/verify/update/install)
died, and Atlas could not upgrade its own managed content in place. `ghostty` and
`starship` never had this and upgraded cleanly.

Fix (matching the ghostty/starship pattern): the source-hash comparison is removed
from `marker_load` (which now only validates marker *structure*); drift is detected
where it belongs — on-disk-vs-source in `check`/`verify` — and `update` now
**refreshes the marker** after rewriting the config. Result: a legitimate Atlas
content change is reported by `check` as not-satisfied and reconciled by a clean
`atlas update <module>`.

## 5. Testing

Full suite stays green (1109). New guards:

- ghostty: the HUD glass + live blinking cursor; the theme uses the locked palette.
- fastfetch: the SYSTEM ONLINE greeting shape (telemetry + collapsed tool line + the
  `◐` mark; no cpu/gpu dump).
- fish: the snippet ships the blinking HUD cursor.
- **in-place upgrade (both fish + fastfetch):** `marker_load` tolerates a
  changed source hash (the fixed bug); `update` reconciles the config *and* refreshes
  the marker hash; `verify` then passes.

## 6. Ownership & scope

`desktop/identity` owns only its own assets (no activation, no system state) and is
the dependency root for the HUD surfaces. The terminal modules keep their existing
reversible marker/manifest lifecycles. Desktop palette alignment, the KDE color
scheme, and the boot/login/lock surfaces are **follow-up RFCs** consuming the same
`desktop/identity` tokens — deliberately not a full custom Plasma theme (YAGNI, per
the design bible).

## 7. Decision required

1. Accept `desktop/identity` (tokens + the Orbital Monogram mark) as the HUD source
   of truth.
2. Accept the terminal HUD (Ghostty glass palette + `◐` Starship prompt + SYSTEM
   ONLINE greeting + blinking cyan cursor).
3. Accept the fish/fastfetch in-place-upgrade fix (move the source-hash check out of
   `marker_load`; refresh the marker on `update`).
