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
'
PRE="${PRE%$'\n'}"

assert_status "plymouth verify passes before install" 0 bash -c "$PRE; module::verify"
assert_status "plymouth install refuses existing dir" 1 bash -c "$PRE; mkdir -p \"\$PLYMOUTH_DIR\"; printf user > \"\$PLYMOUTH_DIR/user\"; module::install"
assert_status "plymouth install writes theme" 0 bash -c "$PRE; module::install >/dev/null 2>&1; [ -r \"\$PLYMOUTH_DIR/atlas.plymouth\" ]; [ -r \"\$PLYMOUTH_DIR/atlas.script\" ]; module::verify"
assert_status "plymouth uses sudo wrapper when not root" 0 bash -c "$PRE; SUDO_LOG=\"\$HOME/sudo.log\"; os::is_root() { return 1; }; sudo() { printf \"%s\n\" \"\$*\" >> \"\$SUDO_LOG\"; \"\$@\"; }; module::install >/dev/null 2>&1; grep -q \"mkdir -p\" \"\$SUDO_LOG\"; grep -q \"mv\" \"\$SUDO_LOG\"; module::verify"
assert_status "plymouth update restores drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$PLYMOUTH_DIR/atlas.script\"; module::update >/dev/null 2>&1; module::verify"
assert_status "plymouth remove detaches" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_plymouth_marker)\"; [ ! -e \"\$PLYMOUTH_DIR\" ]"
