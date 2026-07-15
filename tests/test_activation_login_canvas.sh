#!/usr/bin/env bash
# desktop/login-canvas activation - RFC-0036
# Reuses the RFC-0029 escrow pattern exactly as desktop/theme/lockscreen do, but
# against a SYSTEM-scoped file (/etc/plasmalogin.conf) with TWO keys under nested
# KConfig groups: [Greeter] WallpaperPluginId, and
# [Greeter][Wallpaper][org.kde.image][General] Image. Because it is system-scoped,
# every read/write goes through _login_canvas_run_privileged (root-or-sudo), mirroring
# desktop/sddm and desktop/plymouth.
#
# kreadconfig6/kwriteconfig6 are mocked against a single flat KV file (CONF_FILE)
# keyed by "plugin" and "image" — sufficient to exercise the two-key escrow contract
# without a real ini parser. The sudo mock mirrors desktop/sddm's test.

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
os::is_root() { [ "${ROOT_OK:-1}" = 1 ]; }
SUDO_OK="${SUDO_OK:-1}"; export SUDO_OK
sudo() { case "$1" in -n) shift; [ "${SUDO_OK:-1}" = 1 ] && { "$@"; } || return 1 ;; *) [ "${SUDO_OK:-1}" = 1 ] && "$@" || return 1 ;; esac; }
# --- /etc/plasmalogin.conf mock: a flat KV file with "plugin" and "image" lines ---
CONF_FILE="$HOME/plasmalogin.conf"; export CONF_FILE
_login_canvas_conf_file() { printf "%s\n" "$CONF_FILE"; }
_conf_get() { [ -f "$CONF_FILE" ] && grep -E "^$1=" "$CONF_FILE" 2>/dev/null | tail -1 | cut -d= -f2- || true; }
_conf_set() { local k="$1" v="$2" tmp; tmp="$(mktemp)"; { [ -f "$CONF_FILE" ] && grep -vE "^$k=" "$CONF_FILE" 2>/dev/null; printf "%s=%s\n" "$k" "$v"; } > "$tmp"; mv "$tmp" "$CONF_FILE"; }
_conf_del() { [ -f "$CONF_FILE" ] || return 0; local tmp; tmp="$(mktemp)"; grep -vE "^$1=" "$CONF_FILE" > "$tmp" || true; mv "$tmp" "$CONF_FILE"; }
kreadconfig6() {
  local d="" is_image=0 key=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --group) [ "$2" = Wallpaper ] && is_image=1; shift 2 ;;
      --key) key="$2"; shift 2 ;;
      --default) d="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  local mapkey="plugin"; [ "$is_image" = 1 ] && mapkey="image"
  local v; v="$(_conf_get "$mapkey")"
  if [ -n "$v" ]; then printf "%s\n" "$v"; else printf "%s\n" "$d"; fi
}
kwriteconfig6() {
  local is_image=0 del=0 key="" val=""
  local -a rest=(); for a in "$@"; do rest+=("$a"); done
  local i=0
  while [ $i -lt ${#rest[@]} ]; do
    case "${rest[$i]}" in
      --group) [ "${rest[$((i+1))]}" = Wallpaper ] && is_image=1; i=$((i+2)) ;;
      --key) key="${rest[$((i+1))]}"; i=$((i+2)) ;;
      --delete) del=1; i=$((i+2)) ;;
      --type) i=$((i+2)) ;;
      *) val="${rest[$i]}"; i=$((i+1)) ;;
    esac
  done
  local mapkey="plugin"; [ "$is_image" = 1 ] && mapkey="image"
  if [ "$del" = 1 ]; then _conf_del "$mapkey"; else _conf_set "$mapkey" "$val"; fi
  return 0
}
ACT() { _login_canvas_act_marker; }
'
PRE="${PRE%$'\n'}"

# --- preconditions ---------------------------------------------------------------
assert_status "activate fails when login-canvas not installed" 1 bash -c "$PRE; module::activate >/dev/null 2>&1; [ ! -e \"\$(ACT)\" ]; exit 1"
assert_status "activate fails when kreadconfig6/kwriteconfig6 absent" 1 bash -c "$PRE; module::install >/dev/null 2>&1; command() { if [ \"\$1\" = -v ] && { [ \"\$2\" = kreadconfig6 ] || [ \"\$2\" = kwriteconfig6 ]; }; then return 1; fi; builtin command \"\$@\"; }; module::activate 2>/dev/null"
assert_status "deactivate is a no-op before activation" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::deactivate"
assert_status "activate refuses without root/sudo before writing any state" 1 bash -c "$PRE; module::install >/dev/null 2>&1; ROOT_OK=0; SUDO_OK=0; module::activate >/dev/null 2>&1; [ ! -e \"\$(ACT)\" ]; exit 1"

