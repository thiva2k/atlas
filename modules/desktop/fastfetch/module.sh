#!/usr/bin/env bash
# desktop/fastfetch - RFC-0010.
#
# Atlas owns one system Fastfetch default config. User Fastfetch config remains
# user-owned and has precedence.
MODULE_NAME="fastfetch"
MODULE_DESCRIPTION="Fastfetch identity: installs Fastfetch and applies Atlas's workstation identity layout."
MODULE_DEPENDS=()

_FASTFETCH_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_FASTFETCH_PACKAGE="fastfetch"

_fastfetch_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-fastfetch"
}

_fastfetch_config_source() { printf '%s\n' "$_FASTFETCH_MODULE_DIR/config/config.jsonc"; }
_fastfetch_config_file() { printf '%s\n' "/etc/xdg/fastfetch/config.jsonc"; }
_fastfetch_binary() { printf '%s\n' "/usr/bin/fastfetch"; }
_fastfetch_sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

_fastfetch_run_privileged() {
  if os::is_root; then "$@"; else sudo "$@"; fi
}

_fastfetch_marker_init() {
  _FASTFETCH_MARKER_STATE=absent
  _FASTFETCH_MARKER_PACKAGE=
  _FASTFETCH_MARKER_CONFIG_PATH=
  _FASTFETCH_MARKER_CONFIG_SHA=
}

_fastfetch_hash_valid() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in *[!0-9a-f]*|"") return 1 ;; *) return 0 ;; esac
}

_fastfetch_marker_load() {
  _fastfetch_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_package=0 seen_config=0 seen_sha=0
  marker="$(_fastfetch_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Fastfetch marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Fastfetch marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Fastfetch marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Fastfetch marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Fastfetch marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed|detached) _FASTFETCH_MARKER_STATE="$val" ;;
          *) log::error "Fastfetch marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      package) _FASTFETCH_MARKER_PACKAGE="$val"; seen_package=1 ;;
      config_path) _FASTFETCH_MARKER_CONFIG_PATH="$val"; seen_config=1 ;;
      config_sha256) _FASTFETCH_MARKER_CONFIG_SHA="$val"; seen_sha=1 ;;
      *) log::error "Fastfetch marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Fastfetch marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Fastfetch marker is missing state"; return 1; }
  [ "$seen_package" -eq 1 ] || { log::error "Fastfetch marker is missing package"; return 1; }
  [ "$seen_config" -eq 1 ] || { log::error "Fastfetch marker is missing config_path"; return 1; }
  [ "$seen_sha" -eq 1 ] || { log::error "Fastfetch marker is missing config_sha256"; return 1; }
  [ "$_FASTFETCH_MARKER_PACKAGE" = "$_FASTFETCH_PACKAGE" ] || {
    log::error "Fastfetch marker package is unsupported: $_FASTFETCH_MARKER_PACKAGE"; return 1; }
  [ "$_FASTFETCH_MARKER_CONFIG_PATH" = "$(_fastfetch_config_file)" ] || {
    log::error "Fastfetch marker config_path does not match this module"; return 1; }
  _fastfetch_hash_valid "$_FASTFETCH_MARKER_CONFIG_SHA" || {
    log::error "Fastfetch marker config_sha256 is invalid"; return 1; }
  [ "$_FASTFETCH_MARKER_CONFIG_SHA" = "$(_fastfetch_sha256 "$(_fastfetch_config_source)")" ] || {
    log::error "Fastfetch marker config_sha256 does not match Atlas source"; return 1; }
}

