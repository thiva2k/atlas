#!/usr/bin/env bash
# development/fish - RFC-0014.
#
# Atlas owns Fedora package intent for Fish and one isolated Fish conf.d snippet.
# It does not own aliases, functions, completions, plugins, config.fish, login
# shell state, or terminal profiles.
MODULE_NAME="fish"
MODULE_DESCRIPTION="Fish shell: installs Fedora's fish package and an Atlas-owned conf.d snippet."
MODULE_DEPENDS=()

_FISH_PACKAGES=(fish)

_fish_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-fish"
}

_fish_bin() { printf '%s\n' "/usr/bin/fish"; }

_fish_config_file() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/00-atlas.fish"
}

_fish_config_content() {
  printf '%s\n' "# Managed by Atlas: development/fish. Do not edit."
  printf '%s\n' "set -g""x ATLAS_SHELL fish"
  # RFC-0034: the cursor is the HUD's one live element — a blinking bar (Ghostty
  # paints it cyan). Ghostty's shell-integration hands cursor control to fish, so
  # fish must set the blink itself or the config setting is overridden.
  printf '%s\n' "set -g fish_cursor_default line blink"
  printf '%s\n' "set -g fish_cursor_insert line blink"
  # RFC-0034: the SYSTEM ONLINE greeting. Fires only for a top-level interactive
  # shell (a new terminal), never nested subshells, and only if fastfetch is
  # present — so the wiring is loosely coupled to desktop/fastfetch.
  printf '%s\n' "if status is-interactive; and test \"\$SHLVL\" -le 1; and command -q fastfetch"
  printf '%s\n' "    fastfetch"
  printf '%s\n' "end"
}

_fish_config_hash() {
  _fish_config_content | sha256sum | awk '{print $1}'
}

_fish_file_hash() {
  sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

_fish_hash_valid() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in
    *[!0-9a-f]*|"") return 1 ;;
    *) return 0 ;;
  esac
}

_fish_marker_init() {
  _FISH_MARKER_STATE=absent
  _FISH_MARKER_SOURCE=
  _FISH_MARKER_PACKAGES=
  _FISH_MARKER_CONFIG_PATH=
  _FISH_MARKER_CONFIG_SHA256=
}

_fish_marker_load() {
  _fish_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_source=0 seen_packages=0 seen_path=0 seen_hash=0
  marker="$(_fish_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Fish marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Fish marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Fish marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Fish marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Fish marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed) _FISH_MARKER_STATE="$val" ;;
          *) log::error "Fish marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      package_source)
        _FISH_MARKER_SOURCE="$val"
        seen_source=1
        ;;
      packages)
        _FISH_MARKER_PACKAGES="$val"
        seen_packages=1
        ;;
      config_path)
        _FISH_MARKER_CONFIG_PATH="$val"
        seen_path=1
        ;;
      config_sha256)
        _FISH_MARKER_CONFIG_SHA256="$val"
        seen_hash=1
        ;;
      *) log::error "Fish marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Fish marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Fish marker is missing state"; return 1; }
  [ "$seen_source" -eq 1 ] || { log::error "Fish marker is missing package_source"; return 1; }
  [ "$seen_packages" -eq 1 ] || { log::error "Fish marker is missing packages"; return 1; }
  [ "$seen_path" -eq 1 ] || { log::error "Fish marker is missing config_path"; return 1; }
  [ "$seen_hash" -eq 1 ] || { log::error "Fish marker is missing config_sha256"; return 1; }
  [ "$_FISH_MARKER_SOURCE" = "fedora" ] || {
    log::error "Fish marker package_source is unsupported: $_FISH_MARKER_SOURCE"; return 1; }
  [ "$_FISH_MARKER_PACKAGES" = "fish" ] || {
    log::error "Fish marker package set is unsupported: $_FISH_MARKER_PACKAGES"; return 1; }
  [ "$_FISH_MARKER_CONFIG_PATH" = "$(_fish_config_file)" ] || {
    log::error "Fish marker config_path is unsupported: $_FISH_MARKER_CONFIG_PATH"; return 1; }
  _fish_hash_valid "$_FISH_MARKER_CONFIG_SHA256" || {
    log::error "Fish marker config_sha256 is invalid"; return 1; }
  return 0
}

_fish_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_fish_marker)"
  dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-fish.XXXXXX")" || {
    log::error "cannot create a marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'package_source=fedora\n'
    printf 'packages=fish\n'
    printf 'config_path=%s\n' "$(_fish_config_file)"
    printf 'config_sha256=%s\n' "$(_fish_config_hash)"
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_fish_config_write() {
  local path dir tmp
  path="$(_fish_config_file)"
  dir="$(dirname "$path")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  tmp="$(mktemp "$dir/.00-atlas.XXXXXX")" || {
    log::error "cannot create a Fish config temp file in $dir"; return 1; }
  _fish_config_content > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 644 "$tmp" || { rm -f "$tmp"; log::error "cannot set mode on $tmp"; return 1; }
  mv -f "$tmp" "$path" || { rm -f "$tmp"; log::error "cannot replace $path"; return 1; }
}

