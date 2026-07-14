# RFC-0033: Wallpaper Activation — deferred, problem statement

Status: Deferred (problem statement — not yet a design)

Date: 2026-07-14

Split from: [RFC-0030](RFC-0030-kde-look-activation.md) Rev 2

## 1. Why this is its own RFC

RFC-0030 Rev 1 tried to activate the Atlas wallpaper alongside icons/cursor/fonts
using the RFC-0029 activation contract (record prior → apply → restore verbatim).
An adversarial review found the wallpaper case, unlike the other three, cannot be
made safe by reusing the single-value KConfig escrow — it needs a redesign. So it
was split out here and RFC-0030 Rev 2 covers only icons/cursor/fonts.

This document records the concrete problems so a future accepted design does not
rediscover them. It intentionally proposes no implementation yet.

## 2. What makes wallpaper different from a KConfig key

Verified against the live machine's
`~/.config/plasma-org.kde.plasma.desktop-appletsrc`:

1. **The wallpaper is not one value.** It lives across multiple
   `[Containments][N][Wallpaper][org.kde.image][General] Image=` groups — one per
   desktop containment — plus separate groups for the slideshow plugin
   (`org.kde.slideshow`), solid-colour plugin, etc. A single `prior_wallpaper`
   value cannot faithfully capture a multi-monitor or multi-desktop setup.
2. **Containment IDs are session-generated, not stable.** Hardcoding
   `[Containments][1]` as "the primary desktop" is a machine-specific accident: on
   this host `[Containments][1]` is the desktop but `[Containments][2]` is a
   *panel* that also carries a `wallpaperplugin=org.kde.image` group; on another
   machine the desktop containment may be `[8]` or `[25]` while `[1]` is a deleted
   panel. Reading a fixed containment number mis-identifies the wallpaper on most
   machines and wedges the activation state machine (the post-activate drift check
   reads a different key than `plasma-apply-wallpaperimage` wrote).
3. **Value format mismatch.** The stored value is a `file://` URL
   (`Image=file:///home/user/.local/share/backgrounds/atlas/atlas-gradient.svg`),
   while the Atlas asset is a plain filesystem path. Without normalisation,
   "current == Atlas asset" is never true even right after a successful apply,
   producing a permanent spurious refuse-to-clobber.
4. **The active plugin may not be an image at all.** A user may be on a slideshow,
   a solid colour, or a third-party wallpaper plugin. Switching to the Atlas image
   destroys that selection, and a single recorded image cannot restore it.

## 3. Why the RFC-0029 contract cannot be reused as-is

RFC-0029's core invariant is *record the exact prior, then switch, then restore
verbatim*. For wallpaper, the "exact prior" is a structured, per-screen,
per-plugin object, not a scalar. Recording only the primary image and deferring
the refusal to `deactivate` (RFC-0030 Rev 1's approach) is a **designed one-way
door**: Atlas switches while already knowing at activate time it cannot restore,
which violates the record-before-switch invariant and can silently overwrite a
multi-monitor or non-image configuration. That is the opposite of what the
framework guarantees, so it must not ship under the reversible-activation banner.

## 4. Requirements a future accepted design must meet

1. **Containment discovery**, not a hardcoded ID: enumerate desktop containments
   (e.g. by `plugin=org.kde.plasma.folder`/`desktop` and `activityId`/`lastScreen`)
   and ignore panels. Consider the ScreenMapping data or a DBus query to
   `org.kde.plasma.shell` rather than parsing the appletsrc directly.
2. **Full-fidelity prior capture or honest refusal at ACTIVATE time.** Either
   record enough to restore every screen and the active plugin verbatim, or refuse
   to *activate* (not deactivate) whenever the current config is anything other
   than a single, uniform `org.kde.image` wallpaper that can be captured exactly.
   No lossy prior may ever be recorded.
3. **URL/path normalisation** so "current == Atlas asset" is reliable both for the
   idempotence check and the drift/refuse logic.
4. **Multi-monitor safety**: never restore one screen's image onto all screens; if
   screens diverge and cannot be captured/restored per-screen, refuse to activate.
5. Reuse the RFC-0029 write-once escrow, refuse-to-clobber, interrupted-deactivate
   finalize, and disown mechanics once the prior can be captured faithfully.

## 5. Decision required

None yet — this RFC is a deferral marker. A future revision moves it to Proposed
with an actual design meeting §4, at which point it goes through the Fable judge
like every other activation RFC.
