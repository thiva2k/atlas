# Hyprland Source-Build Unblock — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `aquamarine` 0.9.5 against Fedora 44's `libdisplay-info.so.3`, install stock Hyprland from the enabled COPR on top of it, validate off the login path, go live at SDDM, and wrap the whole thing in a reversible `modules/desktop/hyprland/module.sh`.

**Architecture:** The entire blocker is one stale package. `hyprland` requires `aquamarine >= 0.9.2` **and** `libaquamarine.so.8`; only `aquamarine` drags in the obsolete `libdisplay-info.so.2`. We rebuild aquamarine 0.9.5 unchanged except the library it links, tag it so it installs now but auto-yields to the official rebuild later, and gate every step behind the machine's only rescue path (physical TTY — SSH is off).

**Tech Stack:** Fedora 44, `mock`/`rpmbuild`, `dnf` (dnf5), COPR `solopasha/hyprland`, Bash (Atlas module convention), the Atlas pure-Bash test harness (`tests/lib/assert.sh`).

## Global Constraints

- **aquamarine version is pinned to exactly `0.9.5`** — it provides `libaquamarine.so.8`, which the installed Hyprland binary hard-links. A version bump moves that soname and makes Hyprland unsatisfiable. Never bump.
- **RPM Release string is exactly `2%{?dist}.atlas1`** (renders `2.fc44.atlas1`). Verified ordering: newer than broken `2.fc44`, older than future official `3.fc44`. Do **not** use bare `2.atlas1` — it sorts *below* the broken build and fails.
- **The built RPM must link `libdisplay-info.so.3` and provide `libaquamarine.so.8`; it must not require `libdisplay-info.so.2`.**
- **SSH is OFF.** The only rescue is physical TTY (Ctrl+Alt+F3). Every step must be TTY-recoverable. Plasma is never removed, stays the default session, and is untouched.
- **One recorded dnf transaction.** Rollback is always `dnf history undo <id>` from a bare TTY; the id is saved to the Atlas state dir at install time.
- **The install transaction must be purely additive** — zero removals, zero upgrades of any non-hypr / non-aquamarine package. Any removal = hard stop.
- **Commits carry no `Co-Authored-By` trailer.**
- Paths: built RPM lands in `~/atlas-hypr-rpms/`; Atlas state dir is `${XDG_STATE_HOME:-$HOME/.local/state}/atlas`.

---

## Part A — Live runbook (real machine)

> Part A runs against the live system. Steps marked **(root)** need `sudo`; in a Claude Code session run them yourself via the `!` prefix so you can enter your password. Steps marked **(TTY)** are done at a physical console. Nothing in Part A touches `$HOME` except the explicit `~/.ssh` backup and the wallpaper bake.

### Task A0: Verify assumptions & snapshot a known-good baseline

**Files:**
- Create: `~/atlas-hypr-rpms/` (empty, for later), `${ATLAS_STATE}/hypr-baseline-rpm-qa.txt`, `~/.ssh.bak-20260719/`
- Read-only against: the enabled COPR, the running RPM DB

**Interfaces:**
- Produces: the source RPM `aquamarine-0.9.5-2.fc44.src.rpm` in `~/atlas-hypr-rpms/`; a baseline package manifest; a verified "only aquamarine is broken" fact.

- [ ] **Step 1: Audit the whole install set for the obsolete soname**

```bash
REPO="copr:copr.fedorainfracloud.org:solopasha:hyprland"
for p in hyprland aquamarine xdg-desktop-portal-hyprland hyprlock hypridle hyprpaper; do
  printf '%-30s ' "$p"
  dnf repoquery --repoid="$REPO" --requires "$p" 2>/dev/null \
    | grep -q 'libdisplay-info.so.2' && echo '⚠ needs .so.2' || echo 'ok'
done
```

Expected: only `aquamarine` prints `⚠ needs .so.2`; every other line prints `ok`. If anything *other* than aquamarine needs `.so.2`, STOP — the one-artifact assumption is broken and this plan needs revision.

- [ ] **Step 2: Confirm hyprland does not exact-pin aquamarine**

```bash
dnf repoquery --repoid="copr:copr.fedorainfracloud.org:solopasha:hyprland" \
  --requires hyprland 2>/dev/null | grep -i aquamarine
```

Expected: `aquamarine(x86-64) >= 0.9.2` and `libaquamarine.so.8()(64bit)`. A `= 0.9.5-2` exact pin would break the supersede tag — if you see `=`, STOP and revise.

