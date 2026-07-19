#!/usr/bin/env bash
# desktop/hyprland — RFC-0038. Hermetic: sandboxed HOME/XDG/state, mocked dnf/rpm.
# Includes regressions for comparative-review blocking findings.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_CONFIG_HOME="$HOME/.config"; export XDG_CONFIG_HOME
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
ATLAS_HYPR_RPM_DIR="$HOME/atlas-hypr-rpms"; export ATLAS_HYPR_RPM_DIR
ATLAS_HYPR_REPO_FILE="$HOME/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:solopasha:hyprland.repo"
export ATLAS_HYPR_REPO_FILE
ATLAS_HYPR_WATCHER_BIN="$HOME/.local/bin/atlas-hypr-check.sh"; export ATLAS_HYPR_WATCHER_BIN
DNF_LOG="$HOME/dnf.log"; export DNF_LOG; : > "$DNF_LOG"
REHEARSE_LOG="$HOME/rehearse.log"; export REHEARSE_LOG; : > "$REHEARSE_LOG"
SYSTEMCTL_LOG="$HOME/systemctl.log"; export SYSTEMCTL_LOG; : > "$SYSTEMCTL_LOG"
mkdir -p "$ATLAS_HYPR_RPM_DIR" "$HOME/etc/yum.repos.d" "$HOME/.local/bin"
printf "ID=fedora\nVERSION_ID=44\n" > "$HOME/etc/os-release"
printf "Fedora release 44 (Forty Four)\n" > "$HOME/etc/fedora-release"
export ATLAS_HYPR_OS_RELEASE_FILE="$HOME/etc/os-release"
export ATLAS_HYPR_FEDORA_RELEASE_FILE="$HOME/etc/fedora-release"
: > "$ATLAS_HYPR_RPM_DIR/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"
export ATLAS_HYPR_TXN_ID=42

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/hyprland/module.sh"

_hypr_rpm_path() { printf "%s\n" "$ATLAS_HYPR_RPM_DIR/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"; }
_hypr_build_rpm() { return 0; }
_hypr_run_privileged() { "$@"; }
_hypr_hyprland_present() { [ "${HYPR_PRESENT:-0}" = 1 ]; }
_hypr_fedora_44() { [ "${FEDORA44_OK:-1}" = 1 ]; }
_hypr_rpm_gate() { [ "${RPM_GATE_OK:-1}" = 1 ]; }
_hypr_dnf_copr_available() { [ "${DNF_COPR:-0}" = 1 ]; }
_hypr_systemctl_user() { printf "%s\n" "$*" >> "$SYSTEMCTL_LOG"; return 0; }
_hypr_preview_bake_wallpapers() {
  # Test seam: expected walls are content "expected-<name>"
  local out="$1" f
  mkdir -p "$out"
  for f in atlas-lock-bg.png atlas-wall-bw.png; do
    printf "expected-%s\n" "$f" > "$out/$f"
  done
}
_hypr_rehearse_transaction() {
  printf "rehearse\n" >> "$REHEARSE_LOG"
  [ "${REHEARSE_FAIL:-0}" = 1 ] && return 1
  return 0
}
_hypr_dnf_install_local() {
  printf "install-local %s\n" "$*" >> "$DNF_LOG"
  [ "${DNF_FAIL:-0}" = 1 ] && return 1
  HYPR_PRESENT=1; export HYPR_PRESENT
  return 0
}
_hypr_write_repo() {
  printf "copr-enable\n" >> "$DNF_LOG"
  [ "${COPR_FAIL:-0}" = 1 ] && return 1
  DNF_COPR=1; export DNF_COPR
  mkdir -p "$(dirname "$ATLAS_HYPR_REPO_FILE")"
  printf "[%s]\nname=Copr hyprland\nbaseurl=https://example.test/\nenabled=1\ngpgcheck=1\n" \
    "copr:copr.fedorainfracloud.org:solopasha:hyprland" > "$ATLAS_HYPR_REPO_FILE"
}
_hypr_record_txn_id() {
  mkdir -p "$(dirname "$(_hypr_txn_file)")"
  local id="${ATLAS_HYPR_TXN_ID:-42}"
  _hypr_txn_id_valid "$id" || return 1
  printf "%s\n" "$id" > "$(_hypr_txn_file)"
  chmod 600 "$(_hypr_txn_file)"
}
_hypr_bake_wallpapers() {
  local dir f
  dir="$(_hypr_wall_dir)"
  mkdir -p "$dir"
  for f in atlas-lock-bg.png atlas-wall-bw.png; do
    printf "wall-%s\n" "$f" > "$dir/$f"
  done
  _hypr_record_wall_hashes
}
'
PRE="${PRE%$'\n'}"

assert_status "hyprland check fails before install" 1 \
  bash -c "$PRE; module::check"

assert_status "hyprland verify passes before install (absent)" 0 \
  bash -c "$PRE; module::verify"

assert_status "hyprland install fails on non-Fedora-44 before mutation" 1 \
  bash -c "$PRE; FEDORA44_OK=0; export FEDORA44_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_hypr_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "hyprland install writes installed marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\""

assert_status "hyprland install enables COPR before packages" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -q copr-enable \"\$DNF_LOG\"; [ -f \"\$ATLAS_HYPR_REPO_FILE\" ]"

