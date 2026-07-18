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
# seam: never bake real wallpapers in tests
_hypr_bake_wallpapers() { return 0; }
'
PRE="${PRE%$'\n'}"

assert_status "hyprland check fails before install" 1 \
  bash -c "$PRE; module::check"

assert_status "hyprland verify passes before install (absent)" 0 \
  bash -c "$PRE; module::verify"

assert_status "hyprland install fails on non-Fedora before mutation" 0 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; if module::install >/dev/null 2>&1; then exit 9; fi; [ ! -e \"\$(_hypr_marker)\" ]"

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

assert_status "hyprland install fails leave installing marker" 0 \
  bash -c "$PRE; HYPR_PRESENT=1 DNF_FAIL=1; export HYPR_PRESENT DNF_FAIL; if module::install >/dev/null 2>&1; then exit 9; fi; grep -qxF state=installing \"\$(_hypr_marker)\""

assert_status "hyprland remove detaches configs but leaves packages" 0 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_hypr_marker)\"; [ ! -e \"\$XDG_CONFIG_HOME/hypr\" ]; ! grep -q 'dnf history undo' \"\$DNF_LOG\"; ! grep -qi 'remove' \"\$DNF_LOG\""

assert_status "hyprland remove is idempotent" 0 \
  bash -c "$PRE; HYPR_PRESENT=1; export HYPR_PRESENT; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; module::remove"

assert_status "hyprland backup is a documented no-op" 0 bash -c "$PRE; module::backup"
assert_status "hyprland restore is a documented no-op" 0 bash -c "$PRE; module::restore"
