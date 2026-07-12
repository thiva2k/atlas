#!/usr/bin/env bash
# development/node - RFC-0013.
#
# Atlas owns Fedora package intent for Node.js 24 LTS and npm availability. It
# does not own package managers, global packages, npm configuration, or projects.
MODULE_NAME="node"
MODULE_DESCRIPTION="Node.js runtime: installs Fedora's Node.js 24 LTS and npm packages."
MODULE_DEPENDS=()

_NODE_PACKAGES=(nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin)

_node_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-node"
}

_node_node_bin() { printf '%s\n' "/usr/bin/node"; }
_node_npm_bin() { printf '%s\n' "/usr/bin/npm"; }

_node_fixed_env() {
  env -u NODE_OPTIONS -u NODE_PATH \
      -u NPM_CONFIG_USERCONFIG -u NPM_CONFIG_GLOBALCONFIG -u NPM_CONFIG_PREFIX \
      -u npm_config_userconfig -u npm_config_globalconfig -u npm_config_prefix \
      PATH=/usr/bin:/bin "$@"
}

_node_marker_init() {
  _NODE_MARKER_STATE=absent
  _NODE_MARKER_SOURCE=
  _NODE_MARKER_MAJOR=
  _NODE_MARKER_PACKAGES=
}

_node_marker_load() {
  _node_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_source=0 seen_major=0 seen_packages=0
  marker="$(_node_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Node marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Node marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Node marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Node marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Node marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed) _NODE_MARKER_STATE="$val" ;;
          *) log::error "Node marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      package_source)
        _NODE_MARKER_SOURCE="$val"
        seen_source=1
        ;;
      node_major)
        _NODE_MARKER_MAJOR="$val"
        seen_major=1
        ;;
      packages)
        _NODE_MARKER_PACKAGES="$val"
        seen_packages=1
        ;;
      *) log::error "Node marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Node marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Node marker is missing state"; return 1; }
  [ "$seen_source" -eq 1 ] || { log::error "Node marker is missing package_source"; return 1; }
  [ "$seen_major" -eq 1 ] || { log::error "Node marker is missing node_major"; return 1; }
  [ "$seen_packages" -eq 1 ] || { log::error "Node marker is missing packages"; return 1; }
  [ "$_NODE_MARKER_SOURCE" = "fedora" ] || {
    log::error "Node marker package_source is unsupported: $_NODE_MARKER_SOURCE"; return 1; }
  [ "$_NODE_MARKER_MAJOR" = "24" ] || {
    log::error "Node marker major is unsupported: $_NODE_MARKER_MAJOR"; return 1; }
  [ "$_NODE_MARKER_PACKAGES" = "nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin" ] || {
    log::error "Node marker package set is unsupported: $_NODE_MARKER_PACKAGES"; return 1; }
  return 0
}

_node_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_node_marker)"
  dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-node.XXXXXX")" || {
    log::error "cannot create a marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'package_source=fedora\n'
    printf 'node_major=24\n'
    printf 'packages=nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin\n'
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_node_pkg_present() {
  rpm -q "$1" >/dev/null 2>&1
}

_node_packages_installed() {
  local pkg
  for pkg in "${_NODE_PACKAGES[@]}"; do
    _node_pkg_present "$pkg" || return 1
  done
  return 0
}

_node_path_owned_by() {
  local path="$1" prefix="$2" owner
  [ -x "$path" ] || return 1
  owner="$(rpm -qf "$path" 2>/dev/null)" || return 1
  case "$owner" in
    "$prefix"-*) return 0 ;;
    *) return 1 ;;
  esac
}

_node_cmd_ok() {
  local out
  _node_path_owned_by "$(_node_node_bin)" nodejs24-bin || return 1
  out="$(_node_fixed_env "$(_node_node_bin)" --version 2>&1)" || return 1
  case "$out" in
    v24.*) return 0 ;;
    *) return 1 ;;
  esac
}

_node_npm_ok() {
  _node_path_owned_by "$(_node_npm_bin)" nodejs24-npm-bin || return 1
  _node_fixed_env "$(_node_npm_bin)" --version >/dev/null 2>&1
}

_node_runtime_healthy() {
  _node_packages_installed || { log::error "Node.js package set is incomplete"; return 1; }
  _node_cmd_ok || { log::error "system Node.js is missing, not RPM-owned by nodejs24-bin, not v24, or not runnable: $(_node_node_bin)"; return 1; }
  _node_npm_ok || { log::error "system npm is missing, not RPM-owned by nodejs24-npm-bin, or not runnable: $(_node_npm_bin)"; return 1; }
  return 0
}

_node_system_present() {
  [ -e "$(_node_node_bin)" ] && return 0
  [ -e "$(_node_npm_bin)" ] && return 0
  _node_pkg_present nodejs24 && return 0
  _node_pkg_present nodejs24-npm && return 0
  return 1
}

_node_preflight_path() {
  local path="$1" owner="$2" label="$3"
  [ -e "$path" ] || return 0
  if [ ! -x "$path" ]; then
    log::error "$label exists but is not executable: $path"
    return 1
  fi
  if ! _node_path_owned_by "$path" "$owner"; then
    log::error "$label exists but is not owned by Fedora package $owner: $path"
    return 1
  fi
  return 0
}

_node_preflight_system_paths() {
  _node_preflight_path "$(_node_node_bin)" nodejs24-bin "system Node.js" || return 1
  _node_preflight_path "$(_node_npm_bin)" nodejs24-npm-bin "system npm" || return 1
  return 0
}

module::check() {
  _node_marker_load || return 1
  [ "$_NODE_MARKER_STATE" = "installed" ] || return 1
  _node_runtime_healthy >/dev/null 2>&1 || return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "Node.js module supports Fedora only"; return 1; }
  _node_marker_load || return 1
  _node_preflight_system_paths || return 1
  _node_marker_write installing || return 1
  os::dnf_install "${_NODE_PACKAGES[@]}" || return 1
  _node_runtime_healthy || return 1
  _node_marker_write installed || return 1
  log::info "Node.js runtime is installed and managed by Atlas"
}

module::verify() {
  _node_marker_load || return 1
  case "$_NODE_MARKER_STATE" in
    absent)
      if _node_system_present; then
        log::info "Node.js runtime is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "Node.js runtime is absent and development/node is not installed by Atlas"
      fi
      return 0
      ;;
    installing)
      log::error "development/node install is incomplete; rerun 'atlas install development/node'"
      return 1
      ;;
  esac
  _node_runtime_healthy || return 1
  log::info "Node.js runtime is healthy"
}

module::update() {
  log::info "nothing to update: Node.js package currency is managed by Fedora updates"
  return 0
}

module::remove() {
  _node_marker_load || return 1
  case "$_NODE_MARKER_STATE" in
    absent) log::info "Node.js is not installed by Atlas; nothing to remove"; return 0 ;;
  esac
  rm -f "$(_node_marker)" || { log::error "cannot remove Node.js marker"; return 1; }
  log::info "removed Atlas Node.js marker without uninstalling Fedora packages"
}

module::backup() {
  log::info "nothing to back up: Node.js runtime state is reconstructable; npm config, packages, caches, and projects are user-owned"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall Node.js to reconstruct Atlas-owned runtime intent"
  return 0
}