# --- records prior / applies (uses sudo wrapper when not root) -------------------
assert_status "activate (non-root, sudo) sets plugin+image and records prior" 0 bash -c "$PRE; printf 'plugin=org.kde.slideshow\nimage=/old/path.jpg\n' > \"\$CONF_FILE\"; ROOT_OK=0; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; [ \"\$(_conf_get plugin)\" = org.kde.image ]; [ \"\$(_conf_get image)\" = \"file://\$(_login_canvas_atlas_path)\" ]; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_plugin=org.kde.slideshow \"\$(ACT)\"; grep -qxF prior_image=/old/path.jpg \"\$(ACT)\""
assert_status "activate (root) sets plugin+image without sudo" 0 bash -c "$PRE; printf 'plugin=org.kde.image\nimage=/old/path.jpg\n' > \"\$CONF_FILE\"; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; [ \"\$(_conf_get plugin)\" = org.kde.image ]; [ \"\$(_conf_get image)\" = \"file://\$(_login_canvas_atlas_path)\" ]; grep -qxF state=active \"\$(ACT)\""

# --- idempotent --------------------------------------------------------------------
assert_status "second activate is a no-op" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; cp \"\$(ACT)\" \"\$HOME/m1\"; module::activate >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\""

# --- restores exactly ----------------------------------------------------------------
assert_status "deactivate restores the recorded prior plugin+image and drops prior_*" 0 bash -c "$PRE; printf 'plugin=org.kde.slideshow\nimage=/old/path.jpg\n' > \"\$CONF_FILE\"; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ \"\$(_conf_get plugin)\" = org.kde.slideshow ]; [ \"\$(_conf_get image)\" = /old/path.jpg ]; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_plugin \"\$(ACT)\"; ! grep -q prior_image \"\$(ACT)\""

# --- refuse-to-clobber ---------------------------------------------------------------
assert_status "activate refuses to clobber user drift; prior untouched" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; _conf_set image /some/other.jpg; module::activate 2>/dev/null && exit 1; grep -qxF state=active \"\$(ACT)\""
assert_status "deactivate refuses to clobber user drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; _conf_set image /some/other.jpg; module::deactivate 2>/dev/null && exit 1; [ \"\$(_conf_get image)\" = /some/other.jpg ]"

# --- absent-key sentinel ---------------------------------------------------------------
assert_status "activate records absent sentinel when plugin/image keys did not exist" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; grep -qxF prior_plugin=__ATLAS_ABSENT__ \"\$(ACT)\"; grep -qxF prior_image=__ATLAS_ABSENT__ \"\$(ACT)\""
assert_status "deactivate deletes both keys when prior was absent" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ -z \"\$(_conf_get plugin)\" ]; [ -z \"\$(_conf_get image)\" ]; grep -qxF state=inactive \"\$(ACT)\""

# --- interrupted activation is write-once (never launders Atlas into the escrow) -----
assert_status "interrupted activate reuses recorded prior, never launders it" 0 bash -c "$PRE; module::install >/dev/null 2>&1; _login_canvas_act_write activating org.kde.slideshow /old/path.jpg; _conf_set plugin org.kde.image; _conf_set image \"file://\$(_login_canvas_atlas_path)\"; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_plugin=org.kde.slideshow \"\$(ACT)\"; module::deactivate >/dev/null 2>&1; [ \"\$(_conf_get plugin)\" = org.kde.slideshow ]; [ \"\$(_conf_get image)\" = /old/path.jpg ]"

# --- interrupted deactivate finalizes (already restored, not drift) ------------------
assert_status "interrupted deactivate finalizes to inactive without misreporting drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; _login_canvas_act_write active org.kde.slideshow /old/path.jpg; _conf_set plugin org.kde.slideshow; _conf_set image /old/path.jpg; module::deactivate >/dev/null 2>&1; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_plugin \"\$(ACT)\""

# --- disown then fresh prior -----------------------------------------------------------
assert_status "disown (delete marker) lets activate record a fresh prior" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; rm -f \"\$(ACT)\"; _conf_set plugin org.kde.color; _conf_set image ''; module::activate >/dev/null 2>&1; grep -qxF prior_plugin=org.kde.color \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\""

# --- strict marker parser rejections ----------------------------------------------------
assert_status "load rejects prior_plugin under inactive state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nprior_plugin=org.kde.image\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _login_canvas_act_load 2>/dev/null"
assert_status "load rejects missing prior_image under active state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=active\nprior_plugin=org.kde.image\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _login_canvas_act_load 2>/dev/null"
assert_status "load rejects unknown key" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nbogus=1\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _login_canvas_act_load 2>/dev/null"
assert_status "load rejects an unsupported schema" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=2\nstate=inactive\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _login_canvas_act_load 2>/dev/null"
assert_status "load rejects an invalid state value" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=bogus\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _login_canvas_act_load 2>/dev/null"
assert_status "load rejects marker mode != 600" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\n' > \"\$(ACT)\"; chmod 644 \"\$(ACT)\"; _login_canvas_act_load 2>/dev/null"
