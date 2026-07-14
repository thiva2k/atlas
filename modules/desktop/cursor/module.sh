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
