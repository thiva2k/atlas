#!/usr/bin/env bash
# desktop/login-canvas - RFC-0036.
#
# Installs an Atlas-branded wallpaper for the STOCK plasma-login-greeter (the
# plasma-login-manager greeter UI is compiled-in and NOT themeable — the only
# lever is the wallpaper it renders via its WallpaperPluginId plugin, default
# org.kde.image). Ships the asset user-scope (no root); a separate, reversible
# RFC-0029 activation switches the greeter's SYSTEM-scoped config
# (/etc/plasmalogin.conf) to point at it, mirroring desktop/theme's escrow
# exactly. The greeter wallpaper is purely cosmetic: a bad or missing value at
# worst falls back to the plugin's own default image — it can never block login.
MODULE_NAME="login-canvas"
MODULE_DESCRIPTION="Login canvas: installs the Atlas wallpaper for the plasma-login-greeter (cosmetic only; never blocks login)."
MODULE_DEPENDS=()

_LOGIN_CANVAS_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_login_canvas_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-login-canvas"; }
_login_canvas_asset_source() { printf '%s\n' "$_LOGIN_CANVAS_MODULE_DIR/assets/atlas-login-canvas.png"; }
_login_canvas_asset_file() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/atlas/atlas-login-canvas.png"; }
_login_canvas_sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

# --- install marker (in-place-upgrade-SAFE: marker_load validates only its own
# structure; content drift is judged separately by _login_canvas_asset_matches,
# never by marker_load — the fish/fastfetch bug fixed in RFC-0034 is a marker
# that hard-fails on a *content* hash mismatch across an Atlas release; this
# marker never encodes the shipped asset's hash, only install state) ----------
_login_canvas_marker_init() { _LOGIN_CANVAS_MARKER_STATE=absent; }
_login_canvas_marker_load() {
  _login_canvas_marker_init
  local marker line val seen_schema=0 seen_state=0
  marker="$(_login_canvas_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then log::error "Login-canvas marker is not a readable regular file: $marker"; return 1; fi
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "Login-canvas marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue; case "$line" in \#*) continue ;; esac
    case "$line" in
      schema=1) seen_schema=1 ;;
      state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _LOGIN_CANVAS_MARKER_STATE="$val" ;; *) log::error "Login-canvas marker state is invalid: $val"; return 1 ;; esac; seen_state=1 ;;
      *) log::error "Login-canvas marker has an unknown line: $line"; return 1 ;;
    esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] || { log::error "Login-canvas marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Login-canvas marker is missing state"; return 1; }
}
_login_canvas_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_login_canvas_marker)"; dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.desktop-login-canvas.XXXXXX")" || { log::error "cannot create Login-canvas marker temp file"; return 1; }
  { printf 'schema=1\n'; printf 'state=%s\n' "$state"; } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_login_canvas_asset_matches() {
  local dest="$(_login_canvas_asset_file)" src="$(_login_canvas_asset_source)"
  [ -f "$dest" ] && [ ! -L "$dest" ] && [ "$(_login_canvas_sha256 "$dest")" = "$(_login_canvas_sha256 "$src")" ]
}

_login_canvas_write_asset() {
  local src="$(_login_canvas_asset_source)" dest="$(_login_canvas_asset_file)" dir tmp
  [ -r "$src" ] || { log::error "Atlas login-canvas asset source missing"; return 1; }
  if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then log::error "Atlas login-canvas target is not a regular file: $dest"; return 1; fi
  _login_canvas_asset_matches && return 0
  dir="$(dirname "$dest")"; mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  tmp="$(mktemp "$dir/.atlas-login-canvas.XXXXXX")" || { log::error "cannot create login-canvas temp file"; return 1; }
  cp "$src" "$tmp" || { rm -f "$tmp"; log::error "cannot stage $dest"; return 1; }
  chmod 644 "$tmp" || { rm -f "$tmp"; log::error "cannot chmod $tmp"; return 1; }
  mv -f "$tmp" "$dest" || { rm -f "$tmp"; log::error "cannot replace $dest"; return 1; }
}

_login_canvas_preflight_absent() {
  if [ -e "$(_login_canvas_asset_file)" ] || [ -L "$(_login_canvas_asset_file)" ]; then log::error "Atlas login-canvas asset already exists and is not Atlas-owned: $(_login_canvas_asset_file)"; return 1; fi
}

