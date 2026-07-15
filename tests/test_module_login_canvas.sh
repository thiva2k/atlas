#!/usr/bin/env bash
# desktop/login-canvas - RFC-0036

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/login-canvas/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
# Sandbox the SOURCE asset: tests that simulate a source release must never write
# the real repo asset. Copy it into the temp HOME and point the source there.
mkdir -p "$HOME/src"; cp "$ATLAS_ROOT/modules/desktop/login-canvas/assets/atlas-login-canvas.png" "$HOME/src/atlas-login-canvas.png"
_login_canvas_asset_source() { printf "%s\n" "$HOME/src/atlas-login-canvas.png"; }
'
PRE="${PRE%$'\n'}"

assert_status "login-canvas verify passes before install" 0 bash -c "$PRE; module::verify"
assert_status "login-canvas check fails before install" 1 bash -c "$PRE; module::check"
assert_status "login-canvas install refuses existing asset before mutation" 1 bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_login_canvas_asset_file)\")\"; printf user > \"\$(_login_canvas_asset_file)\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_login_canvas_marker)\" ]; exit \"\${rc:-0}\""
assert_status "login-canvas install fails on non-Fedora before mutation" 1 bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_login_canvas_marker)\" ]; exit \"\${rc:-0}\""
assert_status "login-canvas install writes marker and asset" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_login_canvas_marker)\"; [ -r \"\$(_login_canvas_asset_file)\" ]; cmp -s \"\$(_login_canvas_asset_source)\" \"\$(_login_canvas_asset_file)\""
assert_status "login-canvas verify passes after install" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"
assert_status "login-canvas check passes after install" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::check"
assert_status "login-canvas repeated install is idempotent" 0 bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_login_canvas_marker)\" \"\$HOME/m1\"; cp \"\$(_login_canvas_asset_file)\" \"\$HOME/a1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(_login_canvas_marker)\"; cmp -s \"\$HOME/a1\" \"\$(_login_canvas_asset_file)\""
assert_status "login-canvas verify fails on drift" 1 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_login_canvas_asset_file)\"; module::verify"
assert_status "login-canvas update restores drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_login_canvas_asset_file)\"; module::update >/dev/null 2>&1; module::verify"
assert_status "login-canvas remove detaches and deletes asset" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_login_canvas_marker)\"; [ ! -e \"\$(_login_canvas_asset_file)\" ]"
assert_status "login-canvas remove refuses drift" 1 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_login_canvas_asset_file)\"; module::remove"
assert_status "login-canvas backup no-op" 0 bash -c "$PRE; module::backup"
assert_status "login-canvas restore no-op" 0 bash -c "$PRE; module::restore"

# --- in-place-upgrade-safe marker discipline (RFC-0034 fish/fastfetch fix) --------
# marker_load must validate only its OWN structure, never fail because the shipped
# source asset's bytes changed across an Atlas release (that drift is judged only by
# _login_canvas_asset_matches from check/verify/update, never from marker_load).
assert_status "marker_load never encodes the asset hash; a changed source doesn't break load" 0 bash -c "$PRE; module::install >/dev/null 2>&1; printf newrelease > \"\$(_login_canvas_asset_source)\"; _login_canvas_marker_load; grep -qxF state=installed \"\$(_login_canvas_marker)\""
assert_status "update after a source release re-syncs the asset and verify passes" 0 bash -c "$PRE; module::install >/dev/null 2>&1; printf newrelease > \"\$(_login_canvas_asset_source)\"; module::update >/dev/null 2>&1; module::verify; cmp -s \"\$(_login_canvas_asset_source)\" \"\$(_login_canvas_asset_file)\""

# --- marker strict parser -----------------------------------------------------------
assert_status "marker load rejects unknown line" 1 bash -c "$PRE; d=\"\$(dirname \"\$(_login_canvas_marker)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=installed\nbogus=1\n' > \"\$(_login_canvas_marker)\"; chmod 600 \"\$(_login_canvas_marker)\"; _login_canvas_marker_load 2>/dev/null"
assert_status "marker load rejects invalid state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(_login_canvas_marker)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=bogus\n' > \"\$(_login_canvas_marker)\"; chmod 600 \"\$(_login_canvas_marker)\"; _login_canvas_marker_load 2>/dev/null"
assert_status "marker load rejects mode != 600" 1 bash -c "$PRE; d=\"\$(dirname \"\$(_login_canvas_marker)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=installed\n' > \"\$(_login_canvas_marker)\"; chmod 644 \"\$(_login_canvas_marker)\"; _login_canvas_marker_load 2>/dev/null"
