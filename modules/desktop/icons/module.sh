#!/usr/bin/env bash
# desktop/icons - RFC-0018.
MODULE_NAME="icons"
MODULE_DESCRIPTION="Icons: installs Atlas-approved modern professional icon assets."
MODULE_DEPENDS=()

_ICONS_PACKAGE="papirus-icon-theme"
_icons_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-icons"; }
_icons_package_installed() { os::pkg_installed "$1"; }
_icons_marker_init() { _ICONS_MARKER_STATE=absent; }
_icons_marker_load() {
  _icons_marker_init
  local marker="$(_icons_marker)" line key val seen_schema=0 seen_state=0
  [ -e "$marker" ] || return 0
  [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || { log::error "Icons marker is not a readable regular file"; return 1; }
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "Icons marker mode must be 600"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue
    case "$line" in schema=1) seen_schema=1 ;; state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _ICONS_MARKER_STATE="$val" ;; *) return 1 ;; esac; seen_state=1 ;; package=papirus-icon-theme) ;; *) log::error "Icons marker has invalid line: $line"; return 1 ;; esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] && [ "$seen_state" -eq 1 ] || { log::error "Icons marker is incomplete"; return 1; }
}
_icons_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_icons_marker)"; dir="$(dirname "$marker")"
  mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-icons.XXXXXX")" || return 1
  { printf 'schema=1\nstate=%s\npackage=%s\n' "$state" "$_ICONS_PACKAGE"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }
}
module::check() { _icons_marker_load || return 1; [ "$_ICONS_MARKER_STATE" = installed ] || return 1; _icons_package_installed "$_ICONS_PACKAGE"; }
module::install() { os::is_fedora || { log::error "desktop/icons supports Fedora only"; return 1; }; _icons_marker_load || return 1; _icons_marker_write installing || return 1; _icons_package_installed "$_ICONS_PACKAGE" || os::dnf_install "$_ICONS_PACKAGE" || return 1; _icons_package_installed "$_ICONS_PACKAGE" || return 1; _icons_marker_write installed; }
module::verify() { _icons_marker_load || return 1; case "$_ICONS_MARKER_STATE" in absent) log::info "desktop/icons is not installed by Atlas"; return 0 ;; detached) return 0 ;; installing) return 1 ;; esac; _icons_package_installed "$_ICONS_PACKAGE"; }
module::update() { module::install; }
module::remove() { _icons_marker_load || return 1; case "$_ICONS_MARKER_STATE" in absent|detached) return 0 ;; esac; _icons_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/icons owns no user config"; }
module::restore() { log::info "nothing to restore: reinstall desktop/icons to reconstruct package intent"; }

