# Unblocking Atlas Hyprland via a rebuilt `aquamarine` — weekend design

Status: Approved 2026-07-18 (user chose scope "unblock + go live + package"; approach
per Fable's architecture brief, verified live against the enabled COPR). Supersedes
the "wait for the COPR rebuild" half of the sibling spec's §7 by adding an active
path. The dual-session desktop itself is unchanged — see
`2026-07-16-atlas-hyprland-desktop-design.md`.

## 1. Why this exists

The Atlas Hyprland desktop is fully built and staged but cannot install: Fedora 44
bumped `libdisplay-info` 0.2 → 0.3 (`.so.2` → `.so.3`), and the only F44 packaging of
full Hyprland — COPR `solopasha/hyprland` — still ships `aquamarine-0.9.5-2`, built
against the old `.so.2`. `dnf install hyprland` fails with "nothing provides
libdisplay-info.so.2". This spec is the active unblock: rebuild that one package
ourselves instead of waiting for the upstream rebuild.

## 2. The one-artifact reframing (verified 2026-07-18)

The entire blocker reduces to a single package. Verified live against the enabled
COPR:

- `hyprland` requires `aquamarine(x86-64) >= 0.9.2` — a **minimum**, not an exact
  pin. So a locally-rebuilt `0.9.5-...` satisfies it.
- `hyprland` also requires `libaquamarine.so.8()(64bit)` — its binary is hard-linked
  to aquamarine soname **8**. This makes the rebuild version **mandatory, not
  optional**: we must rebuild exactly `0.9.5` (which provides `.so.8`). A newer
  aquamarine would bump its soname (→ `.so.9`) and Hyprland's `NEEDS
  libaquamarine.so.8` would become unsatisfiable.
- Only `aquamarine` carries the `libdisplay-info.so.2` requirement; the low-level
  hypr* libs already on the system (`hyprutils`, `hyprlang`, `hyprcursor`,
  `hyprgraphics`) are clean against `.so.3`.

Net: **rebuild `aquamarine` 0.9.5 unchanged in every respect except the library it
links** (`libdisplay-info.so.3` in place of `.so.2`), and stock Hyprland installs on
top of it normally.

## 3. Approach: local RPM rebuild in `mock`

Fable evaluated three candidates and chose RPM rebuild decisively:

| Approach | Verdict | Reason |
|---|---|---|
| **Rebuild the RPM** (`mock`, vs F44's `.so.3`) | **Chosen** | dnf-tracked, cleanly removable, the only option that auto-hands-off to the future official package |
| Source build → `/usr/local` | Rejected | Not reversible; permanently shadows the linker against the eventual official package |
| Containerized (distrobox/toolbox) | Rejected | A container can't own the GPU/DRM-master/seat for a compositor picked at the login screen |

**The load-bearing packaging detail — the Release tag.** The broken COPR artifact is
`aquamarine-0.9.5-2`; the eventual official rebuild will be `-3` (or a version bump).
Tag ours **`0.9.5-2.atlas1`** — concretely, spec `Release: 2%{?dist}.atlas1`,
rendering `2.fc44.atlas1` (the bare `2.atlas1` form without the dist tag sorts
*below* the broken `2.fc44` and must not be used; verified with `rpm.labelCompare`
and `rpmdev-vercmp`). By RPM version ordering it wins over `-2` (installs now) and
loses to `-3` (a routine `dnf upgrade` silently swaps in the official package when
it lands). Getting this wrong (e.g. `-3.atlas`) would block the official
package indefinitely. Stay on version **0.9.5** — required by §2's `libaquamarine.so.8`
constraint and by supersession ordering.

`mock` is preferred (chroot build; zero host mutation until install). If `mock` proves
heavy, host `rpmbuild` + `dnf builddep` is an acceptable fallback — its build-deps are
dnf-tracked and undoable — but `mock` is the clean line. Time-box `mock` setup to a few
hours before falling back.

## 4. Phase sequence

- **Phase 0 — Verify & snapshot (read-only, zero mutation).**
  - Re-run the full install-set `libdisplay-info.so.2` audit *with the COPR repoid*
    (the exploratory check omitted it for COPR-only packages).
  - Confirm the COPR's `hyprland` does not pin `aquamarine` to an exact NEVR
    (verified 2026-07-18: it uses `>= 0.9.2`).
  - Fetch aquamarine's `.src.rpm` and read its spec.
  - Record `rpm -qa` as the known-good baseline into the Atlas state dir.
  - Copy `~/.ssh` aside — nothing in this plan touches `$HOME`, but this permanently
    retires the "don't lose my keys" concern.
  - Confirm `/usr/local/lib` holds no ghost aquamarine from prior manual attempts.

- **Phase 1 — Build in isolation (`mock`).** Rebuild `aquamarine-0.9.5` against current
  F44 with Release `2.atlas1`.
  - **Gate:** the resulting RPM's `requires` lists `libdisplay-info.so.3` and **no**
    `.so.2`, and it `provides libaquamarine.so.8`.

- **Phase 2 — Transaction rehearsal (the gate that protects Plasma).** Resolve the full
  install — `hyprland xdg-desktop-portal-hyprland hyprlock hypridle hyprpaper waybar
  wofi mako kitty grim slurp brightnessctl playerctl` plus the local aquamarine RPM —
  with `--assumeno` / download-only.
  - **Gate:** the transaction is **purely additive** — zero removals, zero upgrades of
    any non-hypr package. Nothing in Plasma links aquamarine, so any non-additive line
    is a hard stop.

- **Phase 3 — Install & validate off the login path.** Run the resolved install as one
  `dnf` transaction; immediately record its `dnf history` ID into the Atlas state dir
  so the undo command is knowable from a bare TTY. Bake wallpapers via
  `assets/generate.sh`. Then validate **without SDDM**: launch Hyprland from a spare
  TTY (real DRM path) and run the go/no-go gate (§7).

- **Phase 4 — Go live.** Only after a 5/5 gate: log out → pick "Hyprland" at the Atlas
  SDDM greeter. No reboot; Plasma stays default and untouched. Note: SDDM remembers the
  last-picked session, so it will preselect Hyprland on the next login — Plasma remains
  one click away.

- **Phase 5 — Package as a reversible module.** Write `modules/desktop/hyprland/module.sh`
  modeled on `modules/development/ghostty/module.sh` (§6).

## 5. Rollback and safety floor

The machine has **no SSH** (SSH is off); the only rescue path is physical TTY
(Ctrl+Alt+F3). Every phase stays inside that floor:

- Phases 0–2 leave the host byte-identical to the known-good baseline; abort is
  deleting a build directory.
- Phase 3 onward, "known-good" is always **one `dnf history undo <id>` away**,
  executable from a bare TTY with no network. Everything installed lives in that single
  recorded transaction. The staged `~/.config` files are inert without the packages and
  were already present.
- Phase 4 worst case (greeter or in-session failure): Ctrl+Alt+F3, `dnf history undo`,
  reboot, land in untouched Plasma.
- SSH keys are never in any write path; the Phase 0 copy makes even that moot.

Plasma is never removed, stays the default session, and is untouched throughout.

## 6. The `module.sh` (Phase 5) — architecture

Follows the Atlas module convention exactly (state marker written first, work done,
marker flipped to `installed` only after re-verification; atomic writes; sha256 drift
detection; `_run_privileged` for root steps).

- **Hooks:** `check / install / verify / update / remove / backup / restore`.
- **Marker:** `${ATLAS_STATE_DIR}/installed/desktop-hyprland`, schema-versioned, mode
  600, states `installing → installed → detached`; also records the Phase 3
  `dnf history` transaction ID.
- **Owns:** the COPR repo intent; the local `aquamarine-0.9.5-2.atlas1` RPM install;
  the package set from Phase 2; the config deploy (takes ownership of the already-staged
  `~/.config` files under `hypr/`, `waybar/`, `wofi/`, `mako/`, `kitty/`, with drift
  detection); the wallpaper bake; the watcher disposition.
- **Does not own:** user shell config, user themes, or any file outside the list above.
- **`remove` = detach:** reverses the Atlas-owned config/wallpaper deploy and repoints
  the watcher, but leaves package rollback to the recorded `dnf history undo <id>`
  (conservative — avoids a cascading `dnf remove`).
- **Build split:** a separate `modules/desktop/hyprland/build/build-aquamarine.sh` helper
  produces the RPM, so `module::install` stays fast and idempotent (build once, install
  deterministically) rather than compiling on every run.
- **Docs & watcher:** update the README's "⚠ Blocked" section to "shipped via local
  rebuild; auto-supersedes on official `-3`," and repurpose `watch-availability.sh` to
  detect when our `.atlas` release marker is gone (→ superseded, all-clear) — because the
  existing watcher self-disables the moment `hyprland` is installed and would otherwise
  never report the handoff.

## 7. Go/no-go gate — all five, before picking Hyprland at SDDM

1. Rebuilt RPM requires `libdisplay-info.so.3` only and provides `libaquamarine.so.8`.
2. Phase 2 transaction resolves purely additive (zero removals/non-hypr upgrades).
3. Hyprland launched from a TTY reaches a working desktop with **outputs correctly
   identified at native resolution and refresh** (the one functional test that exercises
   the `libdisplay-info` rebuild — EDID parsing is that library's job), with working
   input and a clean exit back to the TTY.
4. `hyprlock` lock/unlock succeeds in that session (the classic Hyprland PAM-lockout
   vector; hypridle wires straight into it).
5. A normal Plasma login still works afterward.

Anything short of 5/5: stay on Plasma, `dnf history undo`, regroup.

## 8. Risk register

1. **Aquamarine 0.9.5 does not build against `.so.3`.** Caught in `mock` at zero host
   cost. Mitigation: backport the upstream compatibility patch as `.atlas2`; if that
   spirals, abort the weekend with a pristine host.
2. **Builds but crashes at runtime (ABI drift).** Same-version rebuild minimizes it;
   Phase 3's TTY launch catches it before login exposure. A TTY crash drops to a shell —
   Plasma never touched.
3. **Transaction perturbs Plasma's dependency set.** Mitigation: the Phase 2
   additive-only gate, reviewed line by line. Hard stop, not a judgment call.
4. **`hyprlock` cannot authenticate (PAM) — trapped in a locked session.** Mitigation:
   explicit lock/unlock test inside the Phase 3 TTY session before any SDDM login.
5. **Weekend burn on `mock` setup.** Mitigation: `rpmbuild` + `dnf builddep` fallback
   (dnf-tracked, undoable); time-boxed.

## 9. Explicitly out of scope (separate follow-ups, per the sibling spec §8)

- RFC-0034 (fastfetch) and RFC-0037 (lockscreen) amendments.
- Reconciling the off-identity blue assets Fable flagged.
- Baking "theme font must be system-wide" into the SDDM/fonts module.
- Retiring the vestigial `org.atlas.hud` Plasma-only lock module.

These are not part of this weekend's work.
