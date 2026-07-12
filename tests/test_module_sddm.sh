#!/usr/bin/env bash
# desktop/sddm - RFC-0025

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
SDDM_THEME_DIR="$HOME/usr/share/sddm/themes/atlas"; export SDDM_THEME_DIR
SDDM_CONF="$HOME/etc/sddm.conf.d/90-atlas-theme.conf"; export SDDM_CONF
source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/os.sh"; source "$ATLAS_ROOT/modules/desktop/sddm/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::is_root() { return 0; }
_sddm_theme_dir() { printf "%s\n" "$SDDM_THEME_DIR"; }
_sddm_config_file() { printf "%s\n" "$SDDM_CONF"; }
'
PRE="${PRE%$'\n'}"

assert_status "sddm verify passes before install" 0 bash -c "$PRE; module::verify"
assert_status "sddm install refuses existing config" 1 bash -c "$PRE; mkdir -p \"\$(dirname \"\$SDDM_CONF\")\"; printf user > \"\$SDDM_CONF\"; module::install"
assert_status "sddm install writes theme and config" 0 bash -c "$PRE; module::install >/dev/null 2>&1; [ -r \"\$SDDM_THEME_DIR/theme.conf\" ]; grep -qxF Current=atlas \"\$SDDM_CONF\"; module::verify"
assert_status "sddm uses sudo wrapper when not root" 0 bash -c "$PRE; SUDO_LOG=\"\$HOME/sudo.log\"; os::is_root() { return 1; }; sudo() { printf \"%s\n\" \"\$*\" >> \"\$SUDO_LOG\"; \"\$@\"; }; module::install >/dev/null 2>&1; grep -q \"mkdir -p\" \"\$SUDO_LOG\"; grep -q \"90-atlas-theme.conf\" \"\$SUDO_LOG\"; module::verify"
assert_status "sddm update restores drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$SDDM_CONF\"; module::update >/dev/null 2>&1; module::verify"
assert_status "sddm remove detaches" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_sddm_marker)\"; [ ! -e \"\$SDDM_CONF\" ]; [ ! -e \"\$SDDM_THEME_DIR\" ]"
