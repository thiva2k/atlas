#!/usr/bin/env bash
# development/codex - RFC-0026.
#
# Atlas owns one fixed Codex npm package boundary and its marker. It never owns
# authentication, API keys, conversations, project state, prompts, user config,
# MCP servers, skills, plugins, memory, or system Codex policy.
MODULE_NAME="codex"
MODULE_DESCRIPTION="Codex CLI: installs OpenAI's official npm package."
MODULE_DEPENDS=("development/node")

_CODEX_PACKAGE="@openai/codex"
_CODEX_PREFIX="/usr/local"
_CODEX_NPM_OWNER="nodejs24-npm-bin"

_codex_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-codex"
}

_codex_prefix() { printf '%s\n' "$_CODEX_PREFIX"; }
_codex_bin() { printf '%s\n' "$(_codex_prefix)/bin/codex"; }
_codex_package_dir() { printf '%s\n' "$(_codex_prefix)/lib/node_modules/$_CODEX_PACKAGE"; }
_codex_npm_bin() { printf '%s\n' "/usr/bin/npm"; }

_codex_run_privileged() {
  if os::is_root; then "$@"; else sudo "$@"; fi
}

_codex_fixed_env() {
  env -u OPENAI_API_KEY -u CODEX_HOME -u CODEX_CONFIG_DIR \
      -u NPM_CONFIG_USERCONFIG -u NPM_CONFIG_GLOBALCONFIG -u NPM_CONFIG_PREFIX \
      -u npm_config_userconfig -u npm_config_globalconfig -u npm_config_prefix \
      -u NODE_OPTIONS -u NODE_PATH -u COREPACK_HOME \
      PATH=/usr/bin:/bin "$@"
}

_codex_marker_init() {
  _CODEX_MARKER_STATE=absent
  _CODEX_MARKER_SOURCE=
  _CODEX_MARKER_PACKAGE=
  _CODEX_MARKER_PREFIX=
  _CODEX_MARKER_DEPENDS=
}

_codex_marker_load() {
  _codex_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_source=0 seen_package=0 seen_prefix=0 seen_depends=0
  marker="$(_codex_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Codex marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Codex marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Codex marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Codex marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Codex marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed) _CODEX_MARKER_STATE="$val" ;;
          *) log::error "Codex marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      package_source)
        _CODEX_MARKER_SOURCE="$val"
        seen_source=1
        ;;
      package)
        _CODEX_MARKER_PACKAGE="$val"
        seen_package=1
        ;;
      npm_prefix)
        _CODEX_MARKER_PREFIX="$val"
        seen_prefix=1
        ;;
      depends)
        _CODEX_MARKER_DEPENDS="$val"
        seen_depends=1
        ;;
      *) log::error "Codex marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Codex marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Codex marker is missing state"; return 1; }
  [ "$seen_source" -eq 1 ] || { log::error "Codex marker is missing package_source"; return 1; }
  [ "$seen_package" -eq 1 ] || { log::error "Codex marker is missing package"; return 1; }
  [ "$seen_prefix" -eq 1 ] || { log::error "Codex marker is missing npm_prefix"; return 1; }
  [ "$seen_depends" -eq 1 ] || { log::error "Codex marker is missing depends"; return 1; }
  [ "$_CODEX_MARKER_SOURCE" = "npm" ] || {
    log::error "Codex marker package_source is unsupported: $_CODEX_MARKER_SOURCE"; return 1; }
  [ "$_CODEX_MARKER_PACKAGE" = "$_CODEX_PACKAGE" ] || {
    log::error "Codex marker package is unsupported: $_CODEX_MARKER_PACKAGE"; return 1; }
  [ "$_CODEX_MARKER_PREFIX" = "$(_codex_prefix)" ] || {
    log::error "Codex marker npm_prefix is unsupported: $_CODEX_MARKER_PREFIX"; return 1; }
  [ "$_CODEX_MARKER_DEPENDS" = "development/node" ] || {
    log::error "Codex marker dependency set is unsupported: $_CODEX_MARKER_DEPENDS"; return 1; }
  return 0
}

_codex_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_codex_marker)"
  dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-codex.XXXXXX")" || {
    log::error "cannot create a marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'package_source=npm\n'
    printf 'package=%s\n' "$_CODEX_PACKAGE"
    printf 'npm_prefix=%s\n' "$(_codex_prefix)"
    printf 'depends=development/node\n'
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_codex_npm_ok() {
  local npm owner
  npm="$(_codex_npm_bin)"
  [ -x "$npm" ] || return 1
  owner="$(os::pkg_owner "$npm")" || return 1
  case "$owner" in
    "$_CODEX_NPM_OWNER"-*) ;;
    *) return 1 ;;
  esac
  _codex_fixed_env "$npm" --version >/dev/null 2>&1
}

_codex_package_present() {
  local package_json
  package_json="$(_codex_package_dir)/package.json"
  [ -r "$package_json" ] || return 1
  grep -Eq '"name"[[:space:]]*:[[:space:]]*"@openai/codex"' "$package_json"
}