- [ ] **Step 3: Snapshot the known-good package set and back up SSH keys** **(the machine's safety net)**

```bash
ATLAS_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/atlas"
mkdir -p "$ATLAS_STATE" ~/atlas-hypr-rpms
rpm -qa | sort > "$ATLAS_STATE/hypr-baseline-rpm-qa.txt"
cp -a ~/.ssh "$HOME/.ssh.bak-20260719"
ls -la /usr/local/lib/ 2>/dev/null | grep -i aquamarine && echo "GHOST FOUND — investigate" || echo "/usr/local clean"
wc -l "$ATLAS_STATE/hypr-baseline-rpm-qa.txt"
```

Expected: baseline file has a few thousand lines; `/usr/local clean`; `~/.ssh.bak-20260719` exists.

- [ ] **Step 4: Fetch the source RPM** **(root not required)**

```bash
cd ~/atlas-hypr-rpms
dnf download --source --repoid="copr:copr.fedorainfracloud.org:solopasha:hyprland" aquamarine
ls -1 aquamarine-*.src.rpm
```

Expected: `aquamarine-0.9.5-2.fc44.src.rpm` present. (If `dnf download` is missing: `sudo dnf install -y dnf-plugins-core` first.)

- [ ] **Step 5: Commit the baseline record** (state dir is outside the repo; record the fact in the plan checkbox only — nothing to commit here). Proceed when Steps 1–4 all met expectations.

**GATE A0:** only aquamarine needs `.so.2`; hyprland uses `>= 0.9.2`; baseline + SSH backup + SRPM all present.

---

### Task A1: Build `aquamarine-0.9.5-2.fc44.atlas1` in mock

**Files:**
- Modify: `~/rpmbuild/SPECS/aquamarine.spec` (Release line)
- Create: `~/rpmbuild/SRPMS/aquamarine-0.9.5-2.fc44.atlas1.src.rpm`, `~/atlas-hypr-rpms/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm`

**Interfaces:**
- Consumes: the `.src.rpm` from A0.
- Produces: the binary RPM linked against `.so.3`, providing `libaquamarine.so.8`.

- [ ] **Step 1: Install the build toolchain** **(root)**

```bash
sudo dnf install -y mock rpm-build rpmdevtools
sudo usermod -a -G mock "$USER"
```

Then start a shell where the `mock` group is active (either log out/in, or `newgrp mock` in the current shell). Verify: `id -nG | tr ' ' '\n' | grep -qx mock && echo "mock group active"`.

- [ ] **Step 2: Unpack the SRPM and bump the Release**

```bash
rpmdev-setuptree
rpm -i ~/atlas-hypr-rpms/aquamarine-0.9.5-2.fc44.src.rpm
grep -n '^Release:' ~/rpmbuild/SPECS/aquamarine.spec
sed -i 's/^Release:.*/Release:        2%{?dist}.atlas1/' ~/rpmbuild/SPECS/aquamarine.spec
grep -n '^Release:' ~/rpmbuild/SPECS/aquamarine.spec
```

Expected: the Release line now reads `Release:        2%{?dist}.atlas1`.

- [ ] **Step 3: Rebuild the SRPM with the new release, then mock-build the binary**

```bash
rpmbuild -bs ~/rpmbuild/SPECS/aquamarine.spec
ls -1 ~/rpmbuild/SRPMS/aquamarine-0.9.5-2.fc44.atlas1.src.rpm
mock -r fedora-44-x86_64 --rebuild ~/rpmbuild/SRPMS/aquamarine-0.9.5-2.fc44.atlas1.src.rpm
```

Expected: mock ends with `Finish: run` and a success summary. The chroot pulls current F44 build-deps, so it links `libdisplay-info-devel` 0.3 automatically. **If the build fails to compile against 0.3** (risk #1): fetch the upstream compatibility patch, add it to the spec as a new `PatchN:` + `%patchN`, bump Release to `2%{?dist}.atlas2`, and rebuild. If that spirals past your time-box, abort — the host is still byte-identical to A0's baseline.

- [ ] **Step 4: Stage the artifact and run the build gate**

```bash
cp /var/lib/mock/fedora-44-x86_64/result/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm ~/atlas-hypr-rpms/
RPM=~/atlas-hypr-rpms/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm
echo "== requires =="; rpm -qp --requires "$RPM" | grep -i libdisplay-info
echo "== provides =="; rpm -qp --provides "$RPM" | grep -i libaquamarine
```

Expected: requires shows `libdisplay-info.so.3` and **no** `.so.2`; provides shows `libaquamarine.so.8()(64bit)`.

**GATE A1:** the built RPM requires `libdisplay-info.so.3` only and provides `libaquamarine.so.8`. Anything else → stop, do not install.

---

### Task A2: Transaction rehearsal — prove the install is purely additive

**Files:** none created; dry-run only.

**Interfaces:**
- Consumes: the built RPM from A1.
- Produces: a confirmed additive transaction plan (nothing installed yet).

- [ ] **Step 1: Resolve the full transaction without committing** **(root)**

```bash
RPM=~/atlas-hypr-rpms/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm
sudo dnf install --assumeno "$RPM" \
  hyprland xdg-desktop-portal-hyprland hyprlock hypridle hyprpaper \
  waybar wofi mako kitty grim slurp brightnessctl playerctl 2>&1 | tee /tmp/atlas-hypr-txn.txt
```

Expected: dnf prints a transaction summary then aborts at the prompt (because `--assumeno`). The aquamarine line must show our `2.fc44.atlas1` build being installed.

- [ ] **Step 2: Assert the additive-only gate**

```bash
echo "== any removals? (must be empty) =="
grep -iE '^\s*(Removing|Erasing|Obsoleting)' /tmp/atlas-hypr-txn.txt || echo "none — good"
echo "== upgrades of existing packages (scrutinize; hypr*/aquamarine only is fine) =="
grep -iE '^\s*(Upgrading|Downgrading)' /tmp/atlas-hypr-txn.txt || echo "none"
```

Expected: **no** removals/erasing/obsoleting lines. Any upgrade/downgrade lines must be hypr\* or aquamarine only. A removal or a non-hypr downgrade is a **hard stop** — nothing in Plasma links aquamarine, so a non-additive line means the resolver is doing something unexpected.

**GATE A2:** zero removals; upgrades (if any) confined to hypr\*/aquamarine. Otherwise stop and investigate before any real install.

---

### Task A3: Install for real, then validate off the login path

**Files:**
- Create: `${ATLAS_STATE}/hypr-install-txn` (the recorded dnf history id), wallpapers under `~/.local/share/backgrounds/atlas/`

**Interfaces:**
- Consumes: the verified transaction from A2.
- Produces: an installed, TTY-validated Hyprland; a recorded rollback id.

- [ ] **Step 1: Run the single install transaction** **(root)**

```bash
RPM=~/atlas-hypr-rpms/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm
sudo dnf install -y "$RPM" \
  hyprland xdg-desktop-portal-hyprland hyprlock hypridle hyprpaper \
  waybar wofi mako kitty grim slurp brightnessctl playerctl
```

Expected: `Complete!`.

- [ ] **Step 2: Record the rollback id immediately** **(root)**

```bash
ATLAS_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/atlas"
sudo dnf history list | head -5
# read the topmost (most recent) transaction id from that table, then:
read -rp "Enter the transaction id shown above: " TXID
echo "$TXID" > "$ATLAS_STATE/hypr-install-txn"
echo "rollback command: sudo dnf history undo $TXID"
```

Expected: `${ATLAS_STATE}/hypr-install-txn` contains the id; you now know the exact undo command from a bare TTY.

- [ ] **Step 3: Bake the wallpapers**

```bash
bash ~/atlas/modules/desktop/hyprland/assets/generate.sh
ls -1 ~/.local/share/backgrounds/atlas/atlas-lock-bg.png ~/.local/share/backgrounds/atlas/atlas-wall-bw.png
```

Expected: both PNGs exist.

- [ ] **Step 4: Launch Hyprland from a spare TTY and run the go/no-go gate** **(TTY)**

Switch to a free console (Ctrl+Alt+F4), log in as `thiva`, then:

```bash
dbus-run-session Hyprland
```

Run the five checks. All five must pass:
1. **Renderer linkage (already gated in A1):** the RPM required `.so.3` only + provided `libaquamarine.so.8`.
2. **Additive transaction (already gated in A2):** zero removals.
3. **Compositor + EDID:** Hyprland reaches a usable desktop; `hyprctl monitors` shows your panel at **native resolution and refresh** (this is the real functional test of the `libdisplay-info` rebuild — EDID parsing is that library's job); mouse + keyboard work; `hyprctl dispatch exit` returns cleanly to the TTY.
4. **Lock path (the PAM lockout trap):** inside the session, `hyprlock` then unlock with your password succeeds.
5. **Plasma unaffected:** after exiting, a normal Plasma login still works.

**GATE A3:** 5/5. Anything short → `sudo dnf history undo $(cat "$ATLAS_STATE/hypr-install-txn")`, reboot, you are back on untouched Plasma. Regroup before retrying.

---

### Task A4: Go live at the SDDM greeter

- [ ] **Step 1: Switch sessions**

Log out of Plasma → at the Atlas SDDM greeter, open the session dropdown, pick **Hyprland**, log in.

Expected: the B&W Atlas Hyprland desktop (waybar, wallpaper, keybinds). `Super+L` locks; `Super+Return` opens kitty.

- [ ] **Step 2: Know the fallbacks**

SDDM now **remembers Hyprland as the last session** and will preselect it next login — Plasma is still one click away in the same dropdown. Hard floor unchanged: Ctrl+Alt+F3 → `sudo dnf history undo $(cat ~/.local/state/atlas/hypr-install-txn)` → reboot → Plasma.

**GATE A4:** you are logged into Hyprland and have confirmed Plasma is still selectable. Part A done.

---

## Part B — Package it as a reversible module (`desktop/hyprland`)

> Part B is ordinary code, built test-first with the Atlas harness. Run tests with `bash tests/run.sh` (or source a single file). Tests are hermetic — they sandbox `HOME`/XDG/state and mock `dnf`/`rpm`, touching nothing real.

### Task B1: The build helper `build/build-aquamarine.sh`

**Files:**
- Create: `modules/desktop/hyprland/build/build-aquamarine.sh`
- Test: `tests/test_hyprland_build_helper.sh`

**Interfaces:**
- Produces: a script that automates A0-Step4 + A1 (download SRPM → bump Release → mock rebuild → stage RPM into `~/atlas-hypr-rpms/`), so `module::install` never compiles inline.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/test_hyprland_build_helper.sh <<'EOF'
#!/usr/bin/env bash
# desktop/hyprland build helper — syntax + guardrails only (no real mock run).
HELPER="$ATLAS_ROOT/modules/desktop/hyprland/build/build-aquamarine.sh"

assert_status "build helper is valid bash" 0 bash -n "$HELPER"
assert_status "build helper pins the exact release string" 0 \
  bash -c "grep -qF '2%{?dist}.atlas1' \"$HELPER\""
assert_status "build helper never bumps the aquamarine version" 1 \
  bash -c "grep -qE 'aquamarine-0\.(9\.[6-9]|1[0-9])' \"$HELPER\""
EOF
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep hyprland_build`
Expected: FAIL — the helper file does not exist yet (`bash -n` errors).

- [ ] **Step 3: Write the helper**

```bash
mkdir -p modules/desktop/hyprland/build
cat > modules/desktop/hyprland/build/build-aquamarine.sh <<'EOF'
#!/usr/bin/env bash
# Atlas — rebuild aquamarine 0.9.5 against Fedora 44's libdisplay-info.so.3.
# Produces ~/atlas-hypr-rpms/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm.
# Idempotent: if the artifact already exists and passes the gate, it exits 0.
set -euo pipefail
REPO="copr:copr.fedorainfracloud.org:solopasha:hyprland"
OUT="$HOME/atlas-hypr-rpms"
RPM="$OUT/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"

gate() {  # a built RPM passes iff it links .so.3, not .so.2, and provides .so.8
  rpm -qp --requires "$1" 2>/dev/null | grep -q 'libdisplay-info.so.3' &&
  ! rpm -qp --requires "$1" 2>/dev/null | grep -q 'libdisplay-info.so.2' &&
  rpm -qp --provides "$1" 2>/dev/null | grep -q 'libaquamarine.so.8'
}

command -v dnf >/dev/null || { echo "dnf required" >&2; exit 1; }
[ -f /etc/fedora-release ] || { echo "Fedora only" >&2; exit 1; }

if [ -f "$RPM" ] && gate "$RPM"; then echo "already built: $RPM"; exit 0; fi

mkdir -p "$OUT"; cd "$OUT"
[ -f aquamarine-0.9.5-2.fc44.src.rpm ] || \
  dnf download --source --repoid="$REPO" aquamarine
rpmdev-setuptree
rpm -i "$OUT/aquamarine-0.9.5-2.fc44.src.rpm"
sed -i 's/^Release:.*/Release:        2%{?dist}.atlas1/' "$HOME/rpmbuild/SPECS/aquamarine.spec"
rpmbuild -bs "$HOME/rpmbuild/SPECS/aquamarine.spec"
mock -r fedora-44-x86_64 --rebuild \
  "$HOME/rpmbuild/SRPMS/aquamarine-0.9.5-2.fc44.atlas1.src.rpm"
cp /var/lib/mock/fedora-44-x86_64/result/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm "$OUT/"
gate "$RPM" || { echo "GATE FAILED: built RPM has wrong linkage" >&2; exit 1; }
echo "built and gated: $RPM"
EOF
chmod +x modules/desktop/hyprland/build/build-aquamarine.sh
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/run.sh 2>&1 | grep -A3 test_hyprland_build_helper`
Expected: 3 `ok` lines.

- [ ] **Step 5: Commit**

```bash
git add modules/desktop/hyprland/build/build-aquamarine.sh tests/test_hyprland_build_helper.sh
git commit -m "feat(hyprland): aquamarine rebuild helper (.so.3, atlas1 release)"
```

---

### Task B2: Failing tests for `module.sh`

**Files:**
- Test: `tests/test_module_hyprland.sh`

**Interfaces:**
- Consumes: the hooks `module::{check,install,verify,update,remove,backup,restore}` (defined in B3).
- Produces: the behavioral contract those hooks must satisfy.

- [ ] **Step 1: Write the failing test suite** (modeled on `tests/test_module_ghostty.sh`; sandboxes HOME/XDG/state, mocks `dnf`/`rpm`, asserts the marker lifecycle, additive install, config deploy with drift detection, and `remove = detach`)

```bash
cat > tests/test_module_hyprland.sh <<'EOF'
#!/usr/bin/env bash
# desktop/hyprland — hermetic. No test touches the host, /etc, dnf, or a session.
PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_CONFIG_HOME="$HOME/.config"; export XDG_CONFIG_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
DNF_LOG="$HOME/dnf.log"; export DNF_LOG; : > "$DNF_LOG"
RPMS="$HOME/atlas-hypr-rpms"; export RPMS
mkdir -p "$RPMS"
: > "$RPMS/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/hyprland/module.sh"

# point the module at the sandbox RPM dir + a stub build helper that "succeeds"
_hypr_rpm_path() { printf "%s\n" "$RPMS/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"; }
_hypr_build_rpm() { return 0; }        # pretend the artifact is present
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::dnf_install() { printf "%s\n" "$*" >> "$DNF_LOG"; [ "${DNF_FAIL:-0}" = 1 ] && return 1; return 0; }
_hypr_run_privileged() { "$@"; }
_hypr_dnf_install_local() { printf "install-local %s\n" "$*" >> "$DNF_LOG"; [ "${DNF_FAIL:-0}" = 1 ] && return 1; return 0; }
_hypr_hyprland_present() { [ "${HYPR_PRESENT:-0}" = 1 ]; }
'
PRE="${PRE%$'\n'}"

assert_status "hyprland check fails before install" 1 \
  bash -c "$PRE; module::check"

assert_status "hyprland verify passes before install (absent)" 0 \
  bash -c "$PRE; module::verify"

assert_status "hyprland install fails on non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_hypr_marker)\" ]; exit \"\${rc:-0}\""

assert_status "hyprland install writes installed marker" 0 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\""

assert_status "hyprland install deploys all five config trees" 0 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; for d in hypr waybar wofi mako kitty; do [ -e \"\$XDG_CONFIG_HOME/\$d\" ] || exit 1; done"

assert_status "hyprland install uses the local atlas1 aquamarine rpm" 0 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; grep -q 'aquamarine-0.9.5-2.fc44.atlas1' \"\$DNF_LOG\""

assert_status "hyprland check passes after install" 0 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; module::check"

assert_status "hyprland install is idempotent" 0 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; cp \"\$(_hypr_marker)\" \"\$HOME/m1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(_hypr_marker)\""

assert_status "hyprland verify fails when a managed config drifts" 1 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/waybar/config.jsonc\"; module::verify"

assert_status "hyprland update restores drift" 0 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/waybar/config.jsonc\"; module::update >/dev/null 2>&1; module::verify"

assert_status "hyprland install fails leave installing marker" 1 \
  bash -c "$PRE; HYPR_PRESENT=1 DNF_FAIL=1; export HYPR_PRESENT DNF_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "hyprland remove detaches configs but leaves packages" 0 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_hypr_marker)\"; [ ! -e \"\$XDG_CONFIG_HOME/hypr\" ]; ! grep -q 'dnf history undo' \"\$DNF_LOG\"; ! grep -qi 'remove' \"\$DNF_LOG\""

assert_status "hyprland remove is idempotent" 0 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; module::remove"

assert_status "hyprland backup is a documented no-op" 0 bash -c "$PRE; module::backup"
assert_status "hyprland restore is a documented no-op" 0 bash -c "$PRE; module::restore"
EOF
```

- [ ] **Step 2: Run to verify the suite fails**

Run: `bash tests/run.sh 2>&1 | grep -c FAIL`
Expected: multiple FAILs (module.sh not written yet — `source` of a missing file aborts each case).

---

### Task B3: Implement `module.sh` to pass the suite

**Files:**
- Create: `modules/desktop/hyprland/module.sh`

**Interfaces:**
- Consumes: `internal/{error,log,os}.sh` helpers; the staged configs under `modules/desktop/hyprland/config/`.
- Produces: `module::{check,install,verify,update,remove,backup,restore}`, plus `_hypr_marker`, `_hypr_rpm_path`, `_hypr_run_privileged`, `_hypr_dnf_install_local`, `_hypr_hyprland_present`, `_hypr_build_rpm` (the seams the tests override).

- [ ] **Step 1: Write the module.** The marker load/write and atomic-manifest deploy follow the Atlas convention. Reuse the **directory-manifest** approach from `modules/desktop/sddm/module.sh` (`find | sha256sum`) because this module owns five config trees, and the **marker schema + state machine** from `modules/development/ghostty/module.sh`. Below is the full module; the marker helper bodies are the ghostty ones with the `_ghostty_`→`_hypr_` rename and the marker path `installed/desktop-hyprland`.

```bash
cat > modules/desktop/hyprland/module.sh <<'EOF'
#!/usr/bin/env bash
# desktop/hyprland — the B&W Atlas Hyprland session, installed via a locally
# rebuilt aquamarine (0.9.5-2.fc44.atlas1, linked against libdisplay-info.so.3).
# Owns: the COPR intent, the local aquamarine RPM install, the hypr* package set,
# the five ~/.config trees, and the wallpaper bake. Does NOT own user config or
# uninstall packages on remove (detach only; package rollback is dnf history undo).
MODULE_NAME="hyprland"
MODULE_DESCRIPTION="Atlas Hyprland desktop: local aquamarine rebuild + hypr stack + B&W configs."
MODULE_DEPENDS=()

_HYPR_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_HYPR_CONFIG_TREES="hypr waybar wofi mako kitty"
_HYPR_PACKAGES="hyprland xdg-desktop-portal-hyprland hyprlock hypridle hyprpaper waybar wofi mako kitty grim slurp brightnessctl playerctl"

_hypr_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-hyprland"; }
_hypr_rpm_path() { printf '%s\n' "$HOME/atlas-hypr-rpms/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"; }
_hypr_cfg_src() { printf '%s\n' "$_HYPR_MODULE_DIR/config/$1"; }
_hypr_cfg_dst() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/$1"; }
_hypr_run_privileged() { if os::is_root; then "$@"; else sudo "$@"; fi; }
_hypr_hyprland_present() { os::has_cmd Hyprland || rpm -q hyprland >/dev/null 2>&1; }
_hypr_build_rpm() { bash "$_HYPR_MODULE_DIR/build/build-aquamarine.sh"; }

# Install the locally-built aquamarine RPM + the hypr stack in one dnf transaction.
_hypr_dnf_install_local() {
  local rpm; rpm="$(_hypr_rpm_path)"
  [ -f "$rpm" ] || { log::error "aquamarine RPM not built: $rpm (run build/build-aquamarine.sh)"; return 1; }
  # shellcheck disable=SC2086
  _hypr_run_privileged dnf install -y "$rpm" $_HYPR_PACKAGES
}

# --- directory manifest (drift detection over all five trees) ---------------
_hypr_manifest_src() { local d; for d in $_HYPR_CONFIG_TREES; do (cd "$(_hypr_cfg_src "$d")" 2>/dev/null && find . -type f -print | sort | xargs -r sha256sum | sed "s#\$# [$d]#"); done; }
_hypr_manifest_dst() { local d; for d in $_HYPR_CONFIG_TREES; do (cd "$(_hypr_cfg_dst "$d")" 2>/dev/null && find . -type f -print | sort | xargs -r sha256sum | sed "s#\$# [$d]#"); done; }
_hypr_configs_match() { [ "$(_hypr_manifest_src)" = "$(_hypr_manifest_dst)" ]; }

_hypr_deploy_configs() {
  local d src dst
  for d in $_HYPR_CONFIG_TREES; do
    src="$(_hypr_cfg_src "$d")"; dst="$(_hypr_cfg_dst "$d")"
    [ -d "$src" ] || { log::error "missing staged config: $src"; return 1; }
    mkdir -p "$(dirname "$dst")" || return 1
    rm -rf "$dst" || return 1
    cp -a "$src" "$dst" || return 1
  done
}

# --- marker (schema + state machine identical to ghostty; renamed) ----------
_hypr_marker_load() {  # sets _HYPR_STATE to absent|installing|installed|detached
  _HYPR_STATE=absent
  local m; m="$(_hypr_marker)"; [ -e "$m" ] || return 0
  [ -f "$m" ] && [ ! -L "$m" ] && [ -r "$m" ] || { log::error "hyprland marker not a readable file"; return 1; }
  [ "$(stat -c '%a' "$m" 2>/dev/null)" = 600 ] || { log::error "hyprland marker mode must be 600"; return 1; }
  local line s=0 t=0 val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; case "$line" in ""|\#*) continue ;; esac
    case "$line" in
      schema=1) s=1 ;;
      state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _HYPR_STATE="$val" ;; *) return 1 ;; esac; t=1 ;;
      *) return 1 ;;
    esac
  done < "$m"
  [ "$s" -eq 1 ] && [ "$t" -eq 1 ]
}
_hypr_marker_write() {
  local state="$1" m dir tmp; m="$(_hypr_marker)"; dir="$(dirname "$m")"
  mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-hyprland.XXXXXX")" || return 1
  { printf 'schema=1\nstate=%s\n' "$state"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$m" || { rm -f "$tmp"; return 1; }
}

module::check() {
  _hypr_marker_load || return 1
  [ "$_HYPR_STATE" = installed ] || return 1
  _hypr_hyprland_present || return 1
  _hypr_configs_match || return 1
}

module::install() {
  os::is_fedora || { log::error "hyprland module supports Fedora only"; return 1; }
  _hypr_marker_load || return 1
  _hypr_marker_write installing || return 1
  [ -f "$(_hypr_rpm_path)" ] || _hypr_build_rpm || { log::error "aquamarine build failed"; return 1; }
  _hypr_dnf_install_local || { log::error "hyprland package install failed"; return 1; }
  _hypr_deploy_configs || return 1
  bash "$_HYPR_MODULE_DIR/assets/generate.sh" >/dev/null 2>&1 || log::warn "wallpaper bake skipped"
  _hypr_configs_match || return 1
  _hypr_marker_write installed || return 1
  log::info "Atlas Hyprland is installed; pick it at the login screen"
}

module::verify() {
  _hypr_marker_load || return 1
  case "$_HYPR_STATE" in
    absent|detached) return 0 ;;
    installing) log::error "hyprland install incomplete; rerun install"; return 1 ;;
  esac
  _hypr_configs_match || { log::error "hyprland managed config has drifted"; return 1; }
  log::info "Atlas Hyprland config is healthy"
}