assert_status "hyprland install deploys all five config trees" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; for d in hypr waybar wofi mako kitty; do [ -d \"\$XDG_CONFIG_HOME/\$d\" ] || exit 1; done"

assert_status "hyprland install uses the local atlas1 aquamarine rpm" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -q 'aquamarine-0.9.5-2.fc44.atlas1' \"\$DNF_LOG\""

assert_status "hyprland install records numeric dnf history id" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF 42 \"\$(_hypr_txn_file)\"; _hypr_txn_ok"

assert_status "hyprland install bakes both wallpapers" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ -f \"\$(_hypr_wall_dst atlas-lock-bg.png)\" ] && [ -f \"\$(_hypr_wall_dst atlas-wall-bw.png)\" ]"

assert_status "hyprland install deploys watcher units" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ -x \"\$ATLAS_HYPR_WATCHER_BIN\" ]; [ -f \"\$XDG_CONFIG_HOME/systemd/user/atlas-hypr-check.timer\" ]; grep -q enable \"\$SYSTEMCTL_LOG\""

assert_status "hyprland check passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::check"

assert_status "hyprland install is idempotent without re-running dnf" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; : > \"\$DNF_LOG\"; : > \"\$REHEARSE_LOG\"; module::install >/dev/null 2>&1; [ ! -s \"\$DNF_LOG\" ]; [ ! -s \"\$REHEARSE_LOG\" ]"

assert_status "hyprland verify fails when a managed config drifts" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/waybar/config.jsonc\"; module::verify"

assert_status "hyprland verify fails when txn id is unknown" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf unknown > \"\$(_hypr_txn_file)\"; module::verify"

assert_status "hyprland update restores drift" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/waybar/config.jsonc\"; module::update >/dev/null 2>&1; module::verify"

assert_status "hyprland update refuses while installing" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; _hypr_marker_write installing; module::update >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "hyprland install fail leaves installing marker" 1 \
  bash -c "$PRE; DNF_FAIL=1; export DNF_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "hyprland non-additive rehearsal aborts before install" 1 \
  bash -c "$PRE; REHEARSE_FAIL=1; export REHEARSE_FAIL; module::install >/dev/null 2>&1 || rc=\$?; ! grep -q install-local \"\$DNF_LOG\"; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "hyprland rpm gate failure aborts before dnf" 1 \
  bash -c "$PRE; RPM_GATE_OK=0; export RPM_GATE_OK; module::install >/dev/null 2>&1 || rc=\$?; ! grep -q install-local \"\$DNF_LOG\"; exit \"\${rc:-0}\""

assert_status "hyprland refuses unmanaged differing config before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$XDG_CONFIG_HOME/hypr\"; echo user > \"\$XDG_CONFIG_HOME/hypr/user.conf\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_hypr_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "hyprland refuses differing wallpapers without sidecar" 1 \
  bash -c "$PRE; mkdir -p \"\$(_hypr_wall_dir)\"; echo foreign > \"\$(_hypr_wall_dst atlas-lock-bg.png)\"; echo foreign > \"\$(_hypr_wall_dst atlas-wall-bw.png)\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_hypr_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "hyprland adopts byte-identical pre-staged config" 0 \
  bash -c "$PRE; mkdir -p \"\$XDG_CONFIG_HOME\"; cp -a \"\$_HYPR_MODULE_DIR/config/hypr\" \"\$XDG_CONFIG_HOME/hypr\"; cp -a \"\$_HYPR_MODULE_DIR/config/waybar\" \"\$XDG_CONFIG_HOME/waybar\"; cp -a \"\$_HYPR_MODULE_DIR/config/wofi\" \"\$XDG_CONFIG_HOME/wofi\"; cp -a \"\$_HYPR_MODULE_DIR/config/mako\" \"\$XDG_CONFIG_HOME/mako\"; cp -a \"\$_HYPR_MODULE_DIR/config/kitty\" \"\$XDG_CONFIG_HOME/kitty\"; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\""

assert_status "hyprland remove detaches configs and undeploys watcher" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_hypr_marker)\"; [ ! -e \"\$XDG_CONFIG_HOME/hypr\" ]; [ ! -e \"\$ATLAS_HYPR_WATCHER_BIN\" ]; [ -f \"\$(_hypr_txn_file)\" ]; ! grep -qi remove \"\$DNF_LOG\"; grep -q disable \"\$SYSTEMCTL_LOG\""

assert_status "hyprland remove refuses on config drift" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/kitty/kitty.conf\"; module::remove >/dev/null 2>&1 || rc=\$?; grep -qxF state=installed \"\$(_hypr_marker)\"; [ -d \"\$XDG_CONFIG_HOME/kitty\" ]; exit \"\${rc:-0}\""

assert_status "hyprland remove is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; module::remove"

assert_status "hyprland backup is a documented no-op" 0 bash -c "$PRE; module::backup"
assert_status "hyprland restore is a documented no-op" 0 bash -c "$PRE; module::restore"

# --- rehearsal parser unit checks (fail-closed) -----------------------------
assert_status "rehearse parser accepts clean install-only plan" 0 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Installing:
  hyprland-1.0
  waybar-1.0
\""

assert_status "rehearse parser rejects removals" 1 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Removing:
  plasma-workspace-6.0
\""

assert_status "rehearse parser rejects non-hypr upgrades" 1 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Upgrading:
  systemd-257
\""

assert_status "rehearse parser allows hypr package upgrades" 0 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Upgrading:
  hyprland-0.50
  aquamarine-0.9.5
\""

assert_status "txn id unknown is invalid" 1 \
  bash -c "$PRE; _hypr_txn_id_valid unknown"

assert_status "txn id numeric is valid" 0 \
  bash -c "$PRE; _hypr_txn_id_valid 42"