_fish_config_ok() {
  local path
  path="$(_fish_config_file)"
  [ -f "$path" ] || return 1
  [ "$(_fish_file_hash "$path")" = "$(_fish_config_hash)" ]
}

_fish_pkg_present() {
  os::pkg_installed "$1"
}

_fish_packages_installed() {
  local pkg
  for pkg in "${_FISH_PACKAGES[@]}"; do
    _fish_pkg_present "$pkg" || return 1
  done
  return 0
}

_fish_path_owned_by() {
  local path="$1" prefix="$2" owner
  [ -x "$path" ] || return 1
  owner="$(os::pkg_owner "$path")" || return 1
  case "$owner" in
    "$prefix"-*) return 0 ;;
    *) return 1 ;;
  esac
}

_fish_cmd_ok() {
  local out
  _fish_path_owned_by "$(_fish_bin)" fish || return 1
  out="$("$(_fish_bin)" --version 2>&1)" || return 1
  case "$out" in
    fish,\ version\ *) return 0 ;;
    *) return 1 ;;
  esac
}

_fish_runtime_healthy() {
  _fish_packages_installed || { log::error "Fish package set is incomplete"; return 1; }
  _fish_cmd_ok || { log::error "system Fish is missing, not RPM-owned by fish, or not runnable: $(_fish_bin)"; return 1; }
  _fish_config_ok || { log::error "Atlas Fish snippet is missing or drifted: $(_fish_config_file)"; return 1; }
  return 0
}

_fish_system_present() {
  [ -e "$(_fish_bin)" ] && return 0
  _fish_pkg_present fish && return 0
  return 1
}

_fish_preflight_path() {
  local path="$1" owner="$2" label="$3"
  [ -e "$path" ] || return 0
  if [ ! -x "$path" ]; then
    log::error "$label exists but is not executable: $path"
    return 1
  fi
  if ! _fish_path_owned_by "$path" "$owner"; then
    log::error "$label exists but is not owned by Fedora package $owner: $path"
    return 1
  fi
  return 0
}

_fish_preflight() {
  _fish_preflight_path "$(_fish_bin)" fish "system Fish" || return 1
  if [ "$_FISH_MARKER_STATE" = "absent" ] && [ -e "$(_fish_config_file)" ]; then
    log::error "Atlas Fish snippet path already exists but is not owned by Atlas: $(_fish_config_file)"
    return 1
  fi
  return 0
}

module::check() {
  _fish_marker_load || return 1
  [ "$_FISH_MARKER_STATE" = "installed" ] || return 1
  _fish_runtime_healthy >/dev/null 2>&1 || return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "Fish module supports Fedora only"; return 1; }
  _fish_marker_load || return 1
  _fish_preflight || return 1
  _fish_marker_write installing || return 1
  os::dnf_install "${_FISH_PACKAGES[@]}" || return 1
  _fish_config_write || return 1
  _fish_runtime_healthy || return 1
  _fish_marker_write installed || return 1
  log::info "Fish shell is installed and managed by Atlas"
}

module::verify() {
  _fish_marker_load || return 1
  case "$_FISH_MARKER_STATE" in
    absent)
      if [ -e "$(_fish_config_file)" ]; then
        log::warn "unmanaged Atlas Fish snippet exists: $(_fish_config_file)"
      elif _fish_system_present; then
        log::info "Fish is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "Fish is absent and development/fish is not installed by Atlas"
      fi
      return 0
      ;;
    installing)
      log::error "development/fish install is incomplete; rerun 'atlas install development/fish'"
      return 1
      ;;
  esac
  _fish_runtime_healthy || return 1
  log::info "Fish shell is healthy"
}

module::update() {
  _fish_marker_load || return 1
  [ "$_FISH_MARKER_STATE" = "installed" ] || {
    log::error "Fish is not installed by Atlas"; return 1; }
  _fish_config_write || return 1
  _fish_marker_write installed || return 1
  _fish_runtime_healthy || return 1
  log::info "restored Atlas Fish snippet"
}

module::remove() {
  _fish_marker_load || return 1
  case "$_FISH_MARKER_STATE" in
    absent) log::info "Fish is not installed by Atlas; nothing to remove"; return 0 ;;
  esac
  _fish_config_ok || { log::error "refusing to remove drifted Atlas Fish snippet"; return 1; }
  rm -f "$(_fish_config_file)" || { log::error "cannot remove Atlas Fish snippet"; return 1; }
  rm -f "$(_fish_marker)" || { log::error "cannot remove Fish marker"; return 1; }
  log::info "removed Atlas Fish snippet and marker without uninstalling Fedora packages"
}

module::backup() {
  log::info "nothing to back up: Fish package and Atlas snippet are reconstructable; user Fish configuration is user-owned"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall Fish to reconstruct Atlas-owned shell intent"
  return 0
}