_fastfetch_marker_write() {
  local state="$1" marker dir tmp config_sha
  marker="$(_fastfetch_marker)"
  dir="$(dirname "$marker")"
  config_sha="$(_fastfetch_sha256 "$(_fastfetch_config_source)")"
  [ -n "$config_sha" ] || { log::error "cannot hash Fastfetch config source"; return 1; }
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.desktop-fastfetch.XXXXXX")" || {
    log::error "cannot create a Fastfetch marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'package=%s\n' "$_FASTFETCH_PACKAGE"
    printf 'config_path=%s\n' "$(_fastfetch_config_file)"
    printf 'config_sha256=%s\n' "$config_sha"
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_fastfetch_config_matches_source() {
  local dest="$(_fastfetch_config_file)" src="$(_fastfetch_config_source)"
  [ -f "$dest" ] || return 1
  [ ! -L "$dest" ] || return 1
  [ "$(_fastfetch_sha256 "$dest")" = "$(_fastfetch_sha256 "$src")" ]
}

_fastfetch_write_config() {
  local src dest dir tmp
  src="$(_fastfetch_config_source)"
  dest="$(_fastfetch_config_file)"
  [ -r "$src" ] || { log::error "Fastfetch config source missing: $src"; return 1; }
  if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
    log::error "Fastfetch managed config is not a regular file: $dest"
    return 1
  fi
  if _fastfetch_config_matches_source; then
    log::info "Fastfetch config already matches Atlas source"
    return 0
  fi
  dir="$(dirname "$dest")"
  if [ -d "$dir" ] && [ -w "$dir" ]; then
    tmp="$(mktemp "$dir/.config.jsonc.XXXXXX")" || { log::error "cannot create config temp file in $dir"; return 1; }
    cp "$src" "$tmp" || { rm -f "$tmp"; log::error "cannot stage $dest"; return 1; }
    chmod 644 "$tmp" || { rm -f "$tmp"; log::error "cannot chmod $tmp"; return 1; }
    mv -f "$tmp" "$dest" || { rm -f "$tmp"; log::error "cannot replace $dest"; return 1; }
  else
    _fastfetch_run_privileged mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
    tmp="$(_fastfetch_run_privileged mktemp "$dir/.config.jsonc.XXXXXX")" || { log::error "cannot create privileged config temp file in $dir"; return 1; }
    if ! _fastfetch_run_privileged cp "$src" "$tmp"; then _fastfetch_run_privileged rm -f "$tmp" 2>/dev/null || true; log::error "cannot stage $dest"; return 1; fi
    if ! _fastfetch_run_privileged chmod 644 "$tmp"; then _fastfetch_run_privileged rm -f "$tmp" 2>/dev/null || true; log::error "cannot chmod $tmp"; return 1; fi
    if ! _fastfetch_run_privileged mv -f "$tmp" "$dest"; then _fastfetch_run_privileged rm -f "$tmp" 2>/dev/null || true; log::error "cannot replace $dest"; return 1; fi
  fi
}

_fastfetch_runnable() {
  local bin="$(_fastfetch_binary)"
  if ! "$bin" --version >/dev/null 2>&1; then
    log::error "Fastfetch is not runnable"
    return 1
  fi
  "$bin" --config "$(_fastfetch_config_file)" >/dev/null 2>&1 || {
    log::error "Fastfetch cannot run with the Atlas config"; return 1; }
}

_fastfetch_unmanaged_present() {
  os::has_cmd fastfetch && return 0
  [ -e "$(_fastfetch_binary)" ] && return 0
  return 1
}

_fastfetch_preflight_absent() {
  if [ -e "$(_fastfetch_config_file)" ] || [ -L "$(_fastfetch_config_file)" ]; then
    log::error "Fastfetch system config already exists and is not Atlas-owned: $(_fastfetch_config_file)"
    log::error "  fix: move or remove it before Atlas manages desktop/fastfetch"
    return 1
  fi
  return 0
}

module::check() {
  _fastfetch_marker_load || return 1
  [ "$_FASTFETCH_MARKER_STATE" = "installed" ] || return 1
  _fastfetch_config_matches_source || return 1
  _fastfetch_runnable >/dev/null 2>&1 || return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "desktop/fastfetch supports Fedora only"; return 1; }
  _fastfetch_marker_load || return 1
  case "$_FASTFETCH_MARKER_STATE" in
    absent) _fastfetch_preflight_absent || return 1 ;;
    detached|installing|installed) ;;
  esac
  _fastfetch_marker_write installing || return 1
  os::dnf_install "$_FASTFETCH_PACKAGE" || return 1
  _fastfetch_write_config || return 1
  _fastfetch_runnable || return 1
  _fastfetch_marker_write installed || return 1
  log::info "Fastfetch identity is installed"
}

module::verify() {
  _fastfetch_marker_load || return 1
  case "$_FASTFETCH_MARKER_STATE" in
    absent)
      if _fastfetch_unmanaged_present; then
        log::info "Fastfetch is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "desktop/fastfetch is not installed by Atlas"
      fi
      return 0
      ;;
    detached)
      log::warn "desktop/fastfetch is detached; Atlas is not asserting Fastfetch identity"
      return 0
      ;;
    installing)
      log::error "desktop/fastfetch install is incomplete; rerun 'atlas install desktop/fastfetch'"
      return 1
      ;;
  esac
  _fastfetch_config_matches_source || { log::error "Fastfetch managed config is missing or drifted"; return 1; }
  _fastfetch_runnable || return 1
  log::info "Fastfetch identity is healthy"
}

module::update() {
  _fastfetch_marker_load || return 1
  case "$_FASTFETCH_MARKER_STATE" in
    absent|detached)
      log::info "desktop/fastfetch is not actively managed by Atlas; nothing to update"
      return 0
      ;;
    installing|installed) ;;
  esac
  _fastfetch_write_config || return 1
  _fastfetch_runnable || return 1
  _fastfetch_marker_write installed || return 1
}

module::remove() {
  _fastfetch_marker_load || return 1
  case "$_FASTFETCH_MARKER_STATE" in
    absent)
      log::info "desktop/fastfetch is not installed by Atlas; nothing to detach"
      return 0
      ;;
    detached)
      log::info "desktop/fastfetch is already detached from Atlas"
      return 0
      ;;
  esac
  _fastfetch_config_matches_source || {
    log::error "refusing to remove drifted Fastfetch config"; return 1; }
  if [ -w "$(dirname "$(_fastfetch_config_file)")" ]; then
    rm -f "$(_fastfetch_config_file)" || { log::error "cannot remove $(_fastfetch_config_file)"; return 1; }
  else
    _fastfetch_run_privileged rm -f "$(_fastfetch_config_file)" || { log::error "cannot remove $(_fastfetch_config_file)"; return 1; }
  fi
  _fastfetch_marker_write detached || return 1
  log::info "detached desktop/fastfetch without uninstalling packages or touching user config"
}

module::backup() {
  log::info "nothing to back up: Atlas Fastfetch config is reconstructable; user config is user-owned"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall desktop/fastfetch to reconstruct Atlas-owned identity"
  return 0
}