module::update() {
  _hypr_marker_load || return 1
  case "$_HYPR_STATE" in absent|detached) return 0 ;; esac
  _hypr_deploy_configs || return 1
  _hypr_marker_write installed || return 1
  _hypr_configs_match
}

module::remove() {  # detach: drop Atlas-owned configs; leave packages (rollback = dnf history undo)
  _hypr_marker_load || return 1
  case "$_HYPR_STATE" in absent|detached) return 0 ;; esac
  local d
  for d in $_HYPR_CONFIG_TREES; do rm -rf "$(_hypr_cfg_dst "$d")" || return 1; done
  _hypr_marker_write detached || return 1
  log::info "detached Hyprland configs; packages remain — roll them back with: sudo dnf history undo \$(cat ${ATLAS_STATE_DIR:-\$HOME/.local/state/atlas}/hypr-install-txn)"
}

module::backup() { log::info "nothing to back up: desktop/hyprland is reconstructable"; }
module::restore() { log::info "nothing to restore: reinstall desktop/hyprland"; }
EOF
```

- [ ] **Step 2: Run the suite to green**

Run: `bash tests/run.sh 2>&1 | grep -A20 test_module_hyprland`
Expected: every assertion prints `ok`, zero FAIL.

- [ ] **Step 3: Commit**

```bash
git add modules/desktop/hyprland/module.sh tests/test_module_hyprland.sh
git commit -m "feat(hyprland): reversible module.sh (local aquamarine + hypr stack + B&W configs)"
```

---

### Task B4: Repurpose the watcher and refresh the README

**Files:**
- Modify: `modules/desktop/hyprland/assets/watch-availability.sh`, `modules/desktop/hyprland/README.md`
- Test: extend `tests/test_hyprland_build_helper.sh` with a watcher-logic assertion

**Interfaces:**
- Consumes: the installed state from Part A.
- Produces: a watcher that announces *supersession* (our `.atlas` build replaced by the official one) instead of the now-moot *availability*.

- [ ] **Step 1: Write the failing watcher test** (append to `tests/test_hyprland_build_helper.sh`)

```bash
cat >> tests/test_hyprland_build_helper.sh <<'EOF'

