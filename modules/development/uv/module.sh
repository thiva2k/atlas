#!/usr/bin/env bash
# development/uv - RFC-0009.
#
# Atlas owns Fedora package intent for the uv CLI. It does not own projects,
# virtual environments, caches, uv tools, Python versions, or package indexes.
MODULE_NAME="uv"
MODULE_DESCRIPTION="uv package manager: installs Fedora's uv CLI."
MODULE_DEPENDS=("development/python")

_UV_PACKAGES=(uv)

_uv_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-uv"
}

_uv_bin() { printf '%s\n' "/usr/bin/uv"; }

_uv_fixed_env() {
  env -u UV_CACHE_DIR -u UV_CONFIG_FILE -u UV_TOOL_DIR \
      -u UV_PYTHON_INSTALL_DIR -u UV_PROJECT_ENVIRONMENT \
      -u VIRTUAL_ENV -u CONDA_PREFIX -u PYTHONHOME -u PYTHONPATH \
      PATH=/usr/bin:/bin "$@"
}

_uv_marker_init() {
  _UV_MARKER_STATE=absent
  _UV_MARKER_SOURCE=
  _UV_MARKER_PACKAGES=
  _UV_MARKER_DEPENDS=
}

_uv_marker_load() {
  _uv_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_source=0 seen_packages=0 seen_depends=0
  marker="$(_uv_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "uv marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect uv marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "uv marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "uv marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "uv marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed) _UV_MARKER_STATE="$val" ;;
          *) log::error "uv marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      package_source)
        _UV_MARKER_SOURCE="$val"
        seen_source=1
        ;;
      packages)
        _UV_MARKER_PACKAGES="$val"
        seen_packages=1
        ;;
      depends)
        _UV_MARKER_DEPENDS="$val"
        seen_depends=1
        ;;
      *) log::error "uv marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "uv marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "uv marker is missing state"; return 1; }
  [ "$seen_source" -eq 1 ] || { log::error "uv marker is missing package_source"; return 1; }
  [ "$seen_packages" -eq 1 ] || { log::error "uv marker is missing packages"; return 1; }
  [ "$seen_depends" -eq 1 ] || { log::error "uv marker is missing depends"; return 1; }
  [ "$_UV_MARKER_SOURCE" = "fedora" ] || {
    log::error "uv marker package_source is unsupported: $_UV_MARKER_SOURCE"; return 1; }
  [ "$_UV_MARKER_PACKAGES" = "uv" ] || {
    log::error "uv marker package set is unsupported: $_UV_MARKER_PACKAGES"; return 1; }
  [ "$_UV_MARKER_DEPENDS" = "development/python" ] || {
    log::error "uv marker dependency set is unsupported: $_UV_MARKER_DEPENDS"; return 1; }
  return 0
}

_uv_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_uv_marker)"
  dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-uv.XXXXXX")" || {
    log::error "cannot create a marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'package_source=fedora\n'
    printf 'packages=uv\n'
    printf 'depends=development/python\n'
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_uv_pkg_present() {
  rpm -q "$1" >/dev/null 2>&1
}

_uv_packages_installed() {
  local pkg
  for pkg in "${_UV_PACKAGES[@]}"; do
    _uv_pkg_present "$pkg" || return 1
  done
  return 0
}

_uv_path_owned_by() {
  local path="$1" prefix="$2" owner
  [ -x "$path" ] || return 1
  owner="$(rpm -qf "$path" 2>/dev/null)" || return 1
  case "$owner" in
    "$prefix"-*) return 0 ;;
    *) return 1 ;;
  esac
}

_uv_cmd_ok() {
  local out
  _uv_path_owned_by "$(_uv_bin)" uv || return 1
  out="$(_uv_fixed_env "$(_uv_bin)" --version 2>&1)" || return 1
  case "$out" in
    uv\ *) return 0 ;;
    *) return 1 ;;
  esac
}

_uv_runtime_healthy() {
  _uv_packages_installed || { log::error "uv package set is incomplete"; return 1; }
  _uv_cmd_ok || { log::error "system uv is missing, not RPM-owned by uv, or not runnable: $(_uv_bin)"; return 1; }
  return 0
}

_uv_system_present() {
  [ -e "$(_uv_bin)" ] && return 0
  _uv_pkg_present uv && return 0
  return 1
}

_uv_preflight_path() {
  local path="$1" owner="$2" label="$3"
  [ -e "$path" ] || return 0
  if [ ! -x "$path" ]; then
    log::error "$label exists but is not executable: $path"
    return 1
  fi
  if ! _uv_path_owned_by "$path" "$owner"; then
    log::error "$label exists but is not owned by Fedora package $owner: $path"
    return 1
  fi
  return 0
}

_uv_preflight_system_paths() {
  _uv_preflight_path "$(_uv_bin)" uv "system uv" || return 1
  return 0
}

module::check() {
  _uv_marker_load || return 1
  [ "$_UV_MARKER_STATE" = "installed" ] || return 1
  _uv_runtime_healthy >/dev/null 2>&1 || return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "uv module supports Fedora only"; return 1; }
  _uv_marker_load || return 1
  _uv_preflight_system_paths || return 1
  _uv_marker_write installing || return 1
  os::dnf_install "${_UV_PACKAGES[@]}" || return 1
  _uv_runtime_healthy || return 1
  _uv_marker_write installed || return 1
  log::info "uv CLI is installed and managed by Atlas"
}

module::verify() {
  _uv_marker_load || return 1
  case "$_UV_MARKER_STATE" in
    absent)
      if _uv_system_present; then
        log::info "uv is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "uv is absent and development/uv is not installed by Atlas"
      fi
      return 0
      ;;
    installing)
      log::error "development/uv install is incomplete; rerun 'atlas install development/uv'"
      return 1
      ;;
  esac
  _uv_runtime_healthy || return 1
  log::info "uv CLI is healthy"
}

module::update() {
  log::info "nothing to update: uv package currency is managed by Fedora updates"
  return 0
}

module::remove() {
  _uv_marker_load || return 1
  case "$_UV_MARKER_STATE" in
    absent) log::info "uv is not installed by Atlas; nothing to remove"; return 0 ;;
  esac
  rm -f "$(_uv_marker)" || { log::error "cannot remove uv marker"; return 1; }
  log::info "removed Atlas uv marker without uninstalling Fedora packages"
}

module::backup() {
  log::info "nothing to back up: uv CLI state is reconstructable; projects, environments, tools, and caches are user-owned"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall uv to reconstruct Atlas-owned CLI intent"
  return 0
}
