#!/usr/bin/env bash
# desktop/theme - RFC-0017.
MODULE_NAME="theme"
MODULE_DESCRIPTION="Atlas theme: installs the Atlas dark KDE color scheme asset."
MODULE_DEPENDS=()

_THEME_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_theme_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-theme"; }
_theme_asset_source() { printf '%s\n' "$_THEME_MODULE_DIR/assets/Atlas.colors"; }
_theme_asset_file() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes/Atlas.colors"; }
_theme_sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

_theme_marker_init() { _THEME_MARKER_STATE=absent; _THEME_MARKER_SHA=; }
_theme_hash_valid() { [ "${#1}" -eq 64 ] && case "$1" in *[!0-9a-f]*|"") return 1 ;; *) return 0 ;; esac; }

_theme_marker_load() {
  _theme_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_sha=0
  marker="$(_theme_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then log::error "Theme marker is not a readable regular file: $marker"; return 1; fi
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "Theme marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue; case "$line" in \#*) continue ;; esac
    case "$line" in *=*) key="${line%%=*}"; val="${line#*=}" ;; *) log::error "Theme marker has an invalid line: $line"; return 1 ;; esac
    case "$key" in
      schema) [ "$val" = "1" ] || { log::error "Theme marker schema is unsupported: $val"; return 1; }; seen_schema=1 ;;
      state) case "$val" in installing|installed|detached) _THEME_MARKER_STATE="$val" ;; *) log::error "Theme marker state is invalid: $val"; return 1 ;; esac; seen_state=1 ;;
      asset_sha256) _THEME_MARKER_SHA="$val"; seen_sha=1 ;;
      *) log::error "Theme marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] || { log::error "Theme marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Theme marker is missing state"; return 1; }
  [ "$seen_sha" -eq 1 ] || { log::error "Theme marker is missing asset_sha256"; return 1; }
  _theme_hash_valid "$_THEME_MARKER_SHA" || { log::error "Theme marker asset_sha256 is invalid"; return 1; }
}

_theme_marker_write() {
  local state="$1" marker dir tmp sha
  marker="$(_theme_marker)"; dir="$(dirname "$marker")"; sha="$(_theme_sha256 "$(_theme_asset_source)")"
  [ -n "$sha" ] || { log::error "cannot hash Atlas theme source"; return 1; }
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.desktop-theme.XXXXXX")" || { log::error "cannot create Theme marker temp file"; return 1; }
  { printf 'schema=1\n'; printf 'state=%s\n' "$state"; printf 'asset_sha256=%s\n' "$sha"; } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_theme_asset_matches() {
  local dest="$(_theme_asset_file)" src="$(_theme_asset_source)"
  [ -f "$dest" ] && [ ! -L "$dest" ] && [ "$(_theme_sha256 "$dest")" = "$(_theme_sha256 "$src")" ]
}

_theme_write_asset() {
  local src="$(_theme_asset_source)" dest="$(_theme_asset_file)" dir tmp
  [ -r "$src" ] || { log::error "Atlas theme source missing"; return 1; }
  if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then log::error "Atlas theme target is not a regular file: $dest"; return 1; fi
  _theme_asset_matches && return 0
  dir="$(dirname "$dest")"; mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  tmp="$(mktemp "$dir/.Atlas.colors.XXXXXX")" || { log::error "cannot create theme temp file"; return 1; }
  cp "$src" "$tmp" || { rm -f "$tmp"; log::error "cannot stage $dest"; return 1; }
  chmod 644 "$tmp" || { rm -f "$tmp"; log::error "cannot chmod $tmp"; return 1; }
  mv -f "$tmp" "$dest" || { rm -f "$tmp"; log::error "cannot replace $dest"; return 1; }
}

_theme_preflight_absent() {
  if [ -e "$(_theme_asset_file)" ] || [ -L "$(_theme_asset_file)" ]; then log::error "Atlas theme asset already exists and is not Atlas-owned: $(_theme_asset_file)"; return 1; fi
}

module::check() { _theme_marker_load || return 1; [ "$_THEME_MARKER_STATE" = "installed" ] || return 1; _theme_asset_matches; }
module::install() {
  os::is_fedora || { log::error "desktop/theme supports Fedora only"; return 1; }
  _theme_marker_load || return 1
  case "$_THEME_MARKER_STATE" in absent) _theme_preflight_absent || return 1 ;; detached) _theme_preflight_absent || return 1 ;; installing|installed) ;; esac
  _theme_marker_write installing || return 1
  _theme_write_asset || return 1
  _theme_marker_write installed || return 1
}
module::verify() {
  _theme_marker_load || return 1
  case "$_THEME_MARKER_STATE" in absent) log::info "desktop/theme is not installed by Atlas"; return 0 ;; detached) log::warn "desktop/theme is detached"; return 0 ;; installing) log::error "desktop/theme install is incomplete"; return 1 ;; esac
  _theme_asset_matches || { log::error "Atlas theme asset is missing or drifted"; return 1; }
}
module::update() { _theme_marker_load || return 1; case "$_THEME_MARKER_STATE" in absent|detached) return 0 ;; esac; _theme_write_asset && _theme_marker_write installed; }
module::remove() { _theme_marker_load || return 1; case "$_THEME_MARKER_STATE" in absent|detached) return 0 ;; esac; _theme_asset_matches || { log::error "refusing to remove drifted Atlas theme"; return 1; }; rm -f "$(_theme_asset_file)" || return 1; _theme_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/theme is reconstructable from Atlas"; }
module::restore() { log::info "nothing to restore: reinstall desktop/theme to reconstruct Atlas-owned theme"; }
