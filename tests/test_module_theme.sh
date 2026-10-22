#!/usr/bin/env bash
# desktop/theme - RFC-0017

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/theme/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
'
PRE="${PRE%$'\n'}"

assert_status "theme verify passes before install" 0 bash -c "$PRE; module::verify"
assert_status "theme check fails before install" 1 bash -c "$PRE; module::check"
assert_status "theme install refuses existing asset before mutation" 1 bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_theme_asset_file)\")\"; printf user > \"\$(_theme_asset_file)\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_theme_marker)\" ]; exit \"\${rc:-0}\""
assert_status "theme install fails on non-Fedora before mutation" 1 bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_theme_marker)\" ]; exit \"\${rc:-0}\""
assert_status "theme install writes marker and color scheme" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_theme_marker)\"; grep -q \"Atlas Blue\" \"\$(_theme_asset_file)\""
assert_status "theme verify passes after install" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"
assert_status "theme repeated install is idempotent" 0 bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_theme_marker)\" \"\$HOME/m1\"; cp \"\$(_theme_asset_file)\" \"\$HOME/a1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(_theme_marker)\"; cmp -s \"\$HOME/a1\" \"\$(_theme_asset_file)\""
assert_status "theme verify fails on drift" 1 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_theme_asset_file)\"; module::verify"
assert_status "theme update restores drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_theme_asset_file)\"; module::update >/dev/null 2>&1; module::verify"
assert_status "theme remove detaches and deletes asset" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_theme_marker)\"; [ ! -e \"\$(_theme_asset_file)\" ]"
assert_status "theme remove refuses drift" 1 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_theme_asset_file)\"; module::remove"
assert_status "theme backup no-op" 0 bash -c "$PRE; module::backup"
assert_status "theme restore no-op" 0 bash -c "$PRE; module::restore"

