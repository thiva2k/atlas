#!/usr/bin/env bash
# desktop/wallpapers activation - RFC-0033 (per-containment, discovery-based).

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_CONFIG_HOME="$HOME/.config"; export XDG_CONFIG_HOME
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
mkdir -p "$XDG_CONFIG_HOME"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/wallpapers/module.sh"
source "$ATLAS_ROOT/tests/fixtures/wp_mocks.sh"
os::is_fedora() { return 0; }
ATLAS_URL="$(_wp_atlas_url)"; ATLAS_PATH="$(_wp_atlas_image)"
MARK() { _wp_act_marker; }
'
PRE="${PRE%$'\n'}"

# --- preconditions -------------------------------------------------------------
assert_status "wallpapers activate fails when not installed" 1 bash -c "$PRE; wp_seed_single; module::activate >/dev/null 2>&1; [ ! -e \"\$(MARK)\" ]; exit 1"
assert_status "wallpapers activate fails with no appletsrc" 1 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate 2>/dev/null"

# --- discovery + record prior + apply ------------------------------------------
assert_status "wallpapers activate captures desktop [1], ignores panel [2], applies Atlas" 0 bash -c "$PRE; wp_seed_single 'file:///stock/a.png'; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(MARK)\"; grep -qxF containments=1 \"\$(MARK)\"; grep -qxF 'prior_image_1=file:///stock/a.png' \"\$(MARK)\"; [ \"\$(wp_cur 1)\" = \"\$ATLAS_URL\" ]"

# --- idempotent (also proves URL normalization: current==Atlas is not drift) ----
assert_status "wallpapers second activate is a no-op" 0 bash -c "$PRE; wp_seed_single 'file:///stock/a.png'; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; cp \"\$(MARK)\" \"\$HOME/m1\"; module::activate >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(MARK)\"; grep -qxF state=active \"\$(MARK)\""

# --- refuse-at-activate on a non-image plugin ----------------------------------
assert_status "wallpapers refuses to activate over a slideshow (no state written)" 0 bash -c "$PRE; wp_seed_single; kwriteconfig6 --file \"\$APPLETSRC\" --group Containments --group 1 --key wallpaperplugin org.kde.slideshow; module::install >/dev/null 2>&1; module::activate 2>/dev/null && exit 1; [ ! -e \"\$(MARK)\" ]"

# --- restores exactly ----------------------------------------------------------
assert_status "wallpapers deactivate restores the exact prior and clears escrow" 0 bash -c "$PRE; wp_seed_single 'file:///stock/a.png'; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ \"\$(wp_cur 1)\" = 'file:///stock/a.png' ]; grep -qxF state=inactive \"\$(MARK)\"; ! grep -q prior_image \"\$(MARK)\"; ! grep -q containments \"\$(MARK)\""

# --- absent-sentinel: no Image key before activation ---------------------------
assert_status "wallpapers records absent sentinel and deletes the key on restore" 0 bash -c "$PRE; wp_seed_single; kwriteconfig6 --file \"\$APPLETSRC\" --group Containments --group 1 --group Wallpaper --group org.kde.image --group General --key Image --delete ''; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; grep -qxF prior_image_1=__ATLAS_ABSENT__ \"\$(MARK)\"; [ \"\$(wp_cur 1)\" = \"\$ATLAS_URL\" ]; module::deactivate >/dev/null 2>&1; [ \"\$(wp_cur 1)\" = __NONE__ ]"

# --- refuse-to-clobber ---------------------------------------------------------
assert_status "wallpapers activate refuses drift and preserves prior" 0 bash -c "$PRE; wp_seed_single 'file:///stock/a.png'; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; kwriteconfig6 --file \"\$APPLETSRC\" --group Containments --group 1 --group Wallpaper --group org.kde.image --group General --key Image 'file:///other/y.png'; module::activate 2>/dev/null && exit 1; grep -qxF 'prior_image_1=file:///stock/a.png' \"\$(MARK)\""
assert_status "wallpapers deactivate refuses drift, leaves wallpaper" 0 bash -c "$PRE; wp_seed_single 'file:///stock/a.png'; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; kwriteconfig6 --file \"\$APPLETSRC\" --group Containments --group 1 --group Wallpaper --group org.kde.image --group General --key Image 'file:///other/y.png'; module::deactivate 2>/dev/null && exit 1; [ \"\$(wp_cur 1)\" = 'file:///other/y.png' ]"