# --- RFC-0030 activation (kdeglobals [Icons] Theme -> Papirus-Dark) --------------
_ICONS_ACT_VALUE="Papirus-Dark"
_ICONS_ACT_ABSENT="__ATLAS_ABSENT__"
_ICONS_CHANGEICONS="${ATLAS_ICONS_CHANGEICONS:-/usr/libexec/plasma-changeicons}"
_icons_act_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/activated/desktop-icons"; }
_icons_read() { kreadconfig6 --file kdeglobals --group Icons --key Theme --default "$_ICONS_ACT_ABSENT"; }
_icons_act_init() { _ICONS_ACT_STATE=absent; _ICONS_ACT_PRIOR=; }
_icons_act_load() {
  _icons_act_init
  local marker line key val seen_schema=0 seen_state=0 seen_prior=0
  marker="$(_icons_act_marker)"; [ -e "$marker" ] || return 0
  [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || { log::error "icons activation marker not a readable regular file: $marker"; return 1; }
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "icons activation marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue
    case "$line" in *=*) key="${line%%=*}"; val="${line#*=}" ;; *) log::error "icons activation marker invalid line: $line"; return 1 ;; esac
    case "$key" in
      schema) [ "$val" = 1 ] || { log::error "icons activation schema unsupported: $val"; return 1; }; seen_schema=1 ;;
      state) case "$val" in activating|active|inactive) _ICONS_ACT_STATE="$val" ;; *) log::error "icons activation state invalid: $val"; return 1 ;; esac; seen_state=1 ;;
      prior_icontheme) _ICONS_ACT_PRIOR="$val"; seen_prior=1 ;;
      *) log::error "icons activation marker unknown key: $key"; return 1 ;;
    esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] && [ "$seen_state" -eq 1 ] || { log::error "icons activation marker missing schema/state"; return 1; }
  case "$_ICONS_ACT_STATE" in
    inactive) [ "$seen_prior" -eq 0 ] || { log::error "icons activation marker has prior under inactive"; return 1; } ;;
    activating|active) [ "$seen_prior" -eq 1 ] && [ -n "$_ICONS_ACT_PRIOR" ] || { log::error "icons activation marker missing prior under $_ICONS_ACT_STATE"; return 1; } ;;
  esac
}
_icons_act_write() {
  local state="$1" prior="${2:-}" marker dir tmp
  marker="$(_icons_act_marker)"; dir="$(dirname "$marker")"
  mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-icons.act.XXXXXX")" || return 1
  { printf 'schema=1\nstate=%s\n' "$state"; case "$state" in activating|active) printf 'prior_icontheme=%s\n' "$prior" ;; esac; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }
}
module::activate() {
  _icons_marker_load || return 1
  [ "$_ICONS_MARKER_STATE" = installed ] || { log::error "desktop/icons is not installed; run 'atlas install desktop/icons' before activating"; return 1; }
  { command -v kreadconfig6 && command -v kwriteconfig6; } >/dev/null 2>&1 || { log::error "kreadconfig6/kwriteconfig6 not found"; return 1; }
  [ -x "$_ICONS_CHANGEICONS" ] || { log::error "plasma-changeicons not found at $_ICONS_CHANGEICONS; cannot activate icons"; return 1; }
  _icons_act_load || return 1
  local current; current="$(_icons_read)"
  if [ "$_ICONS_ACT_STATE" = active ]; then
    [ "$current" = "$_ICONS_ACT_VALUE" ] && { log::info "Papirus-Dark icons already active"; return 0; }
    log::error "icon theme changed since activation (now: $current); refusing to clobber — delete $(_icons_act_marker) to disown"; return 1
  fi
  local prior="$_ICONS_ACT_PRIOR"; [ -n "$prior" ] || prior="$current"
  _icons_act_write activating "$prior" || return 1
  "$_ICONS_CHANGEICONS" "$_ICONS_ACT_VALUE" >/dev/null 2>&1 || { log::error "failed to apply the Atlas icon theme"; return 1; }
  _icons_act_write active "$prior" || return 1
  log::info "Papirus-Dark icons activated (applies live or on next login; prior recorded: $prior)"
}
module::deactivate() {
  _icons_act_load || return 1
  case "$_ICONS_ACT_STATE" in absent|inactive) log::info "desktop/icons is not activated by Atlas"; return 0 ;; esac
  local current prior="$_ICONS_ACT_PRIOR"; current="$(_icons_read)"
  if [ "$_ICONS_ACT_STATE" = active ] && [ "$current" != "$_ICONS_ACT_VALUE" ]; then
    if [ "$current" = "$prior" ]; then _icons_act_write inactive || return 1; log::info "icons already restored to $prior; marked inactive"; return 0; fi
    log::error "icon theme changed since activation (now: $current); refusing to restore — delete $(_icons_act_marker) to disown"; return 1
  fi
  if [ "$prior" = "$_ICONS_ACT_ABSENT" ]; then
    command -v kwriteconfig6 >/dev/null 2>&1 || { log::error "kwriteconfig6 not found"; return 1; }
    kwriteconfig6 --file kdeglobals --group Icons --key Theme --delete "" >/dev/null 2>&1 || { log::error "failed to remove the Theme key; state left unchanged"; return 1; }
  else
    [ -x "$_ICONS_CHANGEICONS" ] || { log::error "plasma-changeicons not found at $_ICONS_CHANGEICONS; cannot restore prior icon theme"; return 1; }
    "$_ICONS_CHANGEICONS" "$prior" >/dev/null 2>&1 || { log::error "failed to restore prior icon theme '$prior'; state left unchanged"; return 1; }
  fi
  _icons_act_write inactive || return 1
  log::info "desktop/icons deactivated; restored $prior"
}
