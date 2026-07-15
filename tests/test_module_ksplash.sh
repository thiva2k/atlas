#!/usr/bin/env bash
# desktop/ksplash - RFC-0037
# Activation-only: install/check/verify are thin presence checks against the
# org.atlas.hud package's contents/splash/Splash.qml, shipped by desktop/lockscreen.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/ksplash/module.sh"
SPLASH_QML() { _ksplash_splash_qml; }
'
PRE="${PRE%$'\n'}"

assert_status "ksplash check fails before the splash package exists" 1 bash -c "$PRE; module::check"
assert_status "ksplash verify fails before the splash package exists" 1 bash -c "$PRE; module::verify"
assert_status "ksplash install fails before the splash package exists" 1 bash -c "$PRE; module::install"

assert_status "ksplash check/verify/install pass once the splash file is present" 0 bash -c "$PRE; mkdir -p \"\$(dirname \"\$(SPLASH_QML)\")\"; printf 'Rectangle {}' > \"\$(SPLASH_QML)\"; module::check; module::verify; module::install"
assert_status "ksplash update is a no-op that re-verifies" 0 bash -c "$PRE; mkdir -p \"\$(dirname \"\$(SPLASH_QML)\")\"; printf 'Rectangle {}' > \"\$(SPLASH_QML)\"; module::update"
assert_status "ksplash remove/backup/restore are no-ops" 0 bash -c "$PRE; module::remove; module::backup; module::restore"

# --- MODULE_DEPENDS -------------------------------------------------------------
assert_status "ksplash declares desktop/lockscreen as a dependency" 0 bash -c "$PRE; [ \"\${MODULE_DEPENDS[0]}\" = desktop/lockscreen ]; [ \${#MODULE_DEPENDS[@]} -eq 1 ]"