module::check() { _login_canvas_marker_load || return 1; [ "$_LOGIN_CANVAS_MARKER_STATE" = "installed" ] || return 1; _login_canvas_asset_matches; }
module::install() {
  os::is_fedora || { log::error "desktop/login-canvas supports Fedora only"; return 1; }
  _login_canvas_marker_load || return 1
  case "$_LOGIN_CANVAS_MARKER_STATE" in absent|detached) _login_canvas_preflight_absent || return 1 ;; installing|installed) ;; esac
  _login_canvas_marker_write installing || return 1
  _login_canvas_write_asset || return 1
  _login_canvas_marker_write installed || return 1
}
module::verify() {
  _login_canvas_marker_load || return 1
  case "$_LOGIN_CANVAS_MARKER_STATE" in absent) log::info "desktop/login-canvas is not installed by Atlas"; return 0 ;; detached) log::warn "desktop/login-canvas is detached"; return 0 ;; installing) log::error "desktop/login-canvas install is incomplete"; return 1 ;; esac
  _login_canvas_asset_matches || { log::error "Atlas login-canvas asset is missing or drifted"; return 1; }
}
module::update() { _login_canvas_marker_load || return 1; case "$_LOGIN_CANVAS_MARKER_STATE" in absent|detached) return 0 ;; esac; _login_canvas_write_asset && _login_canvas_marker_write installed; }
module::remove() { _login_canvas_marker_load || return 1; case "$_LOGIN_CANVAS_MARKER_STATE" in absent|detached) return 0 ;; esac; _login_canvas_asset_matches || { log::error "refusing to remove drifted Atlas login-canvas asset"; return 1; }; rm -f "$(_login_canvas_asset_file)" || return 1; _login_canvas_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/login-canvas is reconstructable from Atlas"; }
module::restore() { log::info "nothing to restore: reinstall desktop/login-canvas to reconstruct the Atlas-owned asset"; }

# --- RFC-0029 activation ----------------------------------------------------
# Switches the plasma-login-greeter's wallpaper to the Atlas login canvas.
#
# Mechanism (found by inspecting kcm_plasmalogin.so and the greeter binary on a
# live Fedora KDE box — see RFC-0036 §Research): the greeter is a QML app
# (org.kde.plasma.login.wallpaper) that reads a `WallpaperPluginId` string
# (default "org.kde.image") from the KCM's Settings object, whose QML binds
# `settingName: "WallpaperPluginId"` under KConfig group "Greeter" in
# /etc/plasmalogin.conf (confirmed: kcmplasmalogin_authhelper, the polkit-gated
# root D-Bus helper the KCM uses to write system config, embeds exactly one
# path string, "/etc/plasmalogin.conf" — there is no other candidate file). The
# org.kde.image wallpaper plugin's own schema (contents/config/main.xml, shared
# with the desktop wallpaper engine) defines a General/Image string key. Nested
# KConfig groups follow the same convention RFC-0033 already verified for the
# desktop's plasma-org.kde.plasma.desktop-appletsrc
# ([Containments][C][Wallpaper][org.kde.image][General] Image=) — applied here
# with "Greeter" as the outer group in place of a containment id:
#
#   /etc/plasmalogin.conf
#     [Greeter]
#     WallpaperPluginId=org.kde.image
#
#     [Greeter][Wallpaper][org.kde.image][General]
#     Image=file:///path/to/atlas-login-canvas.png
#
# Verified experimentally with kwriteconfig6/kreadconfig6 (which support
# repeated --group for nested groups) round-tripping both keys through a
# throwaway file. This is SYSTEM-scoped (/etc), so activation requires root —
# _run_privileged wraps every read/write exactly like desktop/sddm and
# desktop/plymouth. The greeter reads this file when it spawns the wallpaper
# process (not live): activation and deactivation both apply at the NEXT LOGIN
# SCREEN, never mid-session. A bad or absent value only ever falls back to the
# org.kde.image plugin's own built-in default — this can never block login.
_LOGIN_CANVAS_CONF="/etc/plasmalogin.conf"
_LOGIN_CANVAS_ACT_ABSENT="__ATLAS_ABSENT__"
_login_canvas_act_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/activated/desktop-login-canvas"; }
_login_canvas_run_privileged() { if os::is_root; then "$@"; else sudo "$@"; fi; }
_login_canvas_conf_file() { printf '%s\n' "$_LOGIN_CANVAS_CONF"; }
_login_canvas_atlas_path() { printf '%s\n' "$(_login_canvas_asset_file)"; }
_login_canvas_atlas_url() { printf '%s\n' "file://$(_login_canvas_atlas_path)"; }
_login_canvas_norm() { local v="$1"; printf '%s\n' "${v#file://}"; }

