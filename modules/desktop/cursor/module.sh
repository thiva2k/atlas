#!/usr/bin/env bash
# desktop/cursor - RFC-0019.
MODULE_NAME="cursor"
MODULE_DESCRIPTION="Cursor: installs a simple professional cursor theme package."
MODULE_DEPENDS=()

_CURSOR_PACKAGE="adwaita-cursor-theme"
_cursor_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-cursor"; }
_cursor_package_installed() { os::pkg_installed "$1"; }
_cursor_marker_init() { _CURSOR_MARKER_STATE=absent; }
_cursor_marker_load() {
  _cursor_marker_init
  local marker="$(_cursor_marker)" line val seen_schema=0 seen_state=0
  [ -e "$marker" ] || return 0
  [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || return 1
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue
    case "$line" in schema=1) seen_schema=1 ;; state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _CURSOR_MARKER_STATE="$val" ;; *) return 1 ;; esac; seen_state=1 ;; package=adwaita-cursor-theme) ;; *) return 1 ;; esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] && [ "$seen_state" -eq 1 ]
}
_cursor_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_cursor_marker)"; dir="$(dirname "$marker")"; mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-cursor.XXXXXX")" || return 1
  { printf 'schema=1\nstate=%s\npackage=%s\n' "$state" "$_CURSOR_PACKAGE"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }
}
module::check() { _cursor_marker_load || return 1; [ "$_CURSOR_MARKER_STATE" = installed ] || return 1; _cursor_package_installed "$_CURSOR_PACKAGE"; }
module::install() { os::is_fedora || return 1; _cursor_marker_load || return 1; _cursor_marker_write installing || return 1; _cursor_package_installed "$_CURSOR_PACKAGE" || os::dnf_install "$_CURSOR_PACKAGE" || return 1; _cursor_package_installed "$_CURSOR_PACKAGE" || return 1; _cursor_marker_write installed; }
module::verify() { _cursor_marker_load || return 1; case "$_CURSOR_MARKER_STATE" in absent|detached) return 0 ;; installing) return 1 ;; esac; _cursor_package_installed "$_CURSOR_PACKAGE"; }
module::update() { module::install; }
module::remove() { _cursor_marker_load || return 1; case "$_CURSOR_MARKER_STATE" in absent|detached) return 0 ;; esac; _cursor_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/cursor owns no user config"; }
module::restore() { log::info "nothing to restore: reinstall desktop/cursor to reconstruct package intent"; }

# --- RFC-0030 activation (kcminputrc [Mouse] cursorTheme -> Adwaita) -------------
_CURSOR_ACT_VALUE="Adwaita"
_CURSOR_ACT_ABSENT="__ATLAS_ABSENT__"
_cursor_act_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/activated/desktop-cursor"; }
_cursor_read() { kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme --default "$_CURSOR_ACT_ABSENT"; }
_cursor_act_init() { _CURSOR_ACT_STATE=absent; _CURSOR_ACT_PRIOR=; }
_cursor_act_load() {
  _cursor_act_init
  local marker line key val seen_schema=0 seen_state=0 seen_prior=0
  marker="$(_cursor_act_marker)"; [ -e "$marker" ] || return 0
  [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || { log::error "cursor activation marker not a readable regular file: $marker"; return 1; }
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "cursor activation marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue
    case "$line" in *=*) key="${line%%=*}"; val="${line#*=}" ;; *) log::error "cursor activation marker invalid line: $line"; return 1 ;; esac
    case "$key" in
      schema) [ "$val" = 1 ] || { log::error "cursor activation schema unsupported: $val"; return 1; }; seen_schema=1 ;;
      state) case "$val" in activating|active|inactive) _CURSOR_ACT_STATE="$val" ;; *) log::error "cursor activation state invalid: $val"; return 1 ;; esac; seen_state=1 ;;
      prior_cursortheme) _CURSOR_ACT_PRIOR="$val"; seen_prior=1 ;;
      *) log::error "cursor activation marker unknown key: $key"; return 1 ;;
    esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] && [ "$seen_state" -eq 1 ] || { log::error "cursor activation marker missing schema/state"; return 1; }
  case "$_CURSOR_ACT_STATE" in
    inactive) [ "$seen_prior" -eq 0 ] || { log::error "cursor activation marker has prior under inactive"; return 1; } ;;
    activating|active) [ "$seen_prior" -eq 1 ] && [ -n "$_CURSOR_ACT_PRIOR" ] || { log::error "cursor activation marker missing prior under $_CURSOR_ACT_STATE"; return 1; } ;;
  esac
}
_cursor_act_write() {
  local state="$1" prior="${2:-}" marker dir tmp
  marker="$(_cursor_act_marker)"; dir="$(dirname "$marker")"
  mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-cursor.act.XXXXXX")" || return 1
  { printf 'schema=1\nstate=%s\n' "$state"; case "$state" in activating|active) printf 'prior_cursortheme=%s\n' "$prior" ;; esac; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }
}
module::activate() {
  _cursor_marker_load || return 1
  [ "$_CURSOR_MARKER_STATE" = installed ] || { log::error "desktop/cursor is not installed; run 'atlas install desktop/cursor' before activating"; return 1; }
  { command -v kreadconfig6 && command -v kwriteconfig6; } >/dev/null 2>&1 || { log::error "kreadconfig6/kwriteconfig6 not found"; return 1; }
  _cursor_act_load || return 1
  local current; current="$(_cursor_read)"
  if [ "$_CURSOR_ACT_STATE" = active ]; then
    [ "$current" = "$_CURSOR_ACT_VALUE" ] && { log::info "Adwaita cursor already active"; return 0; }
    log::error "cursor theme changed since activation (now: $current); refusing to clobber — delete $(_cursor_act_marker) to disown"; return 1
  fi
  local prior="$_CURSOR_ACT_PRIOR"; [ -n "$prior" ] || prior="$current"
  _cursor_act_write activating "$prior" || return 1
  kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$_CURSOR_ACT_VALUE" >/dev/null 2>&1 || { log::error "failed to set the cursor theme"; return 1; }
  _cursor_act_write active "$prior" || return 1
  log::info "Adwaita cursor activated (applies at next login; prior recorded: $prior)"
}
module::deactivate() {
  _cursor_act_load || return 1
  case "$_CURSOR_ACT_STATE" in absent|inactive) log::info "desktop/cursor is not activated by Atlas"; return 0 ;; esac
  command -v kwriteconfig6 >/dev/null 2>&1 || { log::error "kwriteconfig6 not found"; return 1; }
  local current prior="$_CURSOR_ACT_PRIOR"; current="$(_cursor_read)"
  if [ "$_CURSOR_ACT_STATE" = active ] && [ "$current" != "$_CURSOR_ACT_VALUE" ]; then
    if [ "$current" = "$prior" ]; then _cursor_act_write inactive || return 1; log::info "cursor already restored to $prior; marked inactive"; return 0; fi
    log::error "cursor theme changed since activation (now: $current); refusing to restore — delete $(_cursor_act_marker) to disown"; return 1
  fi
  if [ "$prior" = "$_CURSOR_ACT_ABSENT" ]; then
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme --delete "" >/dev/null 2>&1 || { log::error "failed to remove the cursorTheme key; state left unchanged"; return 1; }
  else
    kwriteconfig6 --file kcminputrc --group Mouse --key cursorTheme "$prior" >/dev/null 2>&1 || { log::error "failed to restore prior cursor theme '$prior'; state left unchanged"; return 1; }
  fi
  _cursor_act_write inactive || return 1
  log::info "desktop/cursor deactivated; restored $prior (applies at next login)"
}
