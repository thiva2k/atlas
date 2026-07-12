#!/usr/bin/env bash
# development/starship - RFC-0011.
#
# Atlas owns an isolated Starship prompt config. It does not install Starship,
# activate shell integration, or edit user-owned Starship/shell configuration.
MODULE_NAME="starship"
MODULE_DESCRIPTION="Starship prompt theme: installs Atlas's engineering-focused prompt config."
MODULE_DEPENDS=()

_STARSHIP_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_starship_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-starship"
}

_starship_config_dir() {
  printf '%s\n' "${ATLAS_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/atlas}/starship"
}

_starship_config_file() { printf '%s\n' "$(_starship_config_dir)/starship.toml"; }
_starship_config_source() { printf '%s\n' "$_STARSHIP_MODULE_DIR/config/starship.toml"; }
_starship_user_config_file() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"; }
_starship_binary() { printf '%s\n' starship; }
_starship_sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

_starship_marker_init() {
  _STARSHIP_MARKER_STATE=absent
  _STARSHIP_MARKER_CONFIG_PATH=
  _STARSHIP_MARKER_CONFIG_SHA=
}

_starship_hash_valid() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in *[!0-9a-f]*|"") return 1 ;; *) return 0 ;; esac
}

_starship_marker_load() {
  _starship_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_config=0 seen_sha=0
  marker="$(_starship_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Starship marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Starship marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Starship marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Starship marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Starship marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed|detached) _STARSHIP_MARKER_STATE="$val" ;;
          *) log::error "Starship marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      config_path) _STARSHIP_MARKER_CONFIG_PATH="$val"; seen_config=1 ;;
      config_sha256) _STARSHIP_MARKER_CONFIG_SHA="$val"; seen_sha=1 ;;
      *) log::error "Starship marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Starship marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Starship marker is missing state"; return 1; }
  [ "$seen_config" -eq 1 ] || { log::error "Starship marker is missing config_path"; return 1; }
  [ "$seen_sha" -eq 1 ] || { log::error "Starship marker is missing config_sha256"; return 1; }
  [ "$_STARSHIP_MARKER_CONFIG_PATH" = "$(_starship_config_file)" ] || {
    log::error "Starship marker config_path does not match this environment"; return 1; }
  _starship_hash_valid "$_STARSHIP_MARKER_CONFIG_SHA" || {
    log::error "Starship marker config_sha256 is invalid"; return 1; }
}

_starship_marker_write() {
  local state="$1" marker dir tmp config_sha
  marker="$(_starship_marker)"
  dir="$(dirname "$marker")"
  config_sha="$(_starship_sha256 "$(_starship_config_source)")"
  [ -n "$config_sha" ] || { log::error "cannot hash Starship config source"; return 1; }
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-starship.XXXXXX")" || {
    log::error "cannot create a Starship marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'config_path=%s\n' "$(_starship_config_file)"
    printf 'config_sha256=%s\n' "$config_sha"
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_starship_config_matches_source() {
  local dest="$(_starship_config_file)" src="$(_starship_config_source)"
  [ -f "$dest" ] || return 1
  [ ! -L "$dest" ] || return 1
  [ "$(_starship_sha256 "$dest")" = "$(_starship_sha256 "$src")" ]
}

_starship_write_config() {
  local src dest dir tmp
  src="$(_starship_config_source)"
  dest="$(_starship_config_file)"
  [ -r "$src" ] || { log::error "Starship config source missing: $src"; return 1; }
  if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
    log::error "Starship managed config is not a regular file: $dest"
    return 1
  fi
  if _starship_config_matches_source; then
    log::info "Starship config already matches Atlas source"
    return 0
  fi
  dir="$(dirname "$dest")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.starship.toml.XXXXXX")" || {
    log::error "cannot create Starship config temp file in $dir"; return 1; }
  cp "$src" "$tmp" || { rm -f "$tmp"; log::error "cannot stage $dest"; return 1; }
  chmod 644 "$tmp" || { rm -f "$tmp"; log::error "cannot chmod $tmp"; return 1; }
  mv -f "$tmp" "$dest" || { rm -f "$tmp"; log::error "cannot replace $dest"; return 1; }
}

