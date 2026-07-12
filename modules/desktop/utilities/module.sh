#!/usr/bin/env bash
# desktop/utilities - RFC-0020.
MODULE_NAME="utilities"
MODULE_DESCRIPTION="Engineering utilities: installs btop, bat, fd, ripgrep, eza, and zoxide when missing."
MODULE_DEPENDS=()

_UTILITIES_PACKAGES=(btop bat fd-find ripgrep eza zoxide)
_utilities_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-utilities"; }
_utilities_package_installed() { rpm -q "$1" >/dev/null 2>&1; }
_utilities_marker_init() { _UTILITIES_MARKER_STATE=absent; }
_utilities_marker_load() {
  _utilities_marker_init
  local marker="$(_utilities_marker)" line val seen_schema=0 seen_state=0
  [ -e "$marker" ] || return 0
  [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || return 1
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue
    case "$line" in schema=1) seen_schema=1 ;; state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _UTILITIES_MARKER_STATE="$val" ;; *) return 1 ;; esac; seen_state=1 ;; packages=*) ;; *) return 1 ;; esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] && [ "$seen_state" -eq 1 ]
}
_utilities_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_utilities_marker)"; dir="$(dirname "$marker")"; mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-utilities.XXXXXX")" || return 1
  { printf 'schema=1\nstate=%s\npackages=%s\n' "$state" "${_UTILITIES_PACKAGES[*]}"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }
}
_utilities_missing_packages() {
  local pkg missing=()
  for pkg in "${_UTILITIES_PACKAGES[@]}"; do _utilities_package_installed "$pkg" || missing+=("$pkg"); done
  [ "${#missing[@]}" -eq 0 ] || printf '%s\n' "${missing[@]}"
}
_utilities_all_present() { [ -z "$(_utilities_missing_packages)" ]; }
module::check() { _utilities_marker_load || return 1; [ "$_UTILITIES_MARKER_STATE" = installed ] || return 1; _utilities_all_present; }
module::install() {
  os::is_fedora || return 1; _utilities_marker_load || return 1; _utilities_marker_write installing || return 1
  local missing; missing="$(_utilities_missing_packages)"
  if [ -n "$missing" ]; then readarray -t _missing_array <<< "$missing"; os::dnf_install "${_missing_array[@]}" || return 1; fi
  _utilities_all_present || return 1; _utilities_marker_write installed
}
module::verify() { _utilities_marker_load || return 1; case "$_UTILITIES_MARKER_STATE" in absent|detached) return 0 ;; installing) return 1 ;; esac; _utilities_all_present; }
module::update() { module::install; }
module::remove() { _utilities_marker_load || return 1; case "$_UTILITIES_MARKER_STATE" in absent|detached) return 0 ;; esac; _utilities_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/utilities owns no user config"; }
module::restore() { log::info "nothing to restore: reinstall desktop/utilities to reconstruct package intent"; }
