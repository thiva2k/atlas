#!/usr/bin/env bash
# desktop/hyprland — RFC-0038. Hermetic: sandboxed HOME/XDG/state, mocked dnf/rpm.
# No test touches the host, /etc, live COPR, or a Wayland session.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_CONFIG_HOME="$HOME/.config"; export XDG_CONFIG_HOME
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
ATLAS_HYPR_RPM_DIR="$HOME/atlas-hypr-rpms"; export ATLAS_HYPR_RPM_DIR
DNF_LOG="$HOME/dnf.log"; export DNF_LOG; : > "$DNF_LOG"
REHEARSE_LOG="$HOME/rehearse.log"; export REHEARSE_LOG; : > "$REHEARSE_LOG"
mkdir -p "$ATLAS_HYPR_RPM_DIR" "$HOME/etc"
# Fake Fedora 44 release files
printf "ID=fedora\nVERSION_ID=44\n" > "$HOME/etc/os-release"
printf "Fedora release 44 (Forty Four)\n" > "$HOME/etc/fedora-release"
export ATLAS_HYPR_OS_RELEASE_FILE="$HOME/etc/os-release"
export ATLAS_HYPR_FEDORA_RELEASE_FILE="$HOME/etc/fedora-release"

# Staged gated RPM stub (content unused; rpm mock gates)
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
_hypr_rpm_gate() {
  [ "${RPM_GATE_OK:-1}" = 1 ] || return 1
  return 0
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
_hypr_record_txn_id() {
  mkdir -p "$(dirname "$(_hypr_txn_file)")"
  printf "%s\n" "${ATLAS_HYPR_TXN_ID:-42}" > "$(_hypr_txn_file)"
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

assert_status "hyprland install deploys all five config trees" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; for d in hypr waybar wofi mako kitty; do [ -d \"\$XDG_CONFIG_HOME/\$d\" ] || exit 1; done"

assert_status "hyprland install uses the local atlas1 aquamarine rpm" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -q 'aquamarine-0.9.5-2.fc44.atlas1' \"\$DNF_LOG\""

assert_status "hyprland install records dnf history id" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF 42 \"\$(_hypr_txn_file)\""

assert_status "hyprland install bakes both wallpapers" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ -f \"\$(_hypr_wall_dst atlas-lock-bg.png)\" ] && [ -f \"\$(_hypr_wall_dst atlas-wall-bw.png)\" ]"

assert_status "hyprland check passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::check"

assert_status "hyprland install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_hypr_marker)\" \"\$HOME/m1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(_hypr_marker)\""

assert_status "hyprland verify fails when a managed config drifts" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/waybar/config.jsonc\"; module::verify"

assert_status "hyprland update restores drift" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/waybar/config.jsonc\"; module::update >/dev/null 2>&1; module::verify"

assert_status "hyprland install fail leaves installing marker" 1 \
  bash -c "$PRE; DNF_FAIL=1; export DNF_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "hyprland non-additive rehearsal aborts before install" 1 \
  bash -c "$PRE; REHEARSE_FAIL=1; export REHEARSE_FAIL; module::install >/dev/null 2>&1 || rc=\$?; [ ! -s \"\$DNF_LOG\" ]; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "hyprland rpm gate failure aborts before dnf" 1 \
  bash -c "$PRE; RPM_GATE_OK=0; export RPM_GATE_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "hyprland refuses unmanaged differing config before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$XDG_CONFIG_HOME/hypr\"; echo user > \"\$XDG_CONFIG_HOME/hypr/user.conf\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_hypr_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "hyprland adopts byte-identical pre-staged config" 0 \
  bash -c "$PRE; mkdir -p \"\$XDG_CONFIG_HOME\"; cp -a \"\$_HYPR_MODULE_DIR/config/hypr\" \"\$XDG_CONFIG_HOME/hypr\"; cp -a \"\$_HYPR_MODULE_DIR/config/waybar\" \"\$XDG_CONFIG_HOME/waybar\"; cp -a \"\$_HYPR_MODULE_DIR/config/wofi\" \"\$XDG_CONFIG_HOME/wofi\"; cp -a \"\$_HYPR_MODULE_DIR/config/mako\" \"\$XDG_CONFIG_HOME/mako\"; cp -a \"\$_HYPR_MODULE_DIR/config/kitty\" \"\$XDG_CONFIG_HOME/kitty\"; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\""

assert_status "hyprland remove detaches configs but leaves packages" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_hypr_marker)\"; [ ! -e \"\$XDG_CONFIG_HOME/hypr\" ]; [ -f \"\$(_hypr_txn_file)\" ]; ! grep -qi remove \"\$DNF_LOG\"; ! grep -q \"history undo\" \"\$DNF_LOG\""

assert_status "hyprland remove refuses on config drift" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/kitty/kitty.conf\"; module::remove >/dev/null 2>&1 || rc=\$?; grep -qxF state=installed \"\$(_hypr_marker)\"; [ -d \"\$XDG_CONFIG_HOME/kitty\" ]; exit \"\${rc:-0}\""

assert_status "hyprland remove is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; module::remove"

assert_status "hyprland backup is a documented no-op" 0 bash -c "$PRE; module::backup"
assert_status "hyprland restore is a documented no-op" 0 bash -c "$PRE; module::restore"