_login_canvas_read_plugin() { _login_canvas_run_privileged kreadconfig6 --file "$(_login_canvas_conf_file)" --group Greeter --key WallpaperPluginId --default "$_LOGIN_CANVAS_ACT_ABSENT"; }
_login_canvas_read_image() { _login_canvas_run_privileged kreadconfig6 --file "$(_login_canvas_conf_file)" --group Greeter --group Wallpaper --group org.kde.image --group General --key Image --default "$_LOGIN_CANVAS_ACT_ABSENT"; }
_login_canvas_write_plugin() { _login_canvas_run_privileged kwriteconfig6 --file "$(_login_canvas_conf_file)" --group Greeter --key WallpaperPluginId --type string "$1"; }
_login_canvas_write_image() { _login_canvas_run_privileged kwriteconfig6 --file "$(_login_canvas_conf_file)" --group Greeter --group Wallpaper --group org.kde.image --group General --key Image --type string "$1"; }
_login_canvas_delete_plugin() { _login_canvas_run_privileged kwriteconfig6 --file "$(_login_canvas_conf_file)" --group Greeter --key WallpaperPluginId --delete ""; }
_login_canvas_delete_image() { _login_canvas_run_privileged kwriteconfig6 --file "$(_login_canvas_conf_file)" --group Greeter --group Wallpaper --group org.kde.image --group General --key Image --delete ""; }

_login_canvas_act_init() { _LOGIN_CANVAS_ACT_STATE=absent; _LOGIN_CANVAS_ACT_PRIOR_PLUGIN=; _LOGIN_CANVAS_ACT_PRIOR_IMAGE=; }
_login_canvas_act_load() {
  _login_canvas_act_init
  local marker line key val seen_schema=0 seen_state=0 seen_pp=0 seen_pi=0
  marker="$(_login_canvas_act_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then log::error "Login-canvas activation marker is not a readable regular file: $marker"; return 1; fi
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "Login-canvas activation marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue; case "$line" in \#*) continue ;; esac
    case "$line" in *=*) key="${line%%=*}"; val="${line#*=}" ;; *) log::error "Login-canvas activation marker has an invalid line: $line"; return 1 ;; esac
    case "$key" in
      schema) [ "$val" = "1" ] || { log::error "Login-canvas activation schema is unsupported: $val"; return 1; }; seen_schema=1 ;;
      state) case "$val" in activating|active|inactive) _LOGIN_CANVAS_ACT_STATE="$val" ;; *) log::error "Login-canvas activation state is invalid: $val"; return 1 ;; esac; seen_state=1 ;;
      prior_plugin) _LOGIN_CANVAS_ACT_PRIOR_PLUGIN="$val"; seen_pp=1 ;;
      prior_image) _LOGIN_CANVAS_ACT_PRIOR_IMAGE="$val"; seen_pi=1 ;;
      *) log::error "Login-canvas activation marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] || { log::error "Login-canvas activation marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Login-canvas activation marker is missing state"; return 1; }
  case "$_LOGIN_CANVAS_ACT_STATE" in
    inactive) { [ "$seen_pp" -eq 0 ] && [ "$seen_pi" -eq 0 ]; } || { log::error "Login-canvas activation marker has prior_* under inactive state"; return 1; } ;;
    activating|active)
      { [ "$seen_pp" -eq 1 ] && [ -n "$_LOGIN_CANVAS_ACT_PRIOR_PLUGIN" ] && [ "$seen_pi" -eq 1 ] && [ -n "$_LOGIN_CANVAS_ACT_PRIOR_IMAGE" ]; } || { log::error "Login-canvas activation marker is missing prior_* under $_LOGIN_CANVAS_ACT_STATE"; return 1; } ;;
  esac
}
_login_canvas_act_write() {
  local state="$1" prior_plugin="${2:-}" prior_image="${3:-}" marker dir tmp
  marker="$(_login_canvas_act_marker)"; dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.desktop-login-canvas.act.XXXXXX")" || { log::error "cannot create Login-canvas activation temp file"; return 1; }
  {
    printf 'schema=1\n'; printf 'state=%s\n' "$state"
    case "$state" in activating|active) printf 'prior_plugin=%s\n' "$prior_plugin"; printf 'prior_image=%s\n' "$prior_image" ;; esac
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}
# §5.3-style non-interactive privilege preflight — never starts a cancellable prompt.
_login_canvas_privilege_ok() { os::is_root || sudo -n true 2>/dev/null; }
_login_canvas_sudo_guidance() {
  log::error "login-canvas activation requires root to edit $_LOGIN_CANVAS_CONF. Re-run with sudo available, e.g.:"
  log::error "  sudo atlas activate desktop/login-canvas"
}

