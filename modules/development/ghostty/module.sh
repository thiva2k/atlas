#!/usr/bin/env bash
# development/ghostty - RFC-0007.
#
# Atlas owns Ghostty's Fedora COPR/package intent, install marker, and the
# Ghostty config/theme files it creates. It does not own user terminal workflows,
# shell startup files, prompt config, fonts, keybindings, or user themes.
MODULE_NAME="ghostty"
MODULE_DESCRIPTION="Ghostty terminal: installs Ghostty and applies Atlas-owned developer-terminal defaults."
MODULE_DEPENDS=()

_GHOSTTY_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GHOSTTY_COPR="scottames/ghostty"
_GHOSTTY_REPO_ID="copr:copr.fedorainfracloud.org:scottames:ghostty"
_GHOSTTY_PACKAGE="ghostty"

_ghostty_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-ghostty"
}

_ghostty_config_dir() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"; }
_ghostty_config_file() { printf '%s\n' "$(_ghostty_config_dir)/config.ghostty"; }
_ghostty_theme_file() { printf '%s\n' "$(_ghostty_config_dir)/themes/atlas-reference"; }
_ghostty_config_source() { printf '%s\n' "$_GHOSTTY_MODULE_DIR/config/config.ghostty"; }
_ghostty_theme_source() { printf '%s\n' "$_GHOSTTY_MODULE_DIR/config/atlas-reference.theme"; }
_ghostty_repo_file() { printf '%s\n' "/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:scottames:ghostty.repo"; }
_ghostty_desktop_file() { printf '%s\n' "/usr/share/applications/com.mitchellh.ghostty.desktop"; }
_ghostty_binary() { printf '%s\n' "/usr/bin/ghostty"; }

_ghostty_sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

_ghostty_run_privileged() {
  if os::is_root; then "$@"; else sudo "$@"; fi
}

_ghostty_dnf_copr_available() {
  command -v dnf >/dev/null 2>&1 || return 1
  dnf copr --help >/dev/null 2>&1
}

_ghostty_marker_init() {
  _GHOSTTY_MARKER_STATE=absent
  _GHOSTTY_MARKER_SOURCE=
  _GHOSTTY_MARKER_REPO_FILE=
  _GHOSTTY_MARKER_CONFIG_PATH=
  _GHOSTTY_MARKER_THEME_PATH=
  _GHOSTTY_MARKER_CONFIG_SHA=
  _GHOSTTY_MARKER_THEME_SHA=
}

_ghostty_hash_valid() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in
    *[!0-9a-f]*|"") return 1 ;;
    *) return 0 ;;
  esac
}

_ghostty_marker_load() {
  _ghostty_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_source=0 seen_repo=0 seen_config=0 seen_theme=0 seen_config_sha=0 seen_theme_sha=0
  marker="$(_ghostty_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Ghostty marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Ghostty marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Ghostty marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Ghostty marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Ghostty marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed|detached) _GHOSTTY_MARKER_STATE="$val" ;;
          *) log::error "Ghostty marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      package_source) _GHOSTTY_MARKER_SOURCE="$val"; seen_source=1 ;;
      repo_file) _GHOSTTY_MARKER_REPO_FILE="$val"; seen_repo=1 ;;
      config_path) _GHOSTTY_MARKER_CONFIG_PATH="$val"; seen_config=1 ;;
      theme_path) _GHOSTTY_MARKER_THEME_PATH="$val"; seen_theme=1 ;;
      config_sha256) _GHOSTTY_MARKER_CONFIG_SHA="$val"; seen_config_sha=1 ;;
      theme_sha256) _GHOSTTY_MARKER_THEME_SHA="$val"; seen_theme_sha=1 ;;
      *) log::error "Ghostty marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Ghostty marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Ghostty marker is missing state"; return 1; }
  [ "$seen_source" -eq 1 ] || { log::error "Ghostty marker is missing package_source"; return 1; }
  [ "$seen_repo" -eq 1 ] || { log::error "Ghostty marker is missing repo_file"; return 1; }
  [ "$seen_config" -eq 1 ] || { log::error "Ghostty marker is missing config_path"; return 1; }
  [ "$seen_theme" -eq 1 ] || { log::error "Ghostty marker is missing theme_path"; return 1; }
  [ "$seen_config_sha" -eq 1 ] || { log::error "Ghostty marker is missing config_sha256"; return 1; }
  [ "$seen_theme_sha" -eq 1 ] || { log::error "Ghostty marker is missing theme_sha256"; return 1; }
  [ "$_GHOSTTY_MARKER_SOURCE" = "copr:$_GHOSTTY_COPR" ] || {
    log::error "Ghostty marker package_source is unsupported: $_GHOSTTY_MARKER_SOURCE"; return 1; }
  [ "$_GHOSTTY_MARKER_REPO_FILE" = "$(_ghostty_repo_file)" ] || {
    log::error "Ghostty marker repo_file does not match this module"; return 1; }
  [ "$_GHOSTTY_MARKER_CONFIG_PATH" = "$(_ghostty_config_file)" ] || {
    log::error "Ghostty marker config_path does not match this environment"; return 1; }
  [ "$_GHOSTTY_MARKER_THEME_PATH" = "$(_ghostty_theme_file)" ] || {
    log::error "Ghostty marker theme_path does not match this environment"; return 1; }
  _ghostty_hash_valid "$_GHOSTTY_MARKER_CONFIG_SHA" || {
    log::error "Ghostty marker config_sha256 is invalid"; return 1; }
  _ghostty_hash_valid "$_GHOSTTY_MARKER_THEME_SHA" || {
    log::error "Ghostty marker theme_sha256 is invalid"; return 1; }
  return 0
}