WATCH="$ATLAS_ROOT/modules/desktop/hyprland/assets/watch-availability.sh"
assert_status "watcher checks for the atlas release marker, not .so.2" 0 \
  bash -c "grep -q 'atlas1\|\\.atlas' \"$WATCH\""
EOF
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/run.sh 2>&1 | grep 'atlas release marker'`
Expected: FAIL (the current watcher greps for `libdisplay-info.so.2`).

- [ ] **Step 3: Rewrite the watcher's detection branch.** Replace its "is aquamarine rebuilt against .so.3?" logic with "is the *installed* aquamarine still our `.atlas1` build?" — because once Hyprland is installed the old watcher self-disables and never fires. New logic (edit the relevant block in `watch-availability.sh`):

```bash
# Post-install mode: our local aquamarine is 0.9.5-2.fc44.atlas1. When the COPR
# ships an official rebuild, `dnf upgrade` replaces it and the .atlas1 release
# disappears — that is the "all clear, superseded" signal.
installed_rel="$(rpm -q --qf '%{RELEASE}\n' aquamarine 2>/dev/null || true)"
case "$installed_rel" in
  *.atlas1)
    echo "$(stamp) still on the Atlas local rebuild ($installed_rel)" >>"$LOG" ;;
  "")
    echo "$(stamp) aquamarine not installed; nothing to watch" >>"$LOG"
    systemctl --user disable --now atlas-hypr-check.timer >/dev/null 2>&1 || true ;;
  *)
    echo "$(stamp) SUPERSEDED: official aquamarine ($installed_rel) is in place" >>"$LOG"
    notify-send -a "Atlas" "Atlas · Hyprland renderer superseded" \
      "The official aquamarine rebuild ($installed_rel) has replaced the Atlas local build. No action needed." 2>/dev/null || true
    systemctl --user disable --now atlas-hypr-check.timer >/dev/null 2>&1 || true ;;
