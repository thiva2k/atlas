#!/usr/bin/env bash
# desktop/lockscreen - RFC-0035

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/lockscreen/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
'
PRE="${PRE%$'\n'}"

assert_status "lockscreen verify passes before install" 0 bash -c "$PRE; module::verify"
assert_status "lockscreen check fails before install" 1 bash -c "$PRE; module::check"
assert_status "lockscreen install refuses existing package dir before mutation" 1 bash -c "$PRE; mkdir -p \"\$(_lockscreen_dir)\"; printf user > \"\$(_lockscreen_dir)/mine.txt\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_lockscreen_marker)\" ]; exit \"\${rc:-0}\""
assert_status "lockscreen install fails on non-Fedora before mutation" 1 bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_lockscreen_marker)\" ]; exit \"\${rc:-0}\""
assert_status "lockscreen install writes marker and package files" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_lockscreen_marker)\"; [ -r \"\$(_lockscreen_dir)/metadata.json\" ]; [ -r \"\$(_lockscreen_dir)/contents/lockscreen/LockScreen.qml\" ]; [ -r \"\$(_lockscreen_dir)/contents/lockscreen/LockScreenUi.qml\" ]"
# B&W word-only identity (2026-07-16, supersedes RFC-0037's orbital-A mark):
# the KSplash still ships, but the no-logo rule removed atlas-mark.png — the
# splash now renders the ASCII ATLAS masthead, not a graphic mark.
assert_status "lockscreen install ships the KSplash package alongside the lock-screen HUD (RFC-0037)" 0 bash -c "$PRE; module::install >/dev/null 2>&1; [ -r \"\$(_lockscreen_dir)/contents/splash/Splash.qml\" ]; ! [ -e \"\$(_lockscreen_dir)/contents/splash/images/atlas-mark.png\" ]"
assert_status "lockscreen metadata.json declares the org.atlas.hud id and LookAndFeel structure" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -q 'org.atlas.hud' \"\$(_lockscreen_dir)/metadata.json\"; grep -q 'Plasma/LookAndFeel' \"\$(_lockscreen_dir)/metadata.json\""
assert_status "lockscreen verify passes after install" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"
assert_status "lockscreen check passes after install" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::check"
assert_status "lockscreen repeated install is idempotent" 0 bash -c "$PRE; module::install >/dev/null 2>&1; find \"\$(_lockscreen_dir)\" -type f -print | sort | xargs sha256sum > \"\$HOME/s1\"; module::install >/dev/null 2>&1; find \"\$(_lockscreen_dir)\" -type f -print | sort | xargs sha256sum > \"\$HOME/s2\"; cmp -s \"\$HOME/s1\" \"\$HOME/s2\""
assert_status "lockscreen verify fails on drift" 1 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_lockscreen_dir)/metadata.json\"; module::verify"
assert_status "lockscreen check fails on drift" 1 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_lockscreen_dir)/metadata.json\"; module::check"
assert_status "lockscreen update restores drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_lockscreen_dir)/metadata.json\"; module::update >/dev/null 2>&1; module::verify"
assert_status "lockscreen remove detaches and deletes the package dir" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_lockscreen_marker)\"; [ ! -e \"\$(_lockscreen_dir)\" ]"
assert_status "lockscreen remove refuses drift" 1 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$(_lockscreen_dir)/metadata.json\"; module::remove"
assert_status "lockscreen backup no-op" 0 bash -c "$PRE; module::backup"
assert_status "lockscreen restore no-op" 0 bash -c "$PRE; module::restore"

# --- marker discipline ---------------------------------------------------------
assert_status "lockscreen marker mode must be 600" 1 bash -c "$PRE; module::install >/dev/null 2>&1; chmod 644 \"\$(_lockscreen_marker)\"; _lockscreen_marker_load 2>/dev/null"
assert_status "lockscreen marker rejects a symlink" 1 bash -c "$PRE; module::install >/dev/null 2>&1; m=\"\$(_lockscreen_marker)\"; mv \"\$m\" \"\$m.real\"; ln -s \"\$m.real\" \"\$m\"; _lockscreen_marker_load 2>/dev/null"
assert_status "lockscreen marker rejects an unknown key" 1 bash -c "$PRE; d=\"\$(dirname \"\$(_lockscreen_marker)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=installed\nmanifest_sha256=0000000000000000000000000000000000000000000000000000000000000000\nbogus=1\n' > \"\$(_lockscreen_marker)\"; chmod 600 \"\$(_lockscreen_marker)\"; _lockscreen_marker_load 2>/dev/null"
assert_status "lockscreen marker rejects an invalid manifest_sha256" 1 bash -c "$PRE; d=\"\$(dirname \"\$(_lockscreen_marker)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=installed\nmanifest_sha256=notahash\n' > \"\$(_lockscreen_marker)\"; chmod 600 \"\$(_lockscreen_marker)\"; _lockscreen_marker_load 2>/dev/null"

# --- in-place-upgrade-safe: marker_load must NOT hard-fail when the source content changes ---
# The module is re-sourced against a private copy of the module dir (never the real
# repo tree) so mutating the shipped source cannot dirty the working tree.
UPGRADE_PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
cp -r "$ATLAS_ROOT/modules/desktop/lockscreen" "$HOME/lockscreen-copy"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$HOME/lockscreen-copy/module.sh"
os::is_fedora() { return 0; }
'
UPGRADE_PRE="${UPGRADE_PRE%$'\n'}"

assert_status "lockscreen marker_load tolerates a shipped-source content change (in-place upgrade)" 0 bash -c "$UPGRADE_PRE; module::install >/dev/null 2>&1; printf '\n// vendor update\n' >> \"\$_LOCKSCREEN_MODULE_DIR/assets/org.atlas.hud/contents/lockscreen/LockScreenUi.qml\"; _lockscreen_marker_load"
assert_status "lockscreen verify still reports drift after an in-place source upgrade (no false-pass)" 1 bash -c "$UPGRADE_PRE; module::install >/dev/null 2>&1; printf '\n// vendor update\n' >> \"\$_LOCKSCREEN_MODULE_DIR/assets/org.atlas.hud/contents/lockscreen/LockScreenUi.qml\"; module::verify"
assert_status "lockscreen update re-syncs after an in-place source upgrade" 0 bash -c "$UPGRADE_PRE; module::install >/dev/null 2>&1; printf '\n// vendor update\n' >> \"\$_LOCKSCREEN_MODULE_DIR/assets/org.atlas.hud/contents/lockscreen/LockScreenUi.qml\"; module::update >/dev/null 2>&1; module::verify"