_ghostty_marker_write() {
  local state="$1" marker dir tmp config_sha theme_sha
  marker="$(_ghostty_marker)"
  dir="$(dirname "$marker")"
  config_sha="$(_ghostty_sha256 "$(_ghostty_config_source)")"
  theme_sha="$(_ghostty_sha256 "$(_ghostty_theme_source)")"
  [ -n "$config_sha" ] || { log::error "cannot hash Ghostty config source"; return 1; }
  [ -n "$theme_sha" ] || { log::error "cannot hash Ghostty theme source"; return 1; }
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-ghostty.XXXXXX")" || {
    log::error "cannot create a Ghostty marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'package_source=copr:%s\n' "$_GHOSTTY_COPR"
    printf 'repo_file=%s\n' "$(_ghostty_repo_file)"
    printf 'config_path=%s\n' "$(_ghostty_config_file)"
    printf 'theme_path=%s\n' "$(_ghostty_theme_file)"
    printf 'config_sha256=%s\n' "$config_sha"
    printf 'theme_sha256=%s\n' "$theme_sha"
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_ghostty_repo_ok() {
  local repo="$(_ghostty_repo_file)"
  [ -f "$repo" ] || return 1
  grep -qxF "[$_GHOSTTY_REPO_ID]" "$repo" || { log::error "Ghostty COPR repo id is missing or changed"; return 1; }
  grep -qxF "enabled=1" "$repo" || { log::error "Ghostty COPR repo is not enabled"; return 1; }
  grep -qxF "gpgcheck=1" "$repo" || { log::error "Ghostty COPR repo must keep gpgcheck=1"; return 1; }
  grep -q '^baseurl=' "$repo" || { log::error "Ghostty COPR repo is missing baseurl"; return 1; }
}

_ghostty_write_repo() {
  if _ghostty_repo_ok >/dev/null 2>&1; then
    log::info "Ghostty COPR repository already enabled"
    return 0
  fi
  if ! _ghostty_dnf_copr_available; then
    os::dnf_install dnf-plugins-core || { log::error "cannot install dnf COPR support"; return 1; }
  fi
  _ghostty_run_privileged dnf -y copr enable "$_GHOSTTY_COPR" || {
    log::error "cannot enable Ghostty COPR repository"; return 1; }
  _ghostty_repo_ok || return 1
  log::info "enabled Ghostty COPR repository: $_GHOSTTY_COPR"
}

_ghostty_path_matches_source() {
  local dest="$1" src="$2"
  [ -f "$dest" ] || return 1
  [ "$(_ghostty_sha256 "$dest")" = "$(_ghostty_sha256 "$src")" ]
}

_ghostty_atomic_copy() {
  local src="$1" dest="$2" mode="$3" dir tmp
  [ -r "$src" ] || { log::error "Ghostty source file missing: $src"; return 1; }
  if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
    log::error "Ghostty managed path is not a regular file: $dest"
    return 1
  fi
  dir="$(dirname "$dest")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  tmp="$(mktemp "$dir/.atlas-ghostty.XXXXXX")" || {
    log::error "cannot create a Ghostty temp file in $dir"; return 1; }
  cp "$src" "$tmp" || { rm -f "$tmp"; log::error "cannot stage $dest"; return 1; }
  chmod "$mode" "$tmp" || { rm -f "$tmp"; log::error "cannot chmod $tmp"; return 1; }
  mv -f "$tmp" "$dest" || { rm -f "$tmp"; log::error "cannot replace $dest"; return 1; }
}

_ghostty_write_managed_config() {
  _ghostty_atomic_copy "$(_ghostty_config_source)" "$(_ghostty_config_file)" 644 || return 1
  _ghostty_atomic_copy "$(_ghostty_theme_source)" "$(_ghostty_theme_file)" 644 || return 1
  log::info "wrote Atlas-managed Ghostty config"
}

_ghostty_managed_config_ok() {
  local config="$(_ghostty_config_file)" theme="$(_ghostty_theme_file)"
  [ -f "$config" ] || { log::error "Ghostty managed config is missing: $config"; return 1; }
  [ -f "$theme" ] || { log::error "Ghostty managed theme is missing: $theme"; return 1; }
  [ ! -L "$config" ] || { log::error "Ghostty managed config is a symlink: $config"; return 1; }
  [ ! -L "$theme" ] || { log::error "Ghostty managed theme is a symlink: $theme"; return 1; }
  _ghostty_path_matches_source "$config" "$(_ghostty_config_source)" || {
    log::error "Ghostty managed config has drifted: $config"; return 1; }
  _ghostty_path_matches_source "$theme" "$(_ghostty_theme_source)" || {
    log::error "Ghostty managed theme has drifted: $theme"; return 1; }
}

_ghostty_binary_ok() {
  local bin="$(_ghostty_binary)" owner
  [ -x "$bin" ] || { log::error "Ghostty binary is missing or not executable: $bin"; return 1; }
  if owner="$(rpm -qf "$bin" 2>/dev/null)"; then
    case "$owner" in
      ghostty-*) ;;
      *) log::error "Ghostty binary is not owned by the ghostty RPM: $bin"; return 1 ;;
    esac
  fi
  "$bin" --version >/dev/null 2>&1 || { log::error "Ghostty binary is not runnable"; return 1; }
}