esac
```

- [ ] **Step 4: Update the README's "⚠ Blocked" section** — replace it with a "Shipped via local aquamarine rebuild" note: the desktop is installed from `aquamarine-0.9.5-2.fc44.atlas1`, which `dnf upgrade` auto-supersedes when the official `-3` lands; point at this plan and the build helper.

- [ ] **Step 5: Run tests, then commit**

Run: `bash tests/run.sh` → all green.

```bash
git add modules/desktop/hyprland/assets/watch-availability.sh modules/desktop/hyprland/README.md tests/test_hyprland_build_helper.sh
git commit -m "feat(hyprland): watcher announces supersession; README reflects local-rebuild install"
```

---

## Self-Review

**Spec coverage** (each spec section → task):
- §2 one-artifact reframing → A0 Steps 1-2 (audit + no-exact-pin), GATE A1 (`.so.8`/`.so.3`).
- §3 approach + Release tag → Global Constraints + A1 (Release `2%{?dist}.atlas1`, verified).
- §4 Phase 0 → A0; Phase 1 → A1; Phase 2 → A2; Phase 3 → A3; Phase 4 → A4; Phase 5 → B1-B4.
- §5 rollback/safety floor → A3 Step 2 (recorded txn id), GATE A3, A4 Step 2.
- §6 module.sh architecture → B3 (hooks, marker, ownership, detach), B1 (build split).
- §7 go/no-go 5-gate → A3 Step 4.
- §8 risk register → A1 Step 3 (build-fail patch/abort), GATE A2 (Plasma), A3 Step 4 #4 (hyprlock).
- §9 out of scope → not planned (correct).

**Placeholder scan:** no TBD/TODO; every step has an exact command or complete code block; expected outputs stated.

**Type/name consistency:** the tests in B2 override exactly the seams B3 defines (`_hypr_marker`, `_hypr_rpm_path`, `_hypr_run_privileged`, `_hypr_dnf_install_local`, `_hypr_hyprland_present`, `_hypr_build_rpm`); config-tree list `hypr waybar wofi mako kitty` matches between test assertions, `_HYPR_CONFIG_TREES`, and the staged `config/` dirs; the RPM filename `aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm` is identical across A1, A2, A3, B1, and the module.

**One deviation from the spec's wording, intentional and verified:** the spec's shorthand "`0.9.5-2.atlas1`" is realized as Release `2%{?dist}.atlas1` (`2.fc44.atlas1`) — the only form that sorts correctly (proven with `rpm.labelCompare` + `rpmdev-vercmp`). The design intent (installs now, yields to official `-3`) is preserved exactly.
