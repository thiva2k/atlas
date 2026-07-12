#!/usr/bin/env bash
# development/claude - RFC-0016.
#
# Atlas owns the Claude Code package boundary: the Anthropic RPM repository file
# it writes, one managed-settings drop-in, package intent, and the marker. It
# never owns auth, API keys, MCP servers, project config, sessions, or history.
MODULE_NAME="claude"
MODULE_DESCRIPTION="Claude Code CLI: installs Anthropic's signed RPM package."
MODULE_DEPENDS=()

_CLAUDE_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_CLAUDE_PACKAGES=(claude-code)
_CLAUDE_REPO_ID="claude-code"
_CLAUDE_REPO_URL="https://downloads.claude.ai/claude-code/rpm/stable"
_CLAUDE_GPG_URL="https://downloads.claude.ai/keys/claude-code.asc"
_CLAUDE_KEY_FP="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
_CLAUDE_KEY_SHA256="bd70a5e4a268002704024ceba7f8446024114e94f3f0bdd11c23a9e592be81c6"

_claude_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-claude"
}

_claude_repo_source() { printf '%s\n' "$_CLAUDE_MODULE_DIR/config/claude-code.repo"; }
_claude_key_source() { printf '%s\n' "$_CLAUDE_MODULE_DIR/config/claude-code.asc"; }
_claude_settings_source() { printf '%s\n' "$_CLAUDE_MODULE_DIR/config/00-atlas.json"; }
_claude_repo_file() { printf '%s\n' "/etc/yum.repos.d/claude-code.repo"; }
_claude_settings_file() { printf '%s\n' "/etc/claude-code/managed-settings.d/00-atlas.json"; }
_claude_bin() { printf '%s\n' "/usr/bin/claude"; }

_claude_sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

_claude_run_privileged() {
  if os::is_root; then "$@"; else sudo "$@"; fi
}

_claude_fixed_env() {
  env -u ANTHROPIC_API_KEY -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_USE_BEDROCK \
      -u CLAUDE_CODE_USE_VERTEX -u CLAUDE_CODE_GIT_BASH_PATH \
      -u CLAUDE_CODE_USE_POWERSHELL_TOOL -u CLAUDE_CODE_DISABLE_AUTO_MEMORY \
      -u DISABLE_AUTOUPDATER -u DISABLE_UPDATES \
      PATH=/usr/bin:/bin "$@"
}

_claude_marker_init() {
  _CLAUDE_MARKER_STATE=absent
  _CLAUDE_MARKER_SOURCE=
  _CLAUDE_MARKER_PACKAGES=
  _CLAUDE_MARKER_REPO_SHA=
  _CLAUDE_MARKER_SETTINGS_SHA=
}

_claude_marker_load() {
  _claude_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_source=0 seen_packages=0 seen_repo=0 seen_settings=0
  marker="$(_claude_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Claude marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Claude marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Claude marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Claude marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Claude marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed) _CLAUDE_MARKER_STATE="$val" ;;
          *) log::error "Claude marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      package_source)
        _CLAUDE_MARKER_SOURCE="$val"
        seen_source=1
        ;;
      packages)
        _CLAUDE_MARKER_PACKAGES="$val"
        seen_packages=1
        ;;
      repo_sha256)
        _CLAUDE_MARKER_REPO_SHA="$val"
        seen_repo=1
        ;;
      settings_sha256)
        _CLAUDE_MARKER_SETTINGS_SHA="$val"
        seen_settings=1
        ;;
      *) log::error "Claude marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Claude marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Claude marker is missing state"; return 1; }
  [ "$seen_source" -eq 1 ] || { log::error "Claude marker is missing package_source"; return 1; }
  [ "$seen_packages" -eq 1 ] || { log::error "Claude marker is missing packages"; return 1; }
  [ "$seen_repo" -eq 1 ] || { log::error "Claude marker is missing repo_sha256"; return 1; }
  [ "$seen_settings" -eq 1 ] || { log::error "Claude marker is missing settings_sha256"; return 1; }
  [ "$_CLAUDE_MARKER_SOURCE" = "$_CLAUDE_REPO_ID" ] || {
    log::error "Claude marker package_source is unsupported: $_CLAUDE_MARKER_SOURCE"; return 1; }
  [ "$_CLAUDE_MARKER_PACKAGES" = "claude-code" ] || {
    log::error "Claude marker package set is unsupported: $_CLAUDE_MARKER_PACKAGES"; return 1; }

  local repo_sha settings_sha
  repo_sha="$(_claude_sha256 "$(_claude_repo_source)")"
  settings_sha="$(_claude_sha256 "$(_claude_settings_source)")"
  [ -n "$repo_sha" ] || { log::error "cannot hash Claude repo source"; return 1; }
  [ -n "$settings_sha" ] || { log::error "cannot hash Claude settings source"; return 1; }
  [ "$_CLAUDE_MARKER_REPO_SHA" = "$repo_sha" ] || {
    log::error "Claude marker repo_sha256 does not match Atlas source"; return 1; }
  [ "$_CLAUDE_MARKER_SETTINGS_SHA" = "$settings_sha" ] || {
    log::error "Claude marker settings_sha256 does not match Atlas source"; return 1; }
  return 0
}