_ghostty_desktop_ok() {
  local desktop="$(_ghostty_desktop_file)"
  [ -f "$desktop" ] || { log::error "Ghostty desktop launcher is missing: $desktop"; return 1; }
  [ ! -L "$desktop" ] || { log::error "Ghostty desktop launcher is a symlink: $desktop"; return 1; }
  grep -q '^Exec=.*ghostty' "$desktop" || {
    log::error "Ghostty desktop launcher does not execute ghostty"; return 1; }
}

_ghostty_unmanaged_present() {
  os::has_cmd ghostty && return 0
  [ -e "$(_ghostty_binary)" ] && return 0
  [ -e "$(_ghostty_desktop_file)" ] && return 0
  return 1
}

_ghostty_preflight_unmanaged() {
  if [ -e "$(_ghostty_config_file)" ] || [ -L "$(_ghostty_config_file)" ]; then
    log::error "Ghostty config.ghostty already exists and is not Atlas-owned: $(_ghostty_config_file)"
    log::error "  fix: move it to user.ghostty or remove it before Atlas manages Ghostty"
    return 1
  fi
  if _ghostty_unmanaged_present; then
    log::error "Ghostty already exists but is not installed by Atlas"
    log::error "  fix: remove or migrate the existing Ghostty installation before Atlas claims ownership"
    return 1
  fi
  if [ -e "$(_ghostty_repo_file)" ]; then
    log::error "Ghostty COPR repo file already exists and is not Atlas-owned: $(_ghostty_repo_file)"
    log::error "  fix: remove or migrate the existing COPR repo before Atlas claims ownership"
    return 1
  fi
  return 0
}

