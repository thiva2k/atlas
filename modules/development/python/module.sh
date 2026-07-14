#!/usr/bin/env bash
# development/python - RFC-0006.
#
# Atlas owns Fedora package intent for the system Python runtime. It does not
# own virtual environments, user packages, pip configuration, or project state.
MODULE_NAME="python"
MODULE_DESCRIPTION="Python runtime: installs Fedora's system Python and pip packages."
MODULE_DEPENDS=()

_PYTHON_PACKAGES=(python3 python3-pip)

_python_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-python"
}

_python_python_bin() { printf '%s\n' "/usr/bin/python3"; }
_python_pip_bin() { printf '%s\n' "/usr/bin/pip3"; }

_python_fixed_env() {
  env -u PYTHONHOME -u PYTHONPATH -u PYTHONUSERBASE \
      -u PIP_CONFIG_FILE -u PIP_REQUIRE_VIRTUALENV \
      PATH=/usr/bin:/bin "$@"
}

_python_marker_init() {
  _PYTHON_MARKER_STATE=absent
  _PYTHON_MARKER_SOURCE=
  _PYTHON_MARKER_PACKAGES=
}

_python_marker_load() {
  _python_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_source=0 seen_packages=0
  marker="$(_python_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Python marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Python marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Python marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Python marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Python marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed) _PYTHON_MARKER_STATE="$val" ;;
          *) log::error "Python marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      package_source)
        _PYTHON_MARKER_SOURCE="$val"
        seen_source=1
        ;;
      packages)
        _PYTHON_MARKER_PACKAGES="$val"
        seen_packages=1
        ;;
      *) log::error "Python marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Python marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Python marker is missing state"; return 1; }
  [ "$seen_source" -eq 1 ] || { log::error "Python marker is missing package_source"; return 1; }
  [ "$seen_packages" -eq 1 ] || { log::error "Python marker is missing packages"; return 1; }
  [ "$_PYTHON_MARKER_SOURCE" = "fedora" ] || {
    log::error "Python marker package_source is unsupported: $_PYTHON_MARKER_SOURCE"; return 1; }
  [ "$_PYTHON_MARKER_PACKAGES" = "python3 python3-pip" ] || {
    log::error "Python marker package set is unsupported: $_PYTHON_MARKER_PACKAGES"; return 1; }
  return 0
}

_python_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_python_marker)"
  dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-python.XXXXXX")" || {
    log::error "cannot create a marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'package_source=fedora\n'
    printf 'packages=python3 python3-pip\n'
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_python_pkg_present() {
  os::pkg_installed "$1"
}

_python_packages_installed() {
  local pkg
  for pkg in "${_PYTHON_PACKAGES[@]}"; do
    _python_pkg_present "$pkg" || return 1
  done
  return 0
}

_python_path_owned_by() {
  local path="$1" prefix="$2" owner
  [ -x "$path" ] || return 1
  owner="$(os::pkg_owner "$path")" || return 1
  case "$owner" in
    "$prefix"-*) return 0 ;;
    *) return 1 ;;
  esac
}

_python_cmd_ok() {
  local out
  _python_path_owned_by "$(_python_python_bin)" python3 || return 1
  out="$(_python_fixed_env "$(_python_python_bin)" --version 2>&1)" || return 1
  case "$out" in
    Python\ 3.*) return 0 ;;
    *) return 1 ;;
  esac
}

_python_pip_ok() {
  _python_path_owned_by "$(_python_pip_bin)" python3-pip || return 1
  _python_fixed_env "$(_python_pip_bin)" --version >/dev/null 2>&1
}

_python_runtime_healthy() {
  _python_packages_installed || { log::error "Python package set is incomplete"; return 1; }
  _python_cmd_ok || { log::error "system Python is missing, not RPM-owned by python3, or not runnable: $(_python_python_bin)"; return 1; }
  _python_pip_ok || { log::error "system pip is missing, not RPM-owned by python3-pip, or not runnable: $(_python_pip_bin)"; return 1; }
  return 0
}

_python_system_runtime_present() {
  [ -e "$(_python_python_bin)" ] && return 0
  [ -e "$(_python_pip_bin)" ] && return 0
  _python_pkg_present python3 && return 0
  _python_pkg_present python3-pip && return 0
  return 1
}

_python_preflight_path() {
  local path="$1" owner="$2" label="$3"
  [ -e "$path" ] || return 0
  if [ ! -x "$path" ]; then
    log::error "$label exists but is not executable: $path"
    return 1
  fi
  if ! _python_path_owned_by "$path" "$owner"; then
    log::error "$label exists but is not owned by Fedora package $owner: $path"
    return 1
  fi
  return 0
}

_python_preflight_system_paths() {
  _python_preflight_path "$(_python_python_bin)" python3 "system Python" || return 1
  _python_preflight_path "$(_python_pip_bin)" python3-pip "system pip" || return 1
  return 0
}

module::check() {
  _python_marker_load || return 1
  [ "$_PYTHON_MARKER_STATE" = "installed" ] || return 1
  _python_runtime_healthy >/dev/null 2>&1 || return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "Python module supports Fedora only"; return 1; }
  _python_marker_load || return 1
  _python_preflight_system_paths || return 1
  _python_marker_write installing || return 1
  os::dnf_install "${_PYTHON_PACKAGES[@]}" || return 1
  _python_runtime_healthy || return 1
  _python_marker_write installed || return 1
  log::info "Python runtime is installed and managed by Atlas"
}

module::verify() {
  _python_marker_load || return 1
  case "$_PYTHON_MARKER_STATE" in
    absent)
      if _python_system_runtime_present; then
        log::info "Python runtime is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "Python runtime is absent and development/python is not installed by Atlas"
      fi
      return 0
      ;;
    installing)
      log::error "development/python install is incomplete; rerun 'atlas install development/python'"
      return 1
      ;;
  esac
  _python_runtime_healthy || return 1
  log::info "Python runtime is healthy"
}

module::update() {
  log::info "nothing to update: Python package currency is managed by Fedora updates"
  return 0
}

module::remove() {
  _python_marker_load || return 1
  case "$_PYTHON_MARKER_STATE" in
    absent) log::info "Python is not installed by Atlas; nothing to remove"; return 0 ;;
  esac
  rm -f "$(_python_marker)" || { log::error "cannot remove Python marker"; return 1; }
  log::info "removed Atlas Python marker without uninstalling Fedora packages"
}

module::backup() {
  log::info "nothing to back up: Python runtime state is reconstructable; environments and packages are user-owned"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall Python to reconstruct Atlas-owned runtime intent"
  return 0
}
