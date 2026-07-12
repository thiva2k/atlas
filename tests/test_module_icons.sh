#!/usr/bin/env bash
# desktop/icons - RFC-0018

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
source "$ATLAS_ROOT/modules/desktop/icons/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
_icons_package_installed() { grep -qxF "$1" "$PKGS"; }
os::dnf_install() { printf "%s\n" "$*" >> "$DNF_LOG"; [ "${DNF_FAIL:-0}" = 1 ] && return 1; for p in "$@"; do printf "%s\n" "$p" >> "$PKGS"; done; }
'
PRE="${PRE%$'\n'}"

assert_status "icons verify passes before install" 0 bash -c "$PRE; module::verify"
assert_status "icons install uses package when missing" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF papirus-icon-theme \"\$DNF_LOG\"; module::verify"
assert_status "icons install skips package when present" 0 bash -c "$PRE; printf \"%s\n\" papirus-icon-theme > \"\$PKGS\"; module::install >/dev/null 2>&1; [ ! -s \"\$DNF_LOG\" ]; module::verify"
assert_status "icons repeated install is idempotent" 0 bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_icons_marker)\" \"\$HOME/m1\"; : > \"\$DNF_LOG\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(_icons_marker)\"; [ ! -s \"\$DNF_LOG\" ]"
assert_status "icons install fails on non-Fedora before mutation" 1 bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_icons_marker)\" ]; exit \"\${rc:-0}\""
assert_status "icons package failure leaves installing marker" 1 bash -c "$PRE; DNF_FAIL=1; export DNF_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_icons_marker)\"; exit \"\${rc:-0}\""
assert_status "icons verify fails when managed package missing" 1 bash -c "$PRE; _icons_marker_write installed; module::verify"
assert_status "icons remove detaches without uninstalling" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_icons_marker)\"; grep -qxF papirus-icon-theme \"\$PKGS\""
assert_status "icons backup no-op" 0 bash -c "$PRE; module::backup"
assert_status "icons restore no-op" 0 bash -c "$PRE; module::restore"
