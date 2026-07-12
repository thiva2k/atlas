#!/usr/bin/env bash
# desktop/fonts - RFC-0008.
#
# Atlas owns only its recorded typography intent and the Nerd Font files it
# installs under its own user font directory. It never writes user font
# preferences or touches user font collections.
MODULE_NAME="fonts"
MODULE_DESCRIPTION="Typography foundation: installs JetBrains Mono Nerd Font and Inter."
MODULE_DEPENDS=()

_FONTS_PACKAGES=(fontconfig curl xz rsms-inter-fonts)
_FONTS_INTER_PACKAGE="rsms-inter-fonts"
_FONTS_NERD_VERSION="v3.4.0"
_FONTS_NERD_ARCHIVE="JetBrainsMono.tar.xz"
_FONTS_NERD_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/$_FONTS_NERD_VERSION/$_FONTS_NERD_ARCHIVE"
_FONTS_NERD_SHA_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/$_FONTS_NERD_VERSION/SHA-256.txt"

_fonts_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-fonts"
}

_fonts_font_dir() {
  printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/fonts/atlas/JetBrainsMonoNerdFont"
}

_fonts_font_dir_safe() {
  local dir="$(_fonts_font_dir)"
  case "$dir" in
    "$HOME"/*) return 0 ;;
    *)
      log::error "Atlas font directory must live under HOME: $dir"
      log::error "  fix: set XDG_DATA_HOME under $HOME or unset it before running desktop/fonts"
      return 1
      ;;
  esac
}

_fonts_marker_init() {
  _FONTS_MARKER_STATE=absent
  _FONTS_MARKER_INTER_PACKAGE=
  _FONTS_MARKER_NERD_VERSION=
  _FONTS_MARKER_NERD_ARCHIVE=
  _FONTS_MARKER_NERD_URL=
  _FONTS_MARKER_NERD_DIR=
}

_fonts_marker_load() {
  _fonts_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_inter=0 seen_version=0 seen_archive=0 seen_url=0 seen_dir=0
  marker="$(_fonts_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Fonts marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Fonts marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Fonts marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Fonts marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Fonts marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed|detached) _FONTS_MARKER_STATE="$val" ;;
          *) log::error "Fonts marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      inter_package) _FONTS_MARKER_INTER_PACKAGE="$val"; seen_inter=1 ;;
      nerd_font_version) _FONTS_MARKER_NERD_VERSION="$val"; seen_version=1 ;;
      nerd_font_archive) _FONTS_MARKER_NERD_ARCHIVE="$val"; seen_archive=1 ;;
      nerd_font_url) _FONTS_MARKER_NERD_URL="$val"; seen_url=1 ;;
      nerd_font_dir) _FONTS_MARKER_NERD_DIR="$val"; seen_dir=1 ;;
      *) log::error "Fonts marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Fonts marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Fonts marker is missing state"; return 1; }
  [ "$seen_inter" -eq 1 ] || { log::error "Fonts marker is missing inter_package"; return 1; }
  [ "$seen_version" -eq 1 ] || { log::error "Fonts marker is missing nerd_font_version"; return 1; }
  [ "$seen_archive" -eq 1 ] || { log::error "Fonts marker is missing nerd_font_archive"; return 1; }
  [ "$seen_url" -eq 1 ] || { log::error "Fonts marker is missing nerd_font_url"; return 1; }
  [ "$seen_dir" -eq 1 ] || { log::error "Fonts marker is missing nerd_font_dir"; return 1; }
  [ "$_FONTS_MARKER_INTER_PACKAGE" = "$_FONTS_INTER_PACKAGE" ] || {
    log::error "Fonts marker inter_package is unsupported: $_FONTS_MARKER_INTER_PACKAGE"; return 1; }
  [ "$_FONTS_MARKER_NERD_VERSION" = "$_FONTS_NERD_VERSION" ] || {
    log::error "Fonts marker Nerd Font version is unsupported: $_FONTS_MARKER_NERD_VERSION"; return 1; }
  [ "$_FONTS_MARKER_NERD_ARCHIVE" = "$_FONTS_NERD_ARCHIVE" ] || {
    log::error "Fonts marker Nerd Font archive is unsupported: $_FONTS_MARKER_NERD_ARCHIVE"; return 1; }
  [ "$_FONTS_MARKER_NERD_URL" = "$_FONTS_NERD_URL" ] || {
    log::error "Fonts marker Nerd Font URL does not match this module"; return 1; }
  _fonts_font_dir_safe || return 1
  [ "$_FONTS_MARKER_NERD_DIR" = "$(_fonts_font_dir)" ] || {
    log::error "Fonts marker Nerd Font directory does not match this environment"; return 1; }
  return 0
}

_fonts_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_fonts_marker)"
  dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.desktop-fonts.XXXXXX")" || {
    log::error "cannot create a Fonts marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'inter_package=%s\n' "$_FONTS_INTER_PACKAGE"
    printf 'nerd_font_version=%s\n' "$_FONTS_NERD_VERSION"
    printf 'nerd_font_archive=%s\n' "$_FONTS_NERD_ARCHIVE"
    printf 'nerd_font_url=%s\n' "$_FONTS_NERD_URL"
    printf 'nerd_font_dir=%s\n' "$(_fonts_font_dir)"
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_fonts_fc_cache() {
  fc-cache -f "$(_fonts_font_dir)"
}

_fonts_fetch_nerd_archive() {
  local archive="$1" checksums="$2"
  curl -fsSL "$_FONTS_NERD_URL" -o "$archive" || return 1
  curl -fsSL "$_FONTS_NERD_SHA_URL" -o "$checksums" || return 1
}

_fonts_verify_nerd_archive() {
  local archive="$1" checksums="$2" expected actual
  expected="$(awk -v name="$_FONTS_NERD_ARCHIVE" '$2 == name || $2 == "./" name { print $1; exit }' "$checksums" 2>/dev/null)" || return 1
  [ -n "$expected" ] || return 1
  actual="$(sha256sum "$archive" 2>/dev/null | awk '{print $1}')" || return 1
  [ "$actual" = "$expected" ]
}

_fonts_extract_nerd_archive() {
  local archive="$1" dest parent stage extract file count=0
  dest="$(_fonts_font_dir)"
  parent="$(dirname "$dest")"
  _fonts_font_dir_safe || return 1
  mkdir -p "$parent" || { log::error "cannot create $parent"; return 1; }
  stage="$(mktemp -d "$parent/.JetBrainsMonoNerdFont.XXXXXX")" || {
    log::error "cannot create a font staging directory in $parent"; return 1; }
  extract="$stage/source"
  mkdir -p "$extract" "$stage/install" || { rm -rf "$stage"; log::error "cannot create font install staging"; return 1; }
  if ! tar -xJf "$archive" -C "$extract"; then
    rm -rf "$stage"
    log::error "cannot extract $_FONTS_NERD_ARCHIVE"
    return 1
  fi
  while IFS= read -r file; do
    cp "$file" "$stage/install/" || { rm -rf "$stage"; log::error "cannot stage font file: $file"; return 1; }
    count=$((count + 1))
  done < <(find "$extract" -type f \( -name '*.ttf' -o -name '*.otf' \) -print)
  [ "$count" -gt 0 ] || { rm -rf "$stage"; log::error "Nerd Font archive contained no font files"; return 1; }
  chmod 644 "$stage"/install/* || { rm -rf "$stage"; log::error "cannot set font file modes"; return 1; }
  rm -rf "$dest" || { rm -rf "$stage"; log::error "cannot replace $dest"; return 1; }
  mv "$stage/install" "$dest" || { rm -rf "$stage"; log::error "cannot install Nerd Font files"; return 1; }
  rm -rf "$stage"
}

_fonts_nerd_files_present() {
  local dir="$(_fonts_font_dir)"
  [ -d "$dir" ] || return 1
  find "$dir" -type f \( -name '*.ttf' -o -name '*.otf' \) -print -quit | grep -q .
}

_fonts_fc_list_ok() {
  fc-list >/dev/null 2>&1
}

_fonts_match_family() {
  local family="$1" expected="$2" out
  out="$(fc-match "$family" 2>/dev/null)" || return 1
  case "$out" in
    *"$expected"*) return 0 ;;
    *) return 1 ;;
  esac
}

_fonts_nerd_font_ok() {
  _fonts_nerd_files_present || return 1
  _fonts_match_family "JetBrainsMono Nerd Font" "JetBrainsMono Nerd Font"
}

_fonts_inter_ok() {
  _fonts_match_family Inter Inter
}

_fonts_managed_healthy() {
  _fonts_fc_list_ok || { log::error "fontconfig cannot list fonts"; return 1; }
  _fonts_nerd_font_ok || { log::error "JetBrainsMono Nerd Font is not available through fontconfig"; return 1; }
  _fonts_inter_ok || { log::error "Inter is not available through fontconfig"; return 1; }
  return 0
}

_fonts_matching_present() {
  _fonts_match_family "JetBrainsMono Nerd Font" "JetBrainsMono Nerd Font" || return 1
  _fonts_match_family Inter Inter || return 1
  return 0
}

_fonts_preflight_absent() {
  _fonts_font_dir_safe || return 1
  if [ -e "$(_fonts_font_dir)" ] || [ -L "$(_fonts_font_dir)" ]; then
    log::error "Atlas font directory already exists but is not Atlas-owned: $(_fonts_font_dir)"
    log::error "  fix: move or remove it before Atlas manages desktop/fonts"
    return 1
  fi
  return 0
}

_fonts_preflight_detached() {
  _fonts_font_dir_safe || return 1
  if [ -e "$(_fonts_font_dir)" ] || [ -L "$(_fonts_font_dir)" ]; then
    log::error "Atlas font directory exists while desktop/fonts is detached: $(_fonts_font_dir)"
    log::error "  fix: move or remove it before re-enrolling desktop/fonts"
    return 1
  fi
  return 0
}

_fonts_install_nerd_font() {
  if _fonts_nerd_font_ok >/dev/null 2>&1; then
    log::info "JetBrainsMono Nerd Font already installed by Atlas"
    return 0
  fi
  local tmp archive checksums
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/atlas-fonts.XXXXXX")" || {
    log::error "cannot create temporary font download directory"; return 1; }
  archive="$tmp/$_FONTS_NERD_ARCHIVE"
  checksums="$tmp/SHA-256.txt"
  if ! _fonts_fetch_nerd_archive "$archive" "$checksums"; then
    rm -rf "$tmp"
    log::error "cannot download JetBrains Mono Nerd Font"
    return 1
  fi
  if ! _fonts_verify_nerd_archive "$archive" "$checksums"; then
    rm -rf "$tmp"
    log::error "JetBrains Mono Nerd Font checksum verification failed"
    return 1
  fi
  if ! _fonts_extract_nerd_archive "$archive"; then
    rm -rf "$tmp"
    return 1
  fi
  rm -rf "$tmp"
}

module::check() {
  _fonts_marker_load || return 1
  [ "$_FONTS_MARKER_STATE" = "installed" ] || return 1
  _fonts_managed_healthy >/dev/null 2>&1 || return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "desktop/fonts supports Fedora only"; return 1; }
  _fonts_font_dir_safe || return 1
  _fonts_marker_load || return 1
  case "$_FONTS_MARKER_STATE" in
    absent) _fonts_preflight_absent || return 1 ;;
    detached) _fonts_preflight_detached || return 1 ;;
    installing|installed) ;;
  esac
  _fonts_marker_write installing || return 1
  os::dnf_install "${_FONTS_PACKAGES[@]}" || return 1
  _fonts_install_nerd_font || return 1
  _fonts_fc_cache "$(_fonts_font_dir)" || { log::error "cannot refresh font cache"; return 1; }
  _fonts_managed_healthy || return 1
  _fonts_marker_write installed || return 1
  log::info "Atlas typography foundation is installed"
}

module::verify() {
  _fonts_marker_load || return 1
  case "$_FONTS_MARKER_STATE" in
    absent)
      if _fonts_matching_present; then
        log::info "required fonts are present but desktop/fonts is not installed by Atlas; treating them as user-owned"
      else
        log::info "desktop/fonts is not installed by Atlas"
      fi
      return 0
      ;;
    detached)
      log::warn "desktop/fonts is detached; Atlas is not asserting typography health"
      return 0
      ;;
    installing)
      log::error "desktop/fonts install is incomplete; rerun 'atlas install desktop/fonts'"
      return 1
      ;;
  esac
  _fonts_managed_healthy || return 1
  log::info "Atlas typography foundation is healthy"
}

module::update() {
  _fonts_marker_load || return 1
  case "$_FONTS_MARKER_STATE" in
    absent|detached)
      log::info "desktop/fonts is not actively managed by Atlas; nothing to update"
      return 0
      ;;
    installing|installed) ;;
  esac
  _fonts_install_nerd_font || return 1
  _fonts_fc_cache "$(_fonts_font_dir)" || { log::error "cannot refresh font cache"; return 1; }
  _fonts_managed_healthy || return 1
  _fonts_marker_write installed || return 1
}

module::remove() {
  _fonts_font_dir_safe || return 1
  _fonts_marker_load || return 1
  case "$_FONTS_MARKER_STATE" in
    absent)
      log::info "desktop/fonts is not installed by Atlas; nothing to detach"
      return 0
      ;;
    detached)
      log::info "desktop/fonts is already detached from Atlas"
      return 0
      ;;
  esac
  rm -rf "$(_fonts_font_dir)" || { log::error "cannot delete $(_fonts_font_dir)"; return 1; }
  rmdir "$(dirname "$(_fonts_font_dir)")" 2>/dev/null || true
  _fonts_fc_cache "$(dirname "$(_fonts_font_dir)")" || true
  _fonts_marker_write detached || return 1
  log::info "detached desktop/fonts without uninstalling packages or touching user font preferences"
}

module::backup() {
  log::info "nothing to back up: Atlas-owned fonts are reconstructable; user fonts and preferences are user-owned"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall desktop/fonts to reconstruct Atlas-owned typography"
  return 0
}
