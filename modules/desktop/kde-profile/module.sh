#!/usr/bin/env bash
# desktop/kde-profile - RFC-0012.
#
# Atlas owns only the KConfig keys listed in profile.tsv after it creates them.
# It does not adopt existing user KDE settings or own whole KDE config files.
MODULE_NAME="kde-profile"
MODULE_DESCRIPTION="KDE workstation profile: applies Atlas-owned responsive desktop defaults."
MODULE_DEPENDS=()

_KDE_PROFILE_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_KDE_PROFILE_ABSENT="__ATLAS_KDE_PROFILE_ABSENT__"

_kde_profile_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-kde-profile"
}

_kde_profile_source() { printf '%s\n' "$_KDE_PROFILE_MODULE_DIR/profile.tsv"; }
_kde_profile_sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

_kde_profile_has_tools() {
  os::has_cmd kreadconfig6 && os::has_cmd kwriteconfig6
}

_kde_profile_marker_init() {
  _KDE_PROFILE_MARKER_STATE=absent
  _KDE_PROFILE_MARKER_PROFILE_SHA=
}

_kde_profile_hash_valid() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in *[!0-9a-f]*|"") return 1 ;; *) return 0 ;; esac
}

_kde_profile_marker_load() {
  _kde_profile_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_sha=0
  marker="$(_kde_profile_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "KDE profile marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect KDE profile marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "KDE profile marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "KDE profile marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "KDE profile marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed|detached) _KDE_PROFILE_MARKER_STATE="$val" ;;
          *) log::error "KDE profile marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      profile_sha256) _KDE_PROFILE_MARKER_PROFILE_SHA="$val"; seen_sha=1 ;;
      *) log::error "KDE profile marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "KDE profile marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "KDE profile marker is missing state"; return 1; }
  [ "$seen_sha" -eq 1 ] || { log::error "KDE profile marker is missing profile_sha256"; return 1; }
  _kde_profile_hash_valid "$_KDE_PROFILE_MARKER_PROFILE_SHA" || {
    log::error "KDE profile marker profile_sha256 is invalid"; return 1; }
}

_kde_profile_marker_write() {
  local state="$1" marker dir tmp profile_sha
  marker="$(_kde_profile_marker)"
  dir="$(dirname "$marker")"
  profile_sha="$(_kde_profile_sha256 "$(_kde_profile_source)")"
  [ -n "$profile_sha" ] || { log::error "cannot hash KDE profile source"; return 1; }
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.desktop-kde-profile.XXXXXX")" || {
    log::error "cannot create a KDE profile marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'profile_sha256=%s\n' "$profile_sha"
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_kde_profile_for_each() {
  local callback="$1" file group key type value extra
  [ -r "$(_kde_profile_source)" ] || { log::error "KDE profile source missing"; return 1; }
  while IFS='|' read -r file group key type value extra || [ -n "${file:-}${group:-}${key:-}${type:-}${value:-}${extra:-}" ]; do
    case "${file:-}" in ""|\#*) continue ;; esac
    if [ -n "${extra:-}" ] || [ -z "${group:-}" ] || [ -z "${key:-}" ] || [ -z "${type:-}" ] || [ -z "${value:-}" ]; then
      log::error "invalid KDE profile row for $file"
      return 1
    fi
    case "$type" in bool|string) ;; *) log::error "invalid KDE profile type for $file/$group/$key: $type"; return 1 ;; esac
    "$callback" "$file" "$group" "$key" "$type" "$value" || return 1
  done < "$(_kde_profile_source)"
}

_kde_profile_read_value() {
  local file="$1" group="$2" key="$3" type="$4" default="$5"
  if [ "$type" = "bool" ]; then
    kreadconfig6 --file "$file" --group "$group" --key "$key" --default "$default" --type bool
  else
    kreadconfig6 --file "$file" --group "$group" --key "$key" --default "$default"
  fi
}

_kde_profile_write_value() {
  local file="$1" group="$2" key="$3" type="$4" value="$5"
  if [ "$type" = "bool" ]; then
    kwriteconfig6 --file "$file" --group "$group" --key "$key" --type bool "$value"
  else
    kwriteconfig6 --file "$file" --group "$group" --key "$key" "$value"
  fi
}

_kde_profile_delete_value() {
  local file="$1" group="$2" key="$3" type="$4"
  if [ "$type" = "bool" ]; then
    kwriteconfig6 --file "$file" --group "$group" --key "$key" --type bool --delete ""
  else
    kwriteconfig6 --file "$file" --group "$group" --key "$key" --delete ""
  fi
}

_kde_profile_assert_absent_setting() {
  local file="$1" group="$2" key="$3" type="$4" value="$5" current
  current="$(_kde_profile_read_value "$file" "$group" "$key" "$type" "$_KDE_PROFILE_ABSENT")" || {
    log::error "cannot read KDE profile key: $file/$group/$key"; return 1; }
  if [ "$current" != "$_KDE_PROFILE_ABSENT" ]; then
    log::error "KDE profile key already exists and is user-owned: $file/$group/$key"
    log::error "  fix: remove that key before Atlas manages desktop/kde-profile"
    return 1
  fi
}