module::activate() {
  _login_canvas_marker_load || return 1
  [ "$_LOGIN_CANVAS_MARKER_STATE" = "installed" ] || { log::error "desktop/login-canvas is not installed; run 'atlas install desktop/login-canvas' before activating"; return 1; }
  { command -v kreadconfig6 && command -v kwriteconfig6; } >/dev/null 2>&1 || { log::error "kreadconfig6/kwriteconfig6 not found; cannot manage the greeter wallpaper"; return 1; }
  _login_canvas_privilege_ok || { _login_canvas_sudo_guidance; return 1; }
  _login_canvas_act_load || return 1
  local cur_plugin cur_image atlas_url atlas_path
  cur_plugin="$(_login_canvas_read_plugin)"; cur_image="$(_login_canvas_read_image)"
  atlas_path="$(_login_canvas_atlas_path)"; atlas_url="$(_login_canvas_atlas_url)"
  if [ "$_LOGIN_CANVAS_ACT_STATE" = "active" ]; then
    if [ "$cur_plugin" = "org.kde.image" ] && [ "$(_login_canvas_norm "$cur_image")" = "$atlas_path" ]; then
      log::info "Atlas login canvas is already active"; return 0
    fi
    log::error "the greeter wallpaper changed since activation (plugin: $cur_plugin, image: $cur_image); refusing to clobber — delete $(_login_canvas_act_marker) to disown"; return 1
  fi
  # Record prior write-once: reuse an interrupted activating record; else capture now.
  local prior_plugin="$_LOGIN_CANVAS_ACT_PRIOR_PLUGIN" prior_image="$_LOGIN_CANVAS_ACT_PRIOR_IMAGE"
  if [ -z "$prior_plugin" ]; then prior_plugin="$cur_plugin"; prior_image="$cur_image"; fi
  _login_canvas_act_write activating "$prior_plugin" "$prior_image" || return 1
  _login_canvas_write_plugin "org.kde.image" >/dev/null 2>&1 || { log::error "failed to set WallpaperPluginId; state left at 'activating'"; return 1; }
  _login_canvas_write_image "$atlas_url" >/dev/null 2>&1 || { log::error "failed to set the greeter wallpaper image; state left at 'activating'"; return 1; }
  _login_canvas_act_write active "$prior_plugin" "$prior_image" || return 1
  log::info "Atlas login canvas activated (applies at next login screen; prior recorded: plugin=$prior_plugin, image=$prior_image)"
}

module::deactivate() {
  _login_canvas_act_load || return 1
  case "$_LOGIN_CANVAS_ACT_STATE" in absent|inactive) log::info "desktop/login-canvas is not activated by Atlas"; return 0 ;; esac
  command -v kwriteconfig6 >/dev/null 2>&1 || { log::error "kwriteconfig6 not found; cannot restore the prior greeter wallpaper"; return 1; }
  _login_canvas_privilege_ok || { _login_canvas_sudo_guidance; return 1; }
  local cur_plugin cur_image atlas_path prior_plugin="$_LOGIN_CANVAS_ACT_PRIOR_PLUGIN" prior_image="$_LOGIN_CANVAS_ACT_PRIOR_IMAGE"
  cur_plugin="$(_login_canvas_read_plugin)"; cur_image="$(_login_canvas_read_image)"; atlas_path="$(_login_canvas_atlas_path)"
  local is_atlas=0 is_prior=0
  [ "$cur_plugin" = "org.kde.image" ] && [ "$(_login_canvas_norm "$cur_image")" = "$atlas_path" ] && is_atlas=1
  [ "$cur_plugin" = "$prior_plugin" ] && [ "$(_login_canvas_norm "$cur_image")" = "$(_login_canvas_norm "$prior_image")" ] && is_prior=1
  if [ "$_LOGIN_CANVAS_ACT_STATE" = "active" ] && [ "$is_atlas" -ne 1 ]; then
    if [ "$is_prior" -eq 1 ]; then
      # already-restored finalize: restore landed, only the state write was lost.
      _login_canvas_act_write inactive || return 1
      log::info "desktop/login-canvas already restored; marked inactive"; return 0
    fi
    log::error "the greeter wallpaper changed since activation (plugin: $cur_plugin, image: $cur_image); refusing to restore — delete $(_login_canvas_act_marker) to disown"; return 1
  fi
  # Restore the recorded prior (or delete keys that were absent before Atlas).
  if [ "$prior_plugin" = "$_LOGIN_CANVAS_ACT_ABSENT" ]; then
    _login_canvas_delete_plugin >/dev/null 2>&1 || { log::error "failed to remove WallpaperPluginId (prior was absent); state left unchanged"; return 1; }
  else
    _login_canvas_write_plugin "$prior_plugin" >/dev/null 2>&1 || { log::error "failed to restore prior WallpaperPluginId '$prior_plugin'; state left unchanged"; return 1; }
  fi
  if [ "$prior_image" = "$_LOGIN_CANVAS_ACT_ABSENT" ]; then
    _login_canvas_delete_image >/dev/null 2>&1 || { log::error "failed to remove the greeter wallpaper image key (prior was absent); state left unchanged"; return 1; }
  else
    _login_canvas_write_image "$prior_image" >/dev/null 2>&1 || { log::error "failed to restore the prior greeter wallpaper image; state left unchanged"; return 1; }
  fi
  _login_canvas_act_write inactive || return 1
  log::info "desktop/login-canvas deactivated; restored prior greeter wallpaper (applies at next login screen)"
}