_starship_validate_if_present() {
  if ! os::has_cmd starship; then
    log::warn "Starship binary is not present; Atlas installed only the prompt config"
    return 0
  fi
  STARSHIP_CONFIG="$(_starship_config_file)" "$(_starship_binary)" prompt >/dev/null 2>&1 || {
    log::error "Starship rejected the Atlas prompt config"; return 1; }
}

_starship_unmanaged_present() {
  os::has_cmd starship && return 0
  return 1
}

_starship_preflight_absent() {
  if [ -e "$(_starship_config_file)" ] || [ -L "$(_starship_config_file)" ]; then
    log::error "Starship Atlas config already exists and is not Atlas-owned: $(_starship_config_file)"
    log::error "  fix: move or remove it before Atlas manages development/starship"
    return 1
  fi
  return 0
}

_starship_preflight_detached() {
  if [ -e "$(_starship_config_file)" ] || [ -L "$(_starship_config_file)" ]; then
    log::error "Starship Atlas config exists while development/starship is detached: $(_starship_config_file)"
    log::error "  fix: move or remove it before re-enrolling development/starship"
    return 1
  fi
}

module::check() {
  _starship_marker_load || return 1
  [ "$_STARSHIP_MARKER_STATE" = "installed" ] || return 1
  _starship_config_matches_source || return 1
}

module::install() {
  os::is_fedora || { log::error "development/starship supports Fedora only"; return 1; }
  _starship_marker_load || return 1
  case "$_STARSHIP_MARKER_STATE" in
    absent) _starship_preflight_absent || return 1 ;;
    detached) _starship_preflight_detached || return 1 ;;
    installing|installed) ;;
  esac
  _starship_marker_write installing || return 1
  _starship_write_config || return 1
  _starship_validate_if_present || return 1
  _starship_marker_write installed || return 1
  log::info "Starship prompt config is installed"
}

module::verify() {
  _starship_marker_load || return 1
  case "$_STARSHIP_MARKER_STATE" in
    absent)
      if _starship_unmanaged_present; then
        log::info "Starship is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "development/starship is not installed by Atlas"
      fi
      return 0
      ;;
    detached)
      log::warn "development/starship is detached; Atlas is not asserting prompt config"
      return 0
      ;;
    installing)
      log::error "development/starship install is incomplete; rerun 'atlas install development/starship'"
      return 1
      ;;
  esac
  _starship_config_matches_source || { log::error "Starship managed config is missing or drifted"; return 1; }
  _starship_validate_if_present || return 1
  log::info "Starship prompt config is healthy"
}

module::update() {
  _starship_marker_load || return 1
  case "$_STARSHIP_MARKER_STATE" in
    absent|detached)
      log::info "development/starship is not actively managed by Atlas; nothing to update"
      return 0
      ;;
    installing|installed) ;;
  esac
  _starship_write_config || return 1
  _starship_validate_if_present || return 1
  _starship_marker_write installed || return 1
}

module::remove() {
  _starship_marker_load || return 1
  case "$_STARSHIP_MARKER_STATE" in
    absent)
      log::info "development/starship is not installed by Atlas; nothing to detach"
      return 0
      ;;
    detached)
      log::info "development/starship is already detached from Atlas"
      return 0
      ;;
  esac
  _starship_config_matches_source || {
    log::error "refusing to remove drifted Starship config"; return 1; }
  rm -f "$(_starship_config_file)" || { log::error "cannot remove $(_starship_config_file)"; return 1; }
  rmdir "$(_starship_config_dir)" 2>/dev/null || true
  _starship_marker_write detached || return 1
  log::info "detached development/starship without touching user prompt or shell config"
}

module::backup() {
  log::info "nothing to back up: development/starship config is reconstructable from Atlas"
}

module::restore() {
  log::info "nothing to restore: reinstall development/starship to reconstruct Atlas-owned prompt config"
}