# --- multi-monitor: two desktops with distinct wallpapers ----------------------
assert_status "wallpapers multi-monitor captures and restores each desktop's own prior" 0 bash -c "$PRE; wp_seed_dual 'file:///scr/a.png' 'file:///scr/b.png'; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; grep -qxF containments='1 3' \"\$(MARK)\"; grep -qxF 'prior_image_1=file:///scr/a.png' \"\$(MARK)\"; grep -qxF 'prior_image_3=file:///scr/b.png' \"\$(MARK)\"; [ \"\$(wp_cur 1)\" = \"\$ATLAS_URL\" ]; [ \"\$(wp_cur 3)\" = \"\$ATLAS_URL\" ]; module::deactivate >/dev/null 2>&1; [ \"\$(wp_cur 1)\" = 'file:///scr/a.png' ]; [ \"\$(wp_cur 3)\" = 'file:///scr/b.png' ]"

# --- interrupted activate is write-once (never launder Atlas into the escrow) ---
assert_status "wallpapers interrupted activate reuses recorded prior" 0 bash -c "$PRE; wp_seed_single 'file:///stock/a.png'; module::install >/dev/null 2>&1; d=\"\$(dirname \"\$(MARK)\")\"; mkdir -p \"\$d\"; chmod 700 \"\$d\"; printf 'schema=1\nstate=activating\ncontainments=1\nprior_image_1=file:///stock/a.png\n' > \"\$(MARK)\"; chmod 600 \"\$(MARK)\"; kwriteconfig6 --file \"\$APPLETSRC\" --group Containments --group 1 --group Wallpaper --group org.kde.image --group General --key Image \"\$ATLAS_URL\"; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(MARK)\"; grep -qxF 'prior_image_1=file:///stock/a.png' \"\$(MARK)\"; module::deactivate >/dev/null 2>&1; [ \"\$(wp_cur 1)\" = 'file:///stock/a.png' ]"

# --- interrupted deactivate finalizes (one desktop already restored) -----------
assert_status "wallpapers interrupted deactivate finishes without misreporting drift" 0 bash -c "$PRE; wp_seed_dual 'file:///scr/a.png' 'file:///scr/b.png'; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; kwriteconfig6 --file \"\$APPLETSRC\" --group Containments --group 1 --group Wallpaper --group org.kde.image --group General --key Image 'file:///scr/a.png'; module::deactivate >/dev/null 2>&1; grep -qxF state=inactive \"\$(MARK)\"; [ \"\$(wp_cur 1)\" = 'file:///scr/a.png' ]; [ \"\$(wp_cur 3)\" = 'file:///scr/b.png' ]"

# --- disown then fresh prior ---------------------------------------------------
assert_status "wallpapers disown lets activate record a fresh prior" 0 bash -c "$PRE; wp_seed_single 'file:///stock/a.png'; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; rm -f \"\$(MARK)\"; kwriteconfig6 --file \"\$APPLETSRC\" --group Containments --group 1 --group Wallpaper --group org.kde.image --group General --key Image 'file:///new/z.png'; module::activate >/dev/null 2>&1; grep -qxF 'prior_image_1=file:///new/z.png' \"\$(MARK)\"; grep -qxF state=active \"\$(MARK)\""

# --- no-live path (plasma-apply-wallpaperimage absent) -------------------------
assert_status "wallpapers activate works without plasma-apply (applies next login)" 0 bash -c "$PRE; wp_seed_single 'file:///stock/a.png'; module::install >/dev/null 2>&1; command() { if [ \"\$1\" = -v ] && [ \"\$2\" = plasma-apply-wallpaperimage ]; then return 1; fi; builtin command \"\$@\"; }; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(MARK)\"; [ \"\$(wp_cur 1)\" = \"\$ATLAS_URL\" ]"

# --- strict parser -------------------------------------------------------------
assert_status "wallpapers load rejects prior_image under inactive" 1 bash -c "$PRE; d=\"\$(dirname \"\$(MARK)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nprior_image_1=x\n' > \"\$(MARK)\"; chmod 600 \"\$(MARK)\"; _wp_act_load 2>/dev/null"
assert_status "wallpapers load rejects missing prior for a listed containment" 1 bash -c "$PRE; d=\"\$(dirname \"\$(MARK)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=active\ncontainments=1 3\nprior_image_1=x\n' > \"\$(MARK)\"; chmod 600 \"\$(MARK)\"; _wp_act_load 2>/dev/null"
assert_status "wallpapers load rejects a non-integer containment id" 1 bash -c "$PRE; d=\"\$(dirname \"\$(MARK)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=active\ncontainments=1\nprior_image_1=x\nprior_image_z=y\n' > \"\$(MARK)\"; chmod 600 \"\$(MARK)\"; _wp_act_load 2>/dev/null"
assert_status "wallpapers load rejects an unknown key" 1 bash -c "$PRE; d=\"\$(dirname \"\$(MARK)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nbogus=1\n' > \"\$(MARK)\"; chmod 600 \"\$(MARK)\"; _wp_act_load 2>/dev/null"