_ghostty_preflight_detached() {
  if [ -e "$(_ghostty_config_file)" ] || [ -L "$(_ghostty_config_file)" ]; then
    log::error "Ghostty config.ghostty exists while development/ghostty is detached: $(_ghostty_config_file)"
    log::error "  fix: move it to user.ghostty or remove it before re-enrolling Ghostty"
    return 1
  fi
  if [ -e "$(_ghostty_theme_file)" ] || [ -L "$(_ghostty_theme_file)" ]; then
    log::error "Ghostty atlas-reference theme exists while development/ghostty is detached: $(_ghostty_theme_file)"
    log::error "  fix: move or remove it before re-enrolling Ghostty"
    return 1
  fi
  return 0
}

_ghostty_verify_managed() {
  _ghostty_marker_load || return 1
  case "$_GHOSTTY_MARKER_STATE" in
    absent)
      if _ghostty_unmanaged_present; then
        log::info "Ghostty is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "Ghostty is absent and development/ghostty is not installed by Atlas"
      fi
      return 0
      ;;
    detached)
      log::warn "development/ghostty is detached; Atlas is not asserting Ghostty health"
      return 0
      ;;
    installing)
      log::error "development/ghostty install is incomplete; rerun 'atlas install development/ghostty'"
      return 1
      ;;
  esac
  _ghostty_repo_ok || return 1
  _ghostty_binary_ok || return 1
  _ghostty_desktop_ok || return 1
  _ghostty_managed_config_ok || return 1
  log::info "Ghostty is healthy"
}

module::check() {
  _ghostty_marker_load || return 1
  [ "$_GHOSTTY_MARKER_STATE" = "installed" ] || return 1
  _ghostty_repo_ok >/dev/null 2>&1 || return 1
  _ghostty_binary_ok >/dev/null 2>&1 || return 1
  _ghostty_desktop_ok >/dev/null 2>&1 || return 1
  _ghostty_managed_config_ok >/dev/null 2>&1 || return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "Ghostty module supports Fedora only"; return 1; }
  _ghostty_marker_load || return 1
  case "$_GHOSTTY_MARKER_STATE" in
    absent) _ghostty_preflight_unmanaged || return 1 ;;
    detached) _ghostty_preflight_detached || return 1 ;;
    installing|installed) ;;
  esac
  _ghostty_marker_write installing || return 1
  _ghostty_write_repo || return 1
  os::dnf_install "$_GHOSTTY_PACKAGE" || { log::error "failed to install Ghostty"; return 1; }
  _ghostty_write_managed_config || return 1
  _ghostty_repo_ok || return 1
  _ghostty_binary_ok || return 1
  _ghostty_desktop_ok || return 1
  _ghostty_managed_config_ok || return 1
  _ghostty_marker_write installed || return 1
  log::info "Ghostty is installed and managed by Atlas"
}

module::verify() {
  _ghostty_verify_managed
}

module::update() {
  _ghostty_marker_load || return 1
  case "$_GHOSTTY_MARKER_STATE" in
    absent|detached)
      log::info "Ghostty is not actively managed by Atlas; nothing to update"
      return 0
      ;;
    installing|installed) ;;
  esac
  _ghostty_write_managed_config || return 1
  _ghostty_marker_write installed || return 1
  _ghostty_verify_managed || return 1
}

module::remove() {
  _ghostty_marker_load || return 1
  case "$_GHOSTTY_MARKER_STATE" in
    absent)
      log::info "Ghostty is not installed by Atlas; nothing to detach"
      return 0
      ;;
    detached)
      log::info "Ghostty is already detached from Atlas"
      return 0
      ;;
  esac
  _ghostty_managed_config_ok || {
    log::error "refusing to remove drifted Ghostty managed files"; return 1; }
  rm -f "$(_ghostty_config_file)" || { log::error "cannot delete $(_ghostty_config_file)"; return 1; }
  rm -f "$(_ghostty_theme_file)" || { log::error "cannot delete $(_ghostty_theme_file)"; return 1; }
  rmdir "$(dirname "$(_ghostty_theme_file)")" 2>/dev/null || true
  rmdir "$(_ghostty_config_dir)" 2>/dev/null || true
  _ghostty_marker_write detached || return 1
  log::info "detached Ghostty from Atlas without uninstalling packages or touching user config"
}

module::backup() {
  log::info "nothing to back up: Atlas-owned Ghostty state is reconstructable; user terminal config is user-owned"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall Ghostty to reconstruct Atlas-owned state"
  return 0
}
