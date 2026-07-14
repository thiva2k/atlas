#!/usr/bin/env bash
# desktop/plymouth - RFC-0024

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
PLYMOUTH_DIR="$HOME/usr/share/plymouth/themes/atlas"; export PLYMOUTH_DIR
source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/os.sh"; source "$ATLAS_ROOT/modules/desktop/plymouth/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::is_root() { return 0; }
_plymouth_theme_dir() { printf "%s\n" "$PLYMOUTH_DIR"; }
# RFC-0024a: hermetic mocks — no real dnf/sudo/rpm on the test host.
# Plugin present by default (existing asserts stay green); a test removes
# PLUGIN_STATE to simulate the buggy field state (theme present, plugin absent).
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
PLUGIN_STATE="$HOME/plugin_installed"; export PLUGIN_STATE
: > "$PLUGIN_STATE"
os::pkg_installed() { [ "$1" = plymouth-plugin-script ] && { [ -e "$PLUGIN_STATE" ]; return; }; return 0; }
os::dnf_install() { printf "%s\n" "$*" >> "$DNF_LOG"; for _p in "$@"; do [ "$_p" = plymouth-plugin-script ] && : > "$PLUGIN_STATE"; done; }
'
PRE="${PRE%$'\n'}"

assert_status "plymouth verify passes before install" 0 bash -c "$PRE; module::verify"
assert_status "plymouth install refuses existing dir" 1 bash -c "$PRE; mkdir -p \"\$PLYMOUTH_DIR\"; printf user > \"\$PLYMOUTH_DIR/user\"; module::install"
assert_status "plymouth install writes theme" 0 bash -c "$PRE; module::install >/dev/null 2>&1; [ -r \"\$PLYMOUTH_DIR/atlas.plymouth\" ]; [ -r \"\$PLYMOUTH_DIR/atlas.script\" ]; module::verify"
assert_status "plymouth uses sudo wrapper when not root" 0 bash -c "$PRE; SUDO_LOG=\"\$HOME/sudo.log\"; os::is_root() { return 1; }; sudo() { printf \"%s\n\" \"\$*\" >> \"\$SUDO_LOG\"; \"\$@\"; }; module::install >/dev/null 2>&1; grep -q \"mkdir -p\" \"\$SUDO_LOG\"; grep -q \"mv\" \"\$SUDO_LOG\"; module::verify"
assert_status "plymouth update restores drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$PLYMOUTH_DIR/atlas.script\"; module::update >/dev/null 2>&1; module::verify"
assert_status "plymouth remove detaches" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_plymouth_marker)\"; [ ! -e \"\$PLYMOUTH_DIR\" ]"
# RFC-0024a regression tests.
assert_status "plymouth install installs the script plugin" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -qw plymouth-plugin-script \"\$DNF_LOG\""
assert_status "plymouth check FAILS when plugin absent though theme matches" 1 bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$PLUGIN_STATE\"; module::check"
assert_status "plymouth verify FAILS when plugin absent though theme matches" 1 bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$PLUGIN_STATE\"; module::verify 2>/dev/null"
assert_status "plymouth check passes when theme and plugin both present" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::check"
# Field-machine self-heal: marker=installed + theme matches but plugin absent (the
# exact shipped-bug state) -> check fails, so install re-runs and installs the plugin.
assert_status "plymouth field machine self-heals: check fails then install installs plugin" 0 bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$PLUGIN_STATE\"; : > \"\$DNF_LOG\"; if module::check; then exit 1; fi; module::install >/dev/null 2>&1; grep -qw plymouth-plugin-script \"\$DNF_LOG\"; module::check"