_kde_profile_apply_setting() {
  local file="$1" group="$2" key="$3" type="$4" value="$5" current
  current="$(_kde_profile_read_value "$file" "$group" "$key" "$type" "$_KDE_PROFILE_ABSENT")" || {
    log::error "cannot read KDE profile key: $file/$group/$key"; return 1; }
  [ "$current" = "$value" ] && return 0
  _kde_profile_write_value "$file" "$group" "$key" "$type" "$value" || {
    log::error "cannot write KDE profile key: $file/$group/$key"; return 1; }
}

_kde_profile_verify_setting() {
  local file="$1" group="$2" key="$3" type="$4" value="$5" current
  current="$(_kde_profile_read_value "$file" "$group" "$key" "$type" "$_KDE_PROFILE_ABSENT")" || {
    log::error "cannot read KDE profile key: $file/$group/$key"; return 1; }
  [ "$current" = "$value" ] || {
    log::error "KDE profile key is missing or drifted: $file/$group/$key"; return 1; }
}

_kde_profile_delete_setting() {
  local file="$1" group="$2" key="$3" type="$4" value="$5"
  _kde_profile_delete_value "$file" "$group" "$key" "$type" || {
    log::error "cannot delete KDE profile key: $file/$group/$key"; return 1; }
}

_kde_profile_assert_absent_all() { _kde_profile_for_each _kde_profile_assert_absent_setting; }
_kde_profile_apply_all() { _kde_profile_for_each _kde_profile_apply_setting; }
_kde_profile_verify_all() { _kde_profile_for_each _kde_profile_verify_setting; }
_kde_profile_delete_all() { _kde_profile_for_each _kde_profile_delete_setting; }

module::check() {
  _kde_profile_marker_load || return 1
  [ "$_KDE_PROFILE_MARKER_STATE" = "installed" ] || return 1
  _kde_profile_has_tools || return 1
  _kde_profile_verify_all
}

module::install() {
  os::is_fedora || { log::error "desktop/kde-profile supports Fedora only"; return 1; }
  _kde_profile_has_tools || { log::error "kreadconfig6 and kwriteconfig6 are required"; return 1; }
  _kde_profile_marker_load || return 1
  case "$_KDE_PROFILE_MARKER_STATE" in
    absent|detached) _kde_profile_assert_absent_all || return 1 ;;
    installing|installed) ;;
  esac
  _kde_profile_marker_write installing || return 1
  _kde_profile_apply_all || return 1
  _kde_profile_verify_all || return 1
  _kde_profile_marker_write installed || return 1
  log::info "KDE workstation profile is installed"
}

module::verify() {
  _kde_profile_marker_load || return 1
  case "$_KDE_PROFILE_MARKER_STATE" in
    absent)
      log::info "desktop/kde-profile is not installed by Atlas"
      return 0
      ;;
    detached)
      log::warn "desktop/kde-profile is detached; Atlas is not asserting KDE settings"
      return 0
      ;;
    installing)
      log::error "desktop/kde-profile install is incomplete; rerun 'atlas install desktop/kde-profile'"
      return 1
      ;;
  esac
  _kde_profile_has_tools || { log::error "kreadconfig6 and kwriteconfig6 are required"; return 1; }
  _kde_profile_verify_all || return 1
  log::info "KDE workstation profile is healthy"
}

module::update() {
  _kde_profile_marker_load || return 1
  case "$_KDE_PROFILE_MARKER_STATE" in
    absent|detached)
      log::info "desktop/kde-profile is not actively managed by Atlas; nothing to update"
      return 0
      ;;
    installing|installed) ;;
  esac
  _kde_profile_has_tools || { log::error "kreadconfig6 and kwriteconfig6 are required"; return 1; }
  _kde_profile_apply_all || return 1
  _kde_profile_verify_all || return 1
  _kde_profile_marker_write installed || return 1
}

module::remove() {
  _kde_profile_marker_load || return 1
  case "$_KDE_PROFILE_MARKER_STATE" in
    absent)
      log::info "desktop/kde-profile is not installed by Atlas; nothing to detach"
      return 0
      ;;
    detached)
      log::info "desktop/kde-profile is already detached from Atlas"
      return 0
      ;;
  esac
  _kde_profile_has_tools || { log::error "kreadconfig6 and kwriteconfig6 are required"; return 1; }
  _kde_profile_verify_all || { log::error "refusing to remove drifted KDE profile"; return 1; }
  _kde_profile_delete_all || return 1
  _kde_profile_marker_write detached || return 1
  log::info "detached desktop/kde-profile without touching user-owned KDE settings"
}

module::backup() {
  log::info "nothing to back up: desktop/kde-profile is reconstructable from Atlas"
}

module::restore() {
  log::info "nothing to restore: reinstall desktop/kde-profile to reconstruct Atlas-owned KDE settings"
}