_codex_command_package_owned() {
  local bin package_dir target
  bin="$(_codex_bin)"
  package_dir="$(_codex_package_dir)"
  [ -x "$bin" ] || return 1
  target="$(readlink -f "$bin" 2>/dev/null)" || return 1
  case "$target" in
    "$package_dir"/*) return 0 ;;
    *) return 1 ;;
  esac
}

_codex_command_ok() {
  local out
  _codex_command_package_owned || return 1
  out="$(_codex_fixed_env "$(_codex_bin)" --version 2>&1)" || return 1
  [ -n "$out" ]
}

_codex_runtime_healthy() {
  _codex_npm_ok || { log::error "system npm is missing, not RPM-owned by $_CODEX_NPM_OWNER, or not runnable: $(_codex_npm_bin)"; return 1; }
  _codex_package_present || { log::error "Codex npm package is missing or has unexpected package metadata: $(_codex_package_dir)"; return 1; }
  _codex_command_ok || { log::error "Codex command is missing, not package-owned, or not runnable: $(_codex_bin)"; return 1; }
  return 0
}

_codex_system_present() {
  [ -e "$(_codex_bin)" ] && return 0
  [ -e "$(_codex_package_dir)" ] && return 0
  command -v codex >/dev/null 2>&1 && return 0
  return 1
}

_codex_preflight_unmanaged_paths() {
  [ "$_CODEX_MARKER_STATE" = "absent" ] || return 0
  if [ -e "$(_codex_bin)" ]; then
    log::error "Codex command already exists outside Atlas ownership: $(_codex_bin)"
    return 1
  fi
  if [ -e "$(_codex_package_dir)" ]; then
    log::error "Codex npm package directory already exists outside Atlas ownership: $(_codex_package_dir)"
    return 1
  fi
  return 0
}

_codex_preflight_npm() {
  _codex_npm_ok || {
    log::error "Codex requires Atlas-managed npm at $(_codex_npm_bin) owned by $_CODEX_NPM_OWNER"
    return 1
  }
}

_codex_npm_install() {
  _codex_run_privileged env -u OPENAI_API_KEY -u CODEX_HOME -u CODEX_CONFIG_DIR \
    -u NPM_CONFIG_USERCONFIG -u NPM_CONFIG_GLOBALCONFIG -u NPM_CONFIG_PREFIX \
    -u npm_config_userconfig -u npm_config_globalconfig -u npm_config_prefix \
    -u NODE_OPTIONS -u NODE_PATH -u COREPACK_HOME \
    PATH=/usr/bin:/bin "$(_codex_npm_bin)" install -g "$_CODEX_PACKAGE" --prefix "$(_codex_prefix)" --no-audit --no-fund
}

_codex_npm_uninstall() {
  _codex_run_privileged env -u OPENAI_API_KEY -u CODEX_HOME -u CODEX_CONFIG_DIR \
    -u NPM_CONFIG_USERCONFIG -u NPM_CONFIG_GLOBALCONFIG -u NPM_CONFIG_PREFIX \
    -u npm_config_userconfig -u npm_config_globalconfig -u npm_config_prefix \
    -u NODE_OPTIONS -u NODE_PATH -u COREPACK_HOME \
    PATH=/usr/bin:/bin "$(_codex_npm_bin)" uninstall -g "$_CODEX_PACKAGE" --prefix "$(_codex_prefix)" --no-audit --no-fund
}

module::check() {
  _codex_marker_load || return 1
  [ "$_CODEX_MARKER_STATE" = "installed" ] || return 1
  _codex_runtime_healthy >/dev/null 2>&1 || return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "Codex module supports Fedora only"; return 1; }
  _codex_marker_load || return 1
  _codex_preflight_npm || return 1
  _codex_preflight_unmanaged_paths || return 1
  _codex_marker_write installing || return 1
  _codex_npm_install || return 1
  _codex_runtime_healthy || return 1
  _codex_marker_write installed || return 1
  log::info "Codex CLI is installed and managed by Atlas"
}

module::verify() {
  _codex_marker_load || return 1
  case "$_CODEX_MARKER_STATE" in
    absent)
      if _codex_system_present; then
        log::info "Codex CLI is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "Codex CLI is absent and development/codex is not installed by Atlas"
      fi
      return 0
      ;;
    installing)
      log::error "development/codex install is incomplete; rerun 'atlas install development/codex'"
      return 1
      ;;
  esac
  _codex_runtime_healthy || return 1
  log::info "Codex CLI is healthy"
}

module::update() {
  _codex_marker_load || return 1
  case "$_CODEX_MARKER_STATE" in
    absent) log::info "Codex is not installed by Atlas; nothing to update"; return 0 ;;
    installing) log::error "development/codex install is incomplete; rerun 'atlas install development/codex'"; return 1 ;;
  esac
  _codex_preflight_npm || return 1
  _codex_npm_install || return 1
  _codex_runtime_healthy || return 1
  log::info "Codex CLI package has been refreshed"
}

module::remove() {
  _codex_marker_load || return 1
  case "$_CODEX_MARKER_STATE" in
    absent) log::info "Codex is not installed by Atlas; nothing to remove"; return 0 ;;
  esac
  _codex_preflight_npm || return 1
  if [ -e "$(_codex_package_dir)" ] && ! _codex_package_present; then
    log::error "refusing to remove Codex because $(_codex_package_dir) no longer declares $_CODEX_PACKAGE"
    return 1
  fi
  if [ -e "$(_codex_bin)" ] && ! _codex_command_package_owned; then
    log::error "refusing to remove Codex because $(_codex_bin) no longer resolves inside $(_codex_package_dir)"
    return 1
  fi
  _codex_npm_uninstall || return 1
  rm -f "$(_codex_marker)" || { log::error "cannot remove Codex marker"; return 1; }
  log::info "removed Atlas-managed Codex npm package and marker"
}

module::backup() {
  log::info "nothing to back up: Codex authentication, conversations, project state, prompts, user config, MCP servers, skills, plugins, and memory are user-owned"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall Codex to reconstruct Atlas-owned CLI intent"
  return 0
}