_claude_marker_write() {
  local state="$1" marker dir tmp repo_sha settings_sha
  marker="$(_claude_marker)"
  dir="$(dirname "$marker")"
  repo_sha="$(_claude_sha256 "$(_claude_repo_source)")"
  settings_sha="$(_claude_sha256 "$(_claude_settings_source)")"
  [ -n "$repo_sha" ] || { log::error "cannot hash Claude repo source"; return 1; }
  [ -n "$settings_sha" ] || { log::error "cannot hash Claude settings source"; return 1; }
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-claude.XXXXXX")" || {
    log::error "cannot create a marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'package_source=%s\n' "$_CLAUDE_REPO_ID"
    printf 'packages=claude-code\n'
    printf 'repo_sha256=%s\n' "$repo_sha"
    printf 'settings_sha256=%s\n' "$settings_sha"
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_claude_repo_source_valid() {
  local file
  file="$(_claude_repo_source)"
  [ -r "$file" ] || { log::error "Claude repo source missing: $file"; return 1; }
  grep -qxF "[$_CLAUDE_REPO_ID]" "$file" || { log::error "Claude repo source has wrong repo id"; return 1; }
  grep -qxF "baseurl=$_CLAUDE_REPO_URL" "$file" || { log::error "Claude repo source has wrong baseurl"; return 1; }
  grep -qxF "gpgcheck=1" "$file" || { log::error "Claude repo source must enable gpgcheck"; return 1; }
  grep -qxF "gpgkey=$_CLAUDE_GPG_URL" "$file" || { log::error "Claude repo source has wrong gpgkey"; return 1; }
}

_claude_settings_source_valid() {
  local file
  file="$(_claude_settings_source)"
  [ -r "$file" ] || { log::error "Claude managed settings source missing: $file"; return 1; }
  grep -qxF '{' "$file" || { log::error "Claude managed settings source has unexpected format"; return 1; }
  grep -qxF '  "env": {' "$file" || { log::error "Claude managed settings source must use env"; return 1; }
  grep -qxF '    "DISABLE_AUTOUPDATER": "1"' "$file" || {
    log::error "Claude managed settings source must disable background auto-updates"; return 1; }
  grep -qxF '  }' "$file" || { log::error "Claude managed settings source has unexpected object closing"; return 1; }
  grep -qxF '}' "$file" || { log::error "Claude managed settings source has unexpected closing"; return 1; }
}

_claude_key_present() {
  local fp
  fp="$(rpmkeys --list 2>/dev/null | awk '{print toupper($1)}' | tr -d '[:space:]')"
  case "$fp" in *"$_CLAUDE_KEY_FP"*) return 0 ;; *) return 1 ;; esac
}

_claude_key_source_valid() {
  local key tmp fp
  key="$(_claude_key_source)"
  [ -r "$key" ] || { log::error "Claude RPM signing key source missing: $key"; return 1; }
  [ "$(_claude_sha256 "$key")" = "$_CLAUDE_KEY_SHA256" ] || {
    log::error "Claude RPM signing key source hash does not match Atlas allowlist"; return 1; }
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/atlas-claude-rpm.XXXXXX")" || {
    log::error "cannot create a temporary RPM root"; return 1; }
  if ! rpmkeys --root "$tmp" --import "$key" >/dev/null 2>&1; then
    rm -rf "$tmp"
    log::error "Claude RPM signing key source cannot be parsed by rpmkeys"
    return 1
  fi
  fp="$(rpmkeys --root "$tmp" --list 2>/dev/null | awk '{print toupper($1)}' | tr -d '[:space:]')"
  rm -rf "$tmp"
  case "$fp" in
    "$_CLAUDE_KEY_FP") return 0 ;;
    *) log::error "Claude RPM signing key source fingerprint does not match Atlas allowlist"; return 1 ;;
  esac
}

