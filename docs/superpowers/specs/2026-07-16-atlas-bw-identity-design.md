# Atlas — Black & White Word-Only Identity

Status: Approved 2026-07-16. Supersedes the cyan "starship console" greeter and
the wallpaper-constrained wordmark directions explored earlier the same day.

## Decision

- Black & white only. No color accent except a single red (`#E5484D`),
  reserved exclusively for authentication failure.
- No icon/graphic logo anywhere. Atlas's identity is a word, not a mark.
- One artifact — the ASCII "ATLAS" masthead below — expressed differently per
  surface, never a second invented mark (kills the earlier "custom
  module-grid A" ghost concept).

```
 █████╗ ████████╗██╗      █████╗ ███████╗
██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝
███████║   ██║   ██║     ███████║███████╗
██╔══██║   ██║   ██║     ██╔══██║╚════██║
██║  ██║   ██║   ███████╗██║  ██║███████║
╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝
```

41 columns × 6 rows. Font: JetBrainsMono Nerd Font (confirmed installed at
`~/.local/share/fonts/atlas/JetBrainsMonoNerdFont/`).

## Product principle → concrete rule

"Nothing should disturb the user, but they need to be glued to their
machines." Resolved as: login/lock are high-frequency surfaces (Emil
Kowalski's "100+ views/day → no animation, ever" tier) — the functional path
(focus, type, submit, unlock) is instant and never gates a keystroke. The
"glued" feeling comes from ambient craft (GHOST's near-imperceptible idle
motion, proven contrast, machined 1px edges) — not from transitional
flourish the user would sit through hundreds of times a day. Boot and the
fastfetch moment are one-shot-per-session and get the only expressive
motion in the system.

## Per-surface spec

### Boot (Plymouth)

Masthead baked as 5 letter PNGs on a 24×48px cell grid (1920/24 = 80 cols —
the boot screen is an 80-col terminal), placed 1:1, zero runtime scaling.
Two-tone bake: block glyphs `#F2F2F2`, shadow glyphs `#5A5A5A`, background
`#050505`. Animation: letters snap in one at a time every 5 frames (100ms),
full word at 500ms; cursor then blinks 530ms (26 frames on/off) for the rest
of boot as the heartbeat; progress bar fades in at 700ms and fills linearly
with real progress data, no easing.

### Terminal (fastfetch)

Same masthead verbatim, real monospace text via fastfetch's two-color logo
placeholders (`$1`=bright white blocks, `$2`=`38;5;240` grey shadow —
matches the boot bake exactly). Metadata block beneath in the same two-grey
hierarchy (keys grey, values bright white). Colors swatch module disabled.

### Login (SDDM, full QML canvas)

GHOST = the same masthead as one ~5500×1344px QML `Text` element, cropped by
the frame so only fragments are visible, opacity breathing 0.028↔0.042 on a
17s timer, x-drift ±12px on a 41s timer (co-prime periods, never visibly
repeats), approached via overdamped `SpringAnimation` (spring 0.4, damping
0.05, mass 10) — always decelerating, sub-perceptual on a 5500px texture.

Form: centered 384px column — label, static username (click-to-edit),
password field (52px, `#111111` bg, 1px `#262626` border, 2px caret blinking
530ms — same cadence as the boot cursor). Focus/submit/error are
near-instant; the only earned motion is a spring-oscillation shake on wrong
password (spring 4.5, damping 0.15, settles <350ms) paired with the single
red accent, which exists in no resting state.

Full palette, exact QML easing/duration values, and contrast math (16.5:1
body, 4.7:1 error-on-GHOST) are in the implementation; this doc records the
decision, not a byte-for-byte mirror of the build.

### Lock

Shares the login component verbatim. Differences: no entrance animation at
all (GHOST fades in over 400ms, chrome does not); adds a clock (JetBrainsMono
ExtraLight 88px, `-0.02em` tracking); password field only, no username/session
row; idle-settle to 25% opacity after 20s untouched, any keypress restores
instantly and the keystroke still lands.

## Build verification (no live risk)

- Boot: baked assets previewed via composited PNG before touching Plymouth's
  active theme; `plymouth --show-splash` in a nested session where possible.
- Login: `sddm-greeter-qt6 --test-mode --theme <scratch-path>`, screenshotted,
  before `atlasctl update desktop/sddm`.
- Lock: `kscreenlocker_greet --testing --shell <scratch-path>` (safe preview
  mode, does not lock the real session), screenshotted, before
  `atlas activate desktop/lockscreen`. Activation is separately reversible
  per RFC-0029 escrow; manual escape via `kwriteconfig6` is documented in
  the module README regardless.
- Terminal: `fastfetch --config <path>` prints straight to the terminal, no
  risk.

## Open follow-ups (explicitly deferred, not forgotten)

- RFC-0027's `./atlas` launcher references (superseded by the `atlasctl`
  rename, tracked separately).
- Whether the old `atlas-mark.png` icon asset under
  `modules/desktop/lockscreen/assets/org.atlas.hud/contents/splash/images/`
  should be deleted now that the no-logo rule is final, or whether the splash
  sub-screen has a different treatment — resolve during the lock-screen build.
