#!/usr/bin/env bash
# desktop/wallpapers - RFC-0021.
MODULE_NAME="wallpapers"
MODULE_DESCRIPTION="Wallpapers: installs a curated Atlas wallpaper collection without changing user selection."
MODULE_DEPENDS=()

_WALLPAPERS_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_wallpapers_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-wallpapers"; }
_wallpapers_source_dir() { printf '%s\n' "$_WALLPAPERS_MODULE_DIR/assets"; }
_wallpapers_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/atlas"; }
_wallpapers_manifest() { (cd "$(_wallpapers_source_dir)" && find . -type f -name '*.svg' -print | sort | xargs sha256sum) 2>/dev/null; }
_wallpapers_current_manifest() { (cd "$(_wallpapers_dir)" && find . -type f -name '*.svg' -print | sort | xargs sha256sum) 2>/dev/null; }
_wallpapers_marker_init() { _WALLPAPERS_MARKER_STATE=absent; }
_wallpapers_marker_load() {
  _wallpapers_marker_init
  local marker="$(_wallpapers_marker)" line val seen_schema=0 seen_state=0
  [ -e "$marker" ] || return 0
  [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || return 1
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue
    case "$line" in schema=1) seen_schema=1 ;; state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _WALLPAPERS_MARKER_STATE="$val" ;; *) return 1 ;; esac; seen_state=1 ;; *) ;; esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] && [ "$seen_state" -eq 1 ]
}
_wallpapers_marker_write() {
  local state="$1" marker dir tmp
  marker="$(_wallpapers_marker)"; dir="$(dirname "$marker")"; mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-wallpapers.XXXXXX")" || return 1
  { printf 'schema=1\nstate=%s\n' "$state"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }
}
_wallpapers_match() { [ -d "$(_wallpapers_dir)" ] && [ "$(_wallpapers_manifest)" = "$(_wallpapers_current_manifest)" ]; }
_wallpapers_write() {
  local dest="$(_wallpapers_dir)" parent tmp
  parent="$(dirname "$dest")"; mkdir -p "$parent" || return 1
  tmp="$(mktemp -d "$parent/.atlas-wallpapers.XXXXXX")" || return 1
  cp "$(_wallpapers_source_dir)"/*.svg "$tmp"/ || { rm -rf "$tmp"; return 1; }
  chmod 755 "$tmp" || { rm -rf "$tmp"; return 1; }
  chmod 644 "$tmp"/*.svg || { rm -rf "$tmp"; return 1; }
  rm -rf "$dest" || { rm -rf "$tmp"; return 1; }
  mv "$tmp" "$dest" || { rm -rf "$tmp"; return 1; }
}
_wallpapers_preflight_absent() { [ ! -e "$(_wallpapers_dir)" ] && [ ! -L "$(_wallpapers_dir)" ]; }
module::check() { _wallpapers_marker_load || return 1; [ "$_WALLPAPERS_MARKER_STATE" = installed ] || return 1; _wallpapers_match; }
module::install() { os::is_fedora || return 1; _wallpapers_marker_load || return 1; case "$_WALLPAPERS_MARKER_STATE" in absent|detached) _wallpapers_preflight_absent || return 1 ;; esac; _wallpapers_marker_write installing || return 1; _wallpapers_write || return 1; _wallpapers_match || return 1; _wallpapers_marker_write installed; }
module::verify() { _wallpapers_marker_load || return 1; case "$_WALLPAPERS_MARKER_STATE" in absent|detached) return 0 ;; installing) return 1 ;; esac; _wallpapers_match; }
module::update() { _wallpapers_marker_load || return 1; case "$_WALLPAPERS_MARKER_STATE" in absent|detached) return 0 ;; esac; _wallpapers_write || return 1; _wallpapers_marker_write installed; }
module::remove() { _wallpapers_marker_load || return 1; case "$_WALLPAPERS_MARKER_STATE" in absent|detached) return 0 ;; esac; _wallpapers_match || return 1; rm -rf "$(_wallpapers_dir)" || return 1; _wallpapers_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/wallpapers is reconstructable from Atlas"; }
module::restore() { log::info "nothing to restore: reinstall desktop/wallpapers to reconstruct Atlas-owned wallpapers"; }

# --- RFC-0033 activation ---------------------------------------------------------
# Reversible, opt-in switch of every desktop's wallpaper to the Atlas primary image,
# captured per discovered desktop containment (multi-monitor faithful). Activation is
# refused up front if any desktop's active wallpaper plugin is not org.kde.image.
_WP_ACT_ABSENT="__ATLAS_ABSENT__"
declare -gA _WP_ACT_PRIOR=()
_wp_appletsrc() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc"; }
_wp_act_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/activated/desktop-wallpapers"; }
_wp_atlas_image() { printf '%s\n' "$(_wallpapers_dir)/atlas-gradient.svg"; }
_wp_atlas_url() { printf '%s\n' "file://$(_wp_atlas_image)"; }
_wp_norm() { local v="$1"; printf '%s\n' "${v#file://}"; }   # strip file:// for comparison
# Discover desktop containment ids (plugin folder/desktopcontainment; panels ignored).
_wp_discover() {
  local src id plugin; src="$(_wp_appletsrc)"; [ -f "$src" ] || return 0
  while IFS= read -r id; do
    plugin="$(kreadconfig6 --file "$src" --group Containments --group "$id" --key plugin --default "")"
    case "$plugin" in org.kde.plasma.folder|org.kde.desktopcontainment) printf '%s\n' "$id" ;; esac
  done < <(grep -oE '^\[Containments\]\[[0-9]+\]$' "$src" 2>/dev/null | grep -oE '[0-9]+' | sort -un)
}
_wp_read_plugin() { kreadconfig6 --file "$(_wp_appletsrc)" --group Containments --group "$1" --key wallpaperplugin --default ""; }
_wp_read_image() { kreadconfig6 --file "$(_wp_appletsrc)" --group Containments --group "$1" --group Wallpaper --group org.kde.image --group General --key Image --default "$_WP_ACT_ABSENT"; }
_wp_write_image() { kwriteconfig6 --file "$(_wp_appletsrc)" --group Containments --group "$1" --group Wallpaper --group org.kde.image --group General --key Image "$2"; }
_wp_delete_image() { kwriteconfig6 --file "$(_wp_appletsrc)" --group Containments --group "$1" --group Wallpaper --group org.kde.image --group General --key Image --delete ""; }
_wp_act_init() { _WP_ACT_STATE=absent; _WP_ACT_CONTAINMENTS=""; _WP_ACT_PRIOR=(); }
_wp_act_load() {
  _wp_act_init
  local marker line key val seen_schema=0 seen_state=0 seen_conts=0 id
  marker="$(_wp_act_marker)"; [ -e "$marker" ] || return 0
  [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || { log::error "wallpapers activation marker not a readable regular file: $marker"; return 1; }
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "wallpapers activation marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue
    case "$line" in *=*) key="${line%%=*}"; val="${line#*=}" ;; *) log::error "wallpapers activation marker invalid line: $line"; return 1 ;; esac
    case "$key" in
      schema) [ "$val" = 1 ] || { log::error "wallpapers activation schema unsupported: $val"; return 1; }; seen_schema=1 ;;
      state) case "$val" in activating|active|inactive) _WP_ACT_STATE="$val" ;; *) log::error "wallpapers activation state invalid: $val"; return 1 ;; esac; seen_state=1 ;;
      containments) _WP_ACT_CONTAINMENTS="$val"; seen_conts=1 ;;
      prior_image_*) id="${key#prior_image_}"; case "$id" in ''|*[!0-9]*) log::error "wallpapers activation marker bad containment id: $key"; return 1 ;; esac; _WP_ACT_PRIOR["$id"]="$val" ;;
      *) log::error "wallpapers activation marker unknown key: $key"; return 1 ;;
    esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] && [ "$seen_state" -eq 1 ] || { log::error "wallpapers activation marker missing schema/state"; return 1; }
  case "$_WP_ACT_STATE" in
    inactive)
      [ "$seen_conts" -eq 0 ] && [ "${#_WP_ACT_PRIOR[@]}" -eq 0 ] || { log::error "wallpapers activation marker has containments/prior under inactive"; return 1; } ;;
    activating|active)
      [ "$seen_conts" -eq 1 ] || { log::error "wallpapers activation marker missing containments under $_WP_ACT_STATE"; return 1; }
      # exactly one prior_image_<id> per listed id, and none extra
      for id in $_WP_ACT_CONTAINMENTS; do
        case "$id" in ''|*[!0-9]*) log::error "wallpapers activation marker bad containment id in list: $id"; return 1 ;; esac
        [ -n "${_WP_ACT_PRIOR[$id]+x}" ] || { log::error "wallpapers activation marker missing prior_image_$id"; return 1; }
      done
      [ "${#_WP_ACT_PRIOR[@]}" -eq "$(printf '%s\n' $_WP_ACT_CONTAINMENTS | grep -c .)" ] || { log::error "wallpapers activation marker has an extra prior_image_*"; return 1; } ;;
  esac
}
_wp_act_write() {
  local state="$1" marker dir tmp id
  marker="$(_wp_act_marker)"; dir="$(dirname "$marker")"
  mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-wallpapers.act.XXXXXX")" || return 1
  {
    printf 'schema=1\nstate=%s\n' "$state"
    case "$state" in
      activating|active)
        printf 'containments=%s\n' "$_WP_ACT_CONTAINMENTS"
        for id in $_WP_ACT_CONTAINMENTS; do printf 'prior_image_%s=%s\n' "$id" "${_WP_ACT_PRIOR[$id]}"; done ;;
    esac
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }
}
_wp_live_nudge() { command -v plasma-apply-wallpaperimage >/dev/null 2>&1 && plasma-apply-wallpaperimage "$1" >/dev/null 2>&1; }
module::activate() {
  _wallpapers_marker_load || return 1
  [ "$_WALLPAPERS_MARKER_STATE" = installed ] || { log::error "desktop/wallpapers is not installed; run 'atlas install desktop/wallpapers' before activating"; return 1; }
  { command -v kreadconfig6 && command -v kwriteconfig6; } >/dev/null 2>&1 || { log::error "kreadconfig6/kwriteconfig6 not found"; return 1; }
  [ -f "$(_wp_appletsrc)" ] || { log::error "Plasma appletsrc not found; is this a Plasma session?"; return 1; }
  local ids id; ids="$(_wp_discover)"
  [ -n "$ids" ] || { log::error "no desktop containments found to activate"; return 1; }
  # Refuse-at-activate: every desktop must be a single capturable image.
  for id in $ids; do
    local wp; wp="$(_wp_read_plugin "$id")"
    [ "$wp" = org.kde.image ] || { log::error "desktop $id uses '$wp'; Atlas can only reversibly activate over a single-image wallpaper — switch it to an image first, or leave the wallpaper user-owned"; return 1; }
  done
  _wp_act_load || return 1
  local atlas_url atlas_path; atlas_url="$(_wp_atlas_url)"; atlas_path="$(_wp_atlas_image)"
  if [ "$_WP_ACT_STATE" = active ]; then
    local all_atlas=1
    for id in $_WP_ACT_CONTAINMENTS; do [ "$(_wp_norm "$(_wp_read_image "$id")")" = "$atlas_path" ] || all_atlas=0; done
    [ "$all_atlas" = 1 ] && { log::info "Atlas wallpaper already active"; return 0; }
    log::error "wallpaper changed since activation; refusing to clobber — delete $(_wp_act_marker) to disown"; return 1
  fi
  # Record prior write-once: reuse an interrupted activating record; else capture now.
  if [ -z "$_WP_ACT_CONTAINMENTS" ]; then
    _WP_ACT_CONTAINMENTS="$(printf '%s ' $ids)"; _WP_ACT_CONTAINMENTS="${_WP_ACT_CONTAINMENTS% }"
    _WP_ACT_PRIOR=(); for id in $ids; do _WP_ACT_PRIOR["$id"]="$(_wp_read_image "$id")"; done
  fi
  _wp_act_write activating || return 1
  for id in $_WP_ACT_CONTAINMENTS; do _wp_write_image "$id" "$atlas_url" >/dev/null 2>&1 || { log::error "failed to set wallpaper on desktop $id"; return 1; }; done
  _wp_act_write active || return 1
  if _wp_live_nudge "$atlas_path"; then log::info "Atlas wallpaper activated (applied live)"; else log::info "Atlas wallpaper activated (applies at next login)"; fi
}
module::deactivate() {
  _wp_act_load || return 1
  case "$_WP_ACT_STATE" in absent|inactive) log::info "desktop/wallpapers is not activated by Atlas"; return 0 ;; esac
  command -v kwriteconfig6 >/dev/null 2>&1 || { log::error "kwriteconfig6 not found"; return 1; }
  local id atlas_path; atlas_path="$(_wp_atlas_image)"
  # Per-containment classify (restore/skip/drift) before touching anything.
  declare -A act=()
  for id in $_WP_ACT_CONTAINMENTS; do
    local cur; cur="$(_wp_norm "$(_wp_read_image "$id")")"
    if [ "$cur" = "$atlas_path" ]; then act["$id"]=restore
    elif [ "$cur" = "$(_wp_norm "${_WP_ACT_PRIOR[$id]}")" ]; then act["$id"]=skip
    else act["$id"]=drift; fi
  done
  if [ "$_WP_ACT_STATE" = active ]; then
    for id in $_WP_ACT_CONTAINMENTS; do
      [ "${act[$id]}" = drift ] && { log::error "wallpaper on desktop $id changed since activation; refusing to restore — delete $(_wp_act_marker) to disown"; return 1; }
    done
  fi
  local restored_val="" uniform=1 n=0
  for id in $_WP_ACT_CONTAINMENTS; do
    [ "${act[$id]}" = restore ] || continue
    local prior="${_WP_ACT_PRIOR[$id]}"
    if [ "$prior" = "$_WP_ACT_ABSENT" ]; then
      _wp_delete_image "$id" >/dev/null 2>&1 || { log::error "failed to remove wallpaper key on desktop $id; state left unchanged"; return 1; }
      uniform=0
    else
      _wp_write_image "$id" "$prior" >/dev/null 2>&1 || { log::error "failed to restore wallpaper on desktop $id; state left unchanged"; return 1; }
      n=$((n+1))
      if [ -z "$restored_val" ]; then restored_val="$prior"; elif [ "$restored_val" != "$prior" ]; then uniform=0; fi
    fi
  done
  _wp_act_write inactive || return 1
  if [ "$uniform" = 1 ] && [ "$n" -ge 1 ] && _wp_live_nudge "$(_wp_norm "$restored_val")"; then
    log::info "desktop/wallpapers deactivated; restored prior wallpaper (applied live)"
  else
    log::info "desktop/wallpapers deactivated; restored prior wallpaper (applies at next login)"
  fi
}
