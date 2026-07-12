#!/usr/bin/env bash
# development/pnpm - RFC-0015.
#
# Atlas owns Fedora package intent for the pnpm CLI. It does not own projects,
# lockfiles, stores, caches, global packages, configuration, Corepack, or npmrc.
MODULE_NAME="pnpm"
MODULE_DESCRIPTION="pnpm package manager: installs Fedora's pnpm CLI."
MODULE_DEPENDS=("development/node")

_PNPM_PACKAGES=(pnpm)

_pnpm_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-pnpm"
}

_pnpm_bin() { printf '%s\n' "/usr/bin/pnpm"; }

_pnpm_fixed_env() {
  env -u PNPM_HOME -u PNPM_STORE_PATH -u PNPM_CONFIG_DIR \
      -u NPM_CONFIG_USERCONFIG -u NPM_CONFIG_GLOBALCONFIG -u NPM_CONFIG_PREFIX \
      -u npm_config_userconfig -u npm_config_globalconfig -u npm_config_prefix \
      -u NODE_OPTIONS -u NODE_PATH \
      -u COREPACK_HOME -u COREPACK_ENABLE_PROJECT_SPEC \
      PATH=/usr/bin:/bin "$@"
}

_pnpm_marker_init() {
  _PNPM_MARKER_STATE=absent
  _PNPM_MARKER_SOURCE=
  _PNPM_MARKER_PACKAGES=
  _PNPM_MARKER_DEPENDS=
}

_pnpm_marker_load() {
  _pnpm_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_source=0 seen_packages=0 seen_depends=0
  marker="$(_pnpm_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "pnpm marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect pnpm marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "pnpm marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "pnpm marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "pnpm marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed) _PNPM_MARKER_STATE="$val" ;;
          *) log::error "pnpm marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      package_source)
        _PNPM_MARKER_SOURCE="$val"
        seen_source=1
        ;;
      packages)
        _PNPM_MARKER_PACKAGES="$val"
        seen_packages=1
        ;;
      depends)
        _PNPM_MARKER_DEPENDS="$val"
        seen_depends=1
        ;;
      *) log::error "pnpm marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "pnpm marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "pnpm marker is missing state"; return 1; }
  [ "$seen_source" -eq 1 ] || { log::error "pnpm marker is missing package_source"; return 1; }
  [ "$seen_packages" -eq 1 ] || { log::error "pnpm marker is missing packages"; return 1; }
  [ "$seen_depends" -eq 1 ] || { log::error "pnpm marker is missing depends"; return 1; }
  [ "$_PNPM_MARKER_SOURCE" = "fedora" ] || {
    log::error "pnpm marker package_source is unsupported: $_PNPM_MARKER_SOURCE"; return 1; }
  [ "$_PNPM_MARKER_PACKAGES" = "pnpm" ] || {
    log::error "pnpm marker package set is unsupported: $_PNPM_MARKER_PACKAGES"; return 1; }
  [ "$_PNPM_MARKER_DEPENDS" = "development/node" ] || {
    log::error "pnpm marker dependency set is unsupported: $_PNPM_MARKER_DEPENDS"; return 1; }
  return 0
}

_pnpm_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_pnpm_marker)"
  dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-pnpm.XXXXXX")" || {
    log::error "cannot create a marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'package_source=fedora\n'
    printf 'packages=pnpm\n'
    printf 'depends=development/node\n'
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_pnpm_pkg_present() {
  rpm -q "$1" >/dev/null 2>&1
}

_pnpm_packages_installed() {
  local pkg
  for pkg in "${_PNPM_PACKAGES[@]}"; do
    _pnpm_pkg_present "$pkg" || return 1
  done
  return 0
}

_pnpm_path_owned_by() {
  local path="$1" prefix="$2" owner
  [ -x "$path" ] || return 1
  owner="$(rpm -qf "$path" 2>/dev/null)" || return 1
  case "$owner" in
    "$prefix"-*) return 0 ;;
    *) return 1 ;;
  esac
}

_pnpm_cmd_ok() {
  local out
  _pnpm_path_owned_by "$(_pnpm_bin)" pnpm || return 1
  out="$(_pnpm_fixed_env "$(_pnpm_bin)" --version 2>&1)" || return 1
  case "$out" in
    [0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

_pnpm_runtime_healthy() {
  _pnpm_packages_installed || { log::error "pnpm package set is incomplete"; return 1; }
  _pnpm_cmd_ok || { log::error "system pnpm is missing, not RPM-owned by pnpm, not runnable, or reports an unexpected version: $(_pnpm_bin)"; return 1; }
  return 0
}

_pnpm_system_present() {
  [ -e "$(_pnpm_bin)" ] && return 0
  _pnpm_pkg_present pnpm && return 0
  return 1
}

_pnpm_preflight_path() {
  local path="$1" owner="$2" label="$3"
  [ -e "$path" ] || return 0
  if [ ! -x "$path" ]; then
    log::error "$label exists but is not executable: $path"
    return 1
  fi
  if ! _pnpm_path_owned_by "$path" "$owner"; then
    log::error "$label exists but is not owned by Fedora package $owner: $path"
    return 1
  fi
  return 0
}

_pnpm_preflight_system_paths() {
  _pnpm_preflight_path "$(_pnpm_bin)" pnpm "system pnpm" || return 1
  return 0
}

module::check() {
  _pnpm_marker_load || return 1
  [ "$_PNPM_MARKER_STATE" = "installed" ] || return 1
  _pnpm_runtime_healthy >/dev/null 2>&1 || return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "pnpm module supports Fedora only"; return 1; }
  _pnpm_marker_load || return 1
  _pnpm_preflight_system_paths || return 1
  _pnpm_marker_write installing || return 1
  os::dnf_install "${_PNPM_PACKAGES[@]}" || return 1
  _pnpm_runtime_healthy || return 1
  _pnpm_marker_write installed || return 1
  log::info "pnpm CLI is installed and managed by Atlas"
}

module::verify() {
  _pnpm_marker_load || return 1
  case "$_PNPM_MARKER_STATE" in
    absent)
      if _pnpm_system_present; then
        log::info "pnpm is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "pnpm is absent and development/pnpm is not installed by Atlas"
      fi
      return 0
      ;;
    installing)
      log::error "development/pnpm install is incomplete; rerun 'atlas install development/pnpm'"
      return 1
      ;;
  esac
  _pnpm_runtime_healthy || return 1
  log::info "pnpm CLI is healthy"
}

module::update() {
  log::info "nothing to update: pnpm package currency is managed by Fedora updates"
  return 0
}

module::remove() {
  _pnpm_marker_load || return 1
  case "$_PNPM_MARKER_STATE" in
    absent) log::info "pnpm is not installed by Atlas; nothing to remove"; return 0 ;;
  esac
  rm -f "$(_pnpm_marker)" || { log::error "cannot remove pnpm marker"; return 1; }
  log::info "removed Atlas pnpm marker without uninstalling Fedora packages"
}

module::backup() {
  log::info "nothing to back up: pnpm CLI state is reconstructable; projects, stores, caches, packages, configuration, and credentials are user-owned"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall pnpm to reconstruct Atlas-owned CLI intent"
  return 0
}
