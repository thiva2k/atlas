#!/usr/bin/env bash
# desktop/wallpapers - RFC-0021.
MODULE_NAME="wallpapers"
MODULE_DESCRIPTION="Wallpapers: installs a curated Atlas wallpaper collection without changing user selection."
MODULE_DEPENDS=()

_WALLPAPERS_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_wallpapers_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-wallpapers"; }
_wallpapers_source_dir() { printf '%s\n' "$_WALLPAPERS_MODULE_DIR/assets"; }
_wallpapers_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/atlas"; }
_wallpapers_manifest() { (cd "$(_wallpapers_source_dir)" && find . -type f -name '*.svg' -print | sort | xargs sha256sum) 2>/dev/null; }
_wallpapers_current_manifest() { (cd "$(_wallpapers_dir)" && find . -type f -name '*.svg' -print | sort | xargs sha256sum) 2>/dev/null; }
_wallpapers_marker_init() { _WALLPAPERS_MARKER_STATE=absent; }
_wallpapers_marker_load() {
  _wallpapers_marker_init
  local marker="$(_wallpapers_marker)" line val seen_schema=0 seen_state=0
  [ -e "$marker" ] || return 0
  [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || return 1
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue
    case "$line" in schema=1) seen_schema=1 ;; state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _WALLPAPERS_MARKER_STATE="$val" ;; *) return 1 ;; esac; seen_state=1 ;; *) ;; esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] && [ "$seen_state" -eq 1 ]
}
_wallpapers_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_wallpapers_marker)"; dir="$(dirname "$marker")"; mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-wallpapers.XXXXXX")" || return 1
  { printf 'schema=1\nstate=%s\n' "$state"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }
}
_wallpapers_match() { [ -d "$(_wallpapers_dir)" ] && [ "$(_wallpapers_manifest)" = "$(_wallpapers_current_manifest)" ]; }
_wallpapers_write() {
  local dest="$(_wallpapers_dir)" parent tmp
  parent="$(dirname "$dest")"; mkdir -p "$parent" || return 1
  tmp="$(mktemp -d "$parent/.atlas-wallpapers.XXXXXX")" || return 1
  cp "$(_wallpapers_source_dir)"/*.svg "$tmp"/ || { rm -rf "$tmp"; return 1; }
  chmod 755 "$tmp" || { rm -rf "$tmp"; return 1; }
  chmod 644 "$tmp"/*.svg || { rm -rf "$tmp"; return 1; }
  rm -rf "$dest" || { rm -rf "$tmp"; return 1; }
  mv "$tmp" "$dest" || { rm -rf "$tmp"; return 1; }
}
_wallpapers_preflight_absent() { [ ! -e "$(_wallpapers_dir)" ] && [ ! -L "$(_wallpapers_dir)" ]; }
module::check() { _wallpapers_marker_load || return 1; [ "$_WALLPAPERS_MARKER_STATE" = installed ] || return 1; _wallpapers_match; }
module::install() { os::is_fedora || return 1; _wallpapers_marker_load || return 1; case "$_WALLPAPERS_MARKER_STATE" in absent|detached) _wallpapers_preflight_absent || return 1 ;; esac; _wallpapers_marker_write installing || return 1; _wallpapers_write || return 1; _wallpapers_match || return 1; _wallpapers_marker_write installed; }
module::verify() { _wallpapers_marker_load || return 1; case "$_WALLPAPERS_MARKER_STATE" in absent|detached) return 0 ;; installing) return 1 ;; esac; _wallpapers_match; }
module::update() { _wallpapers_marker_load || return 1; case "$_WALLPAPERS_MARKER_STATE" in absent|detached) return 0 ;; esac; _wallpapers_write || return 1; _wallpapers_marker_write installed; }
module::remove() { _wallpapers_marker_load || return 1; case "$_WALLPAPERS_MARKER_STATE" in absent|detached) return 0 ;; esac; _wallpapers_match || return 1; rm -rf "$(_wallpapers_dir)" || return 1; _wallpapers_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/wallpapers is reconstructable from Atlas"; }
module::restore() { log::info "nothing to restore: reinstall desktop/wallpapers to reconstruct Atlas-owned wallpapers"; }