_claude_import_key() {
  _claude_key_source_valid || return 1
  if _claude_key_present; then
    log::info "Claude Code RPM signing key is already trusted"
    return 0
  fi
  _claude_run_privileged rpmkeys --import "$(_claude_key_source)" || {
    log::error "cannot import Claude Code RPM signing key"; return 1; }
  _claude_key_present || { log::error "Claude Code RPM signing key fingerprint did not match the Atlas allowlist"; return 1; }
}

_claude_file_matches_source() {
  local dest="$1" src="$2"
  [ -f "$dest" ] || return 1
  [ "$(_claude_sha256 "$dest")" = "$(_claude_sha256 "$src")" ]
}

_claude_repo_matches_source() {
  _claude_file_matches_source "$(_claude_repo_file)" "$(_claude_repo_source)"
}

_claude_settings_matches_source() {
  _claude_file_matches_source "$(_claude_settings_file)" "$(_claude_settings_source)"
}

_claude_write_source_file() {
  local src="$1" dest="$2" label="$3" dir tmp
  if _claude_file_matches_source "$dest" "$src"; then
    log::info "$label already matches Atlas source"
    return 0
  fi
  dir="$(dirname "$dest")"
  if [ -d "$dir" ] && [ -w "$dir" ]; then
    tmp="$(mktemp "$dir/.atlas-claude.XXXXXX")" || { log::error "cannot create temp file in $dir"; return 1; }
    cp "$src" "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
    chmod 644 "$tmp" || { rm -f "$tmp"; log::error "cannot chmod $tmp"; return 1; }
    mv -f "$tmp" "$dest" || { rm -f "$tmp"; log::error "cannot replace $dest"; return 1; }
  else
    _claude_run_privileged mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
    tmp="$(_claude_run_privileged mktemp "$dir/.atlas-claude.XXXXXX")" || {
      log::error "cannot create privileged temp file in $dir"; return 1; }
    if ! _claude_run_privileged cp "$src" "$tmp"; then
      _claude_run_privileged rm -f "$tmp" 2>/dev/null || true
      log::error "cannot write $tmp"
      return 1
    fi
    if ! _claude_run_privileged chmod 644 "$tmp"; then
      _claude_run_privileged rm -f "$tmp" 2>/dev/null || true
      log::error "cannot chmod $tmp"
      return 1
    fi
    if ! _claude_run_privileged mv -f "$tmp" "$dest"; then
      _claude_run_privileged rm -f "$tmp" 2>/dev/null || true
      log::error "cannot replace $dest"
      return 1
    fi
  fi
  _claude_file_matches_source "$dest" "$src" || { log::error "$label write did not match Atlas source"; return 1; }
  log::info "wrote $label: $dest"
}

_claude_write_repo() {
  _claude_repo_source_valid || return 1
  _claude_write_source_file "$(_claude_repo_source)" "$(_claude_repo_file)" "Claude Code repository"
}

_claude_write_settings() {
  _claude_settings_source_valid || return 1
  _claude_write_source_file "$(_claude_settings_source)" "$(_claude_settings_file)" "Claude Code managed settings"
}

_claude_pkg_present() {
  rpm -q "$1" >/dev/null 2>&1
}

_claude_packages_installed() {
  local pkg
  for pkg in "${_CLAUDE_PACKAGES[@]}"; do
    _claude_pkg_present "$pkg" || return 1
  done
  return 0
}

_claude_path_owned_by() {
  local path="$1" prefix="$2" owner
  [ -x "$path" ] || return 1
  owner="$(rpm -qf "$path" 2>/dev/null)" || return 1
  case "$owner" in
    "$prefix"-*) return 0 ;;
    *) return 1 ;;
  esac
}

_claude_cmd_ok() {
  local out
  _claude_path_owned_by "$(_claude_bin)" claude-code || return 1
  out="$(_claude_fixed_env "$(_claude_bin)" --version 2>&1)" || return 1
  [ -n "$out" ]
}

