#!/usr/bin/env bash
# desktop/utilities - RFC-0020

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
DNF_LOG="$HOME/dnf.log"; export DNF_LOG; : > "$DNF_LOG"
PKGS="$HOME/pkgs"; export PKGS; : > "$PKGS"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/utilities/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
_utilities_package_installed() { grep -qxF "$1" "$PKGS"; }
os::dnf_install() { printf "%s\n" "$*" >> "$DNF_LOG"; [ "${DNF_FAIL:-0}" = 1 ] && return 1; for p in "$@"; do printf "%s\n" "$p" >> "$PKGS"; done; }
'
PRE="${PRE%$'\n'}"

assert_status "utilities verify passes before install" 0 bash -c "$PRE; module::verify"
assert_eq "utilities install only missing packages" "$(bash -c "$PRE; printf \"bat\\nripgrep\\n\" > \"\$PKGS\"; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")" "btop fd-find eza zoxide"
assert_status "utilities verify passes after install" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"
assert_status "utilities repeated install is idempotent" 0 bash -c "$PRE; module::install >/dev/null 2>&1; : > \"\$DNF_LOG\"; module::install >/dev/null 2>&1; [ ! -s \"\$DNF_LOG\" ]"
assert_status "utilities install fails on non-Fedora before mutation" 1 bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_utilities_marker)\" ]; exit \"\${rc:-0}\""
assert_status "utilities verify fails when managed package missing" 1 bash -c "$PRE; _utilities_marker_write installed; module::verify"
assert_status "utilities remove detaches without uninstalling" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_utilities_marker)\"; grep -qxF btop \"\$PKGS\""
assert_status "utilities backup no-op" 0 bash -c "$PRE; module::backup"
assert_status "utilities restore no-op" 0 bash -c "$PRE; module::restore"

