#!/usr/bin/env bash
# desktop/wallpapers - RFC-0021

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/wallpapers/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
'
PRE="${PRE%$'\n'}"

assert_status "wallpapers verify passes before install" 0 bash -c "$PRE; module::verify"
assert_status "wallpapers install refuses existing directory before mutation" 1 bash -c "$PRE; mkdir -p \"\$(_wallpapers_dir)\"; printf user > \"\$(_wallpapers_dir)/mine.svg\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_wallpapers_marker)\" ]; exit \"\${rc:-0}\""
assert_status "wallpapers install writes marker and collection" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_wallpapers_marker)\"; [ -r \"\$(_wallpapers_dir)/atlas-gradient.svg\" ]; [ -r \"\$(_wallpapers_dir)/atlas-grid.svg\" ]; [ -r \"\$(_wallpapers_dir)/atlas-orbit.svg\" ]"
assert_status "wallpapers verify passes after install" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"
assert_status "wallpapers repeated install is idempotent" 0 bash -c "$PRE; module::install >/dev/null 2>&1; find \"\$(_wallpapers_dir)\" -type f -print | sort | xargs sha256sum > \"\$HOME/s1\"; module::install >/dev/null 2>&1; find \"\$(_wallpapers_dir)\" -type f -print | sort | xargs sha256sum > \"\$HOME/s2\"; cmp -s \"\$HOME/s1\" \"\$HOME/s2\""
assert_status "wallpapers verify fails on drift" 1 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_wallpapers_dir)/atlas-gradient.svg\"; module::verify"
assert_status "wallpapers update restores drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_wallpapers_dir)/atlas-gradient.svg\"; module::update >/dev/null 2>&1; module::verify"
assert_status "wallpapers remove detaches and deletes collection" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_wallpapers_marker)\"; [ ! -e \"\$(_wallpapers_dir)\" ]"
assert_status "wallpapers backup no-op" 0 bash -c "$PRE; module::backup"
assert_status "wallpapers restore no-op" 0 bash -c "$PRE; module::restore"