_claude_runtime_healthy() {
  _claude_key_source_valid || return 1
  _claude_repo_matches_source || { log::error "Claude Code repository is missing or drifted: $(_claude_repo_file)"; return 1; }
  _claude_settings_matches_source || { log::error "Claude Code managed settings are missing or drifted: $(_claude_settings_file)"; return 1; }
  _claude_packages_installed || { log::error "Claude Code package set is incomplete"; return 1; }
  _claude_cmd_ok || { log::error "system Claude Code is missing, not RPM-owned by claude-code, or not runnable: $(_claude_bin)"; return 1; }
  return 0
}

_claude_system_present() {
  [ -e "$(_claude_bin)" ] && return 0
  _claude_pkg_present claude-code && return 0
  return 1
}

_claude_preflight_path() {
  local path="$1" owner="$2" label="$3"
  [ -e "$path" ] || return 0
  if [ ! -x "$path" ]; then
    log::error "$label exists but is not executable: $path"
    return 1
  fi
  if ! _claude_path_owned_by "$path" "$owner"; then
    log::error "$label exists but is not owned by Fedora package $owner: $path"
    return 1
  fi
  return 0
}

_claude_preflight() {
  _claude_preflight_path "$(_claude_bin)" claude-code "system Claude Code" || return 1
  if [ "$_CLAUDE_MARKER_STATE" = "absent" ]; then
    [ ! -e "$(_claude_repo_file)" ] || {
      log::error "Claude Code repo path already exists but is not owned by Atlas: $(_claude_repo_file)"; return 1; }
    [ ! -e "$(_claude_settings_file)" ] || {
      log::error "Claude Code managed settings path already exists but is not owned by Atlas: $(_claude_settings_file)"; return 1; }
  fi
  return 0
}

module::check() {
  _claude_marker_load || return 1
  [ "$_CLAUDE_MARKER_STATE" = "installed" ] || return 1
  _claude_runtime_healthy >/dev/null 2>&1 || return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "Claude Code module supports Fedora only"; return 1; }
  _claude_marker_load || return 1
  _claude_key_source_valid || return 1
  _claude_repo_source_valid || return 1
  _claude_settings_source_valid || return 1
  _claude_preflight || return 1
  _claude_marker_write installing || return 1
  _claude_import_key || return 1
  _claude_write_repo || return 1
  _claude_write_settings || return 1
  os::dnf_install "${_CLAUDE_PACKAGES[@]}" || return 1
  _claude_runtime_healthy || return 1
  _claude_marker_write installed || return 1
  log::info "Claude Code CLI is installed and managed by Atlas"
}

module::verify() {
  _claude_marker_load || return 1
  case "$_CLAUDE_MARKER_STATE" in
    absent)
      if _claude_system_present; then
        log::info "Claude Code is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "Claude Code is absent and development/claude is not installed by Atlas"
      fi
      return 0
      ;;
    installing)
      log::error "development/claude install is incomplete; rerun 'atlas install development/claude'"
      return 1
      ;;
  esac
  _claude_runtime_healthy || return 1
  log::info "Claude Code CLI is healthy"
}

module::update() {
  _claude_marker_load || return 1
  [ "$_CLAUDE_MARKER_STATE" = "installed" ] || {
    log::error "Claude Code is not installed by Atlas; cannot update managed state"; return 1; }
  _claude_write_repo || return 1
  _claude_write_settings || return 1
  log::info "restored Atlas-owned Claude Code repository/settings; package currency is managed by DNF"
}

module::remove() {
  _claude_marker_load || return 1
  case "$_CLAUDE_MARKER_STATE" in
    absent) log::info "Claude Code is not installed by Atlas; nothing to remove"; return 0 ;;
  esac
  _claude_repo_matches_source || { log::error "refusing to remove drifted Claude Code repo: $(_claude_repo_file)"; return 1; }
  _claude_settings_matches_source || { log::error "refusing to remove drifted Claude Code managed settings: $(_claude_settings_file)"; return 1; }
  _claude_run_privileged rm -f "$(_claude_repo_file)" || { log::error "cannot remove Claude Code repo"; return 1; }
  _claude_run_privileged rm -f "$(_claude_settings_file)" || { log::error "cannot remove Claude Code managed settings"; return 1; }
  rm -f "$(_claude_marker)" || { log::error "cannot remove Claude Code marker"; return 1; }
  log::info "removed Atlas Claude Code repo/settings/marker without uninstalling packages or touching user state"
}

module::backup() {
  log::info "nothing to back up: Claude Code installation is reconstructable; credentials, sessions, MCP, project config, and history are user-owned"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall Claude Code to reconstruct Atlas-owned package intent"
  return 0
}
