#!/usr/bin/env bash
# desktop/icons - RFC-0018.
MODULE_NAME="icons"
MODULE_DESCRIPTION="Icons: installs Atlas-approved modern professional icon assets."
MODULE_DEPENDS=()

_ICONS_PACKAGE="papirus-icon-theme"
_icons_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-icons"; }
_icons_package_installed() { rpm -q "$1" >/dev/null 2>&1; }
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
