#!/usr/bin/env bash
# desktop/lockscreen - RFC-0035.
#
# Atlas owns a Plasma look-and-feel package, org.atlas.hud, shipped under
# assets/org.atlas.hud and installed USER-scope (no root) to
# $XDG_DATA_HOME/plasma/look-and-feel/org.atlas.hud/. Atlas never changes the
# active lock-screen theme on install — that is a separate, reversible
# activation (RFC-0029) that switches kscreenlockerrc [Greeter] Theme.
MODULE_NAME="lockscreen"
MODULE_DESCRIPTION="Lock-screen HUD: installs the org.atlas.hud Plasma look-and-feel package without changing the active lock theme."
MODULE_DEPENDS=()

_LOCKSCREEN_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LOCKSCREEN_PACKAGE_ID="org.atlas.hud"

_lockscreen_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-lockscreen"; }
_lockscreen_source_dir() { printf '%s\n' "$_LOCKSCREEN_MODULE_DIR/assets/$_LOCKSCREEN_PACKAGE_ID"; }
_lockscreen_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/look-and-feel/$_LOCKSCREEN_PACKAGE_ID"; }

# Manifest: every shipped file's relative path + sha256, sorted. Used both to
# detect drift (verify) and as the marker's content fingerprint (in-place
# upgrades to a new Atlas package layout are picked up by re-hashing the
# *source*, not by hard-failing marker_load — see _lockscreen_marker_load).
_lockscreen_manifest() { (cd "$(_lockscreen_source_dir)" && find . -type f -print | sort | xargs sha256sum) 2>/dev/null; }
_lockscreen_current_manifest() { (cd "$(_lockscreen_dir)" && find . -type f -print | sort | xargs sha256sum) 2>/dev/null; }
_lockscreen_manifest_hash() { _lockscreen_manifest | sha256sum | awk '{print $1}'; }
_lockscreen_hash_valid() { [ "${#1}" -eq 64 ] && case "$1" in *[!0-9a-f]*|"") return 1 ;; *) return 0 ;; esac; }

# --- install marker ----------------------------------------------------------
_lockscreen_marker_init() { _LOCKSCREEN_MARKER_STATE=absent; _LOCKSCREEN_MARKER_SHA=; }

# IMPORTANT (in-place-upgrade-safe): marker_load validates only the marker
# file's OWN structural integrity (schema/state/hash-format) — it must never
# hard-fail just because the shipped source content changed since the marker
# was written (e.g. a new Atlas release touches LockScreenUi.qml). Content
# drift is judged separately by _lockscreen_matches, called explicitly from
# check/verify. This mirrors desktop/theme and desktop/wallpapers, and avoids
# the bug fish/fastfetch had before their in-place-upgrade fix.
_lockscreen_marker_load() {
  _lockscreen_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_sha=0
  marker="$(_lockscreen_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then log::error "Lockscreen marker is not a readable regular file: $marker"; return 1; fi
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "Lockscreen marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue; case "$line" in \#*) continue ;; esac
    case "$line" in *=*) key="${line%%=*}"; val="${line#*=}" ;; *) log::error "Lockscreen marker has an invalid line: $line"; return 1 ;; esac
    case "$key" in
      schema) [ "$val" = "1" ] || { log::error "Lockscreen marker schema is unsupported: $val"; return 1; }; seen_schema=1 ;;
      state) case "$val" in installing|installed|detached) _LOCKSCREEN_MARKER_STATE="$val" ;; *) log::error "Lockscreen marker state is invalid: $val"; return 1 ;; esac; seen_state=1 ;;
      manifest_sha256) _LOCKSCREEN_MARKER_SHA="$val"; seen_sha=1 ;;
      *) log::error "Lockscreen marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] || { log::error "Lockscreen marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Lockscreen marker is missing state"; return 1; }
  [ "$seen_sha" -eq 1 ] || { log::error "Lockscreen marker is missing manifest_sha256"; return 1; }
  _lockscreen_hash_valid "$_LOCKSCREEN_MARKER_SHA" || { log::error "Lockscreen marker manifest_sha256 is invalid"; return 1; }
}

_lockscreen_marker_write() {
  local state="$1" marker dir tmp sha
  marker="$(_lockscreen_marker)"; dir="$(dirname "$marker")"; sha="$(_lockscreen_manifest_hash)"
  [ -n "$sha" ] || { log::error "cannot hash Atlas lock-screen HUD source"; return 1; }
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.desktop-lockscreen.XXXXXX")" || { log::error "cannot create Lockscreen marker temp file"; return 1; }
  { printf 'schema=1\n'; printf 'state=%s\n' "$state"; printf 'manifest_sha256=%s\n' "$sha"; } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_lockscreen_matches() { [ -d "$(_lockscreen_dir)" ] && [ "$(_lockscreen_manifest)" = "$(_lockscreen_current_manifest)" ]; }

_lockscreen_write_package() {
  local dest="$(_lockscreen_dir)" parent tmp
  [ -d "$(_lockscreen_source_dir)" ] || { log::error "Atlas lock-screen HUD source missing: $(_lockscreen_source_dir)"; return 1; }
  parent="$(dirname "$dest")"; mkdir -p "$parent" || { log::error "cannot create $parent"; return 1; }
  tmp="$(mktemp -d "$parent/.atlas-lockscreen.XXXXXX")" || { log::error "cannot create staging dir"; return 1; }
  # Copy the whole package tree (metadata.json + contents/lockscreen/*.qml).
  (cd "$(_lockscreen_source_dir)" && find . -type f -print0) | while IFS= read -r -d '' f; do
    mkdir -p "$tmp/$(dirname "$f")" || exit 1
    cp "$(_lockscreen_source_dir)/$f" "$tmp/$f" || exit 1
  done || { rm -rf "$tmp"; log::error "cannot stage $dest"; return 1; }
  find "$tmp" -type d -exec chmod 755 {} + || { rm -rf "$tmp"; log::error "cannot chmod staged dirs"; return 1; }
  find "$tmp" -type f -exec chmod 644 {} + || { rm -rf "$tmp"; log::error "cannot chmod staged files"; return 1; }
  rm -rf "$dest" || { rm -rf "$tmp"; log::error "cannot clear $dest"; return 1; }
  mv "$tmp" "$dest" || { rm -rf "$tmp"; log::error "cannot replace $dest"; return 1; }
}

_lockscreen_preflight_absent() { [ ! -e "$(_lockscreen_dir)" ] && [ ! -L "$(_lockscreen_dir)" ]; }

module::check() { _lockscreen_marker_load || return 1; [ "$_LOCKSCREEN_MARKER_STATE" = "installed" ] || return 1; _lockscreen_matches; }
module::install() {
  os::is_fedora || { log::error "desktop/lockscreen supports Fedora only"; return 1; }
  _lockscreen_marker_load || return 1
  case "$_LOCKSCREEN_MARKER_STATE" in
    absent|detached) _lockscreen_preflight_absent || { log::error "Atlas lock-screen HUD package already exists and is not Atlas-owned: $(_lockscreen_dir)"; return 1; } ;;
    installing|installed) ;;
  esac
  _lockscreen_marker_write installing || return 1
  _lockscreen_write_package || return 1
  _lockscreen_matches || { log::error "lock-screen HUD package failed to verify after write"; return 1; }
  _lockscreen_marker_write installed || return 1
}
module::verify() {
  _lockscreen_marker_load || return 1
  case "$_LOCKSCREEN_MARKER_STATE" in
    absent) log::info "desktop/lockscreen is not installed by Atlas"; return 0 ;;
    detached) log::warn "desktop/lockscreen is detached"; return 0 ;;
    installing) log::error "desktop/lockscreen install is incomplete"; return 1 ;;
  esac
  _lockscreen_matches || { log::error "Atlas lock-screen HUD package is missing or drifted"; return 1; }
}
module::update() { _lockscreen_marker_load || return 1; case "$_LOCKSCREEN_MARKER_STATE" in absent|detached) return 0 ;; esac; _lockscreen_write_package || return 1; _lockscreen_marker_write installed; }
module::remove() {
  _lockscreen_marker_load || return 1
  case "$_LOCKSCREEN_MARKER_STATE" in absent|detached) return 0 ;; esac
  _lockscreen_matches || { log::error "refusing to remove drifted Atlas lock-screen HUD package"; return 1; }
  rm -rf "$(_lockscreen_dir)" || return 1
  _lockscreen_marker_write detached
}
module::backup() { log::info "nothing to back up: desktop/lockscreen is reconstructable from Atlas"; }
module::restore() { log::info "nothing to restore: reinstall desktop/lockscreen to reconstruct the Atlas-owned package"; }

# --- RFC-0029 activation (reversible, opt-in switch of kscreenlockerrc [Greeter] Theme) ---
# Reuses the desktop/theme escrow pattern exactly: a transitional `activating`
# state, write-once prior, refuse-to-clobber on drift, already-restored
# finalize on deactivate, and an absent sentinel + delete-on-restore when the
# Theme key did not previously exist. Applies at next lock — kscreenlocker
# reads the Theme key when it spawns kscreenlocker_greet, not live.
_LOCKSCREEN_ACT_ABSENT="__ATLAS_ABSENT__"
_lockscreen_act_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/activated/desktop-lockscreen"; }
_lockscreen_read_theme() { kreadconfig6 --file kscreenlockerrc --group Greeter --key Theme --default "$_LOCKSCREEN_ACT_ABSENT"; }

_lockscreen_act_init() { _LOCKSCREEN_ACT_STATE=absent; _LOCKSCREEN_ACT_PRIOR=; }
_lockscreen_act_load() {
  _lockscreen_act_init
  local marker line key val seen_schema=0 seen_state=0 seen_prior=0
  marker="$(_lockscreen_act_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then log::error "Lockscreen activation marker is not a readable regular file: $marker"; return 1; fi
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "Lockscreen activation marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue; case "$line" in \#*) continue ;; esac
    case "$line" in *=*) key="${line%%=*}"; val="${line#*=}" ;; *) log::error "Lockscreen activation marker has an invalid line: $line"; return 1 ;; esac
    case "$key" in
      schema) [ "$val" = "1" ] || { log::error "Lockscreen activation schema is unsupported: $val"; return 1; }; seen_schema=1 ;;
      state) case "$val" in activating|active|inactive) _LOCKSCREEN_ACT_STATE="$val" ;; *) log::error "Lockscreen activation state is invalid: $val"; return 1 ;; esac; seen_state=1 ;;
      prior_theme) _LOCKSCREEN_ACT_PRIOR="$val"; seen_prior=1 ;;
      *) log::error "Lockscreen activation marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] || { log::error "Lockscreen activation marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Lockscreen activation marker is missing state"; return 1; }
  case "$_LOCKSCREEN_ACT_STATE" in
    inactive) [ "$seen_prior" -eq 0 ] || { log::error "Lockscreen activation marker has prior_theme under inactive state"; return 1; } ;;
    activating|active) [ "$seen_prior" -eq 1 ] && [ -n "$_LOCKSCREEN_ACT_PRIOR" ] || { log::error "Lockscreen activation marker is missing prior_theme under $_LOCKSCREEN_ACT_STATE"; return 1; } ;;
  esac
}
_lockscreen_act_write() {
  local state="$1" prior="${2:-}" marker dir tmp
  marker="$(_lockscreen_act_marker)"; dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.desktop-lockscreen.act.XXXXXX")" || { log::error "cannot create Lockscreen activation temp file"; return 1; }
  {
    printf 'schema=1\n'; printf 'state=%s\n' "$state"
    case "$state" in activating|active) printf 'prior_theme=%s\n' "$prior" ;; esac
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

module::activate() {
  _lockscreen_marker_load || return 1
  [ "$_LOCKSCREEN_MARKER_STATE" = "installed" ] || { log::error "desktop/lockscreen is not installed; run 'atlas install desktop/lockscreen' before activating"; return 1; }
  { command -v kreadconfig6 && command -v kwriteconfig6; } >/dev/null 2>&1 || { log::error "kreadconfig6/kwriteconfig6 not found; cannot manage the lock-screen theme"; return 1; }
  _lockscreen_act_load || return 1
  local current; current="$(_lockscreen_read_theme)"
  if [ "$_LOCKSCREEN_ACT_STATE" = "active" ]; then
    [ "$current" = "$_LOCKSCREEN_PACKAGE_ID" ] && { log::info "Atlas lock-screen HUD is already active"; return 0; }
    log::error "lock-screen theme changed since activation (now: $current); refusing to clobber — delete $(_lockscreen_act_marker) to disown"; return 1
  fi
  # transition (absent|activating|inactive) -> active, recording the prior write-once.
  local prior="$_LOCKSCREEN_ACT_PRIOR"; [ -n "$prior" ] || prior="$current"
  _lockscreen_act_write activating "$prior" || return 1
  kwriteconfig6 --file kscreenlockerrc --group Greeter --key Theme "$_LOCKSCREEN_PACKAGE_ID" >/dev/null 2>&1 || { log::error "failed to set the lock-screen theme"; return 1; }
  _lockscreen_act_write active "$prior" || return 1
  log::info "Atlas lock-screen HUD activated (prior recorded: $prior); applies at next lock"
}
module::deactivate() {
  _lockscreen_act_load || return 1
  case "$_LOCKSCREEN_ACT_STATE" in absent|inactive) log::info "desktop/lockscreen is not activated by Atlas"; return 0 ;; esac
  command -v kwriteconfig6 >/dev/null 2>&1 || { log::error "kwriteconfig6 not found; cannot restore the lock-screen theme"; return 1; }
  local current prior="$_LOCKSCREEN_ACT_PRIOR"; current="$(_lockscreen_read_theme)"
  if [ "$_LOCKSCREEN_ACT_STATE" = "active" ] && [ "$current" != "$_LOCKSCREEN_PACKAGE_ID" ]; then
    if [ "$current" = "$prior" ]; then _lockscreen_act_write inactive || return 1; log::info "desktop/lockscreen already restored to $prior; marked inactive"; return 0; fi
    log::error "lock-screen theme changed since activation (now: $current); refusing to restore — delete $(_lockscreen_act_marker) to disown"; return 1
  fi
  if [ "$prior" = "$_LOCKSCREEN_ACT_ABSENT" ]; then
    kwriteconfig6 --file kscreenlockerrc --group Greeter --key Theme --delete "" >/dev/null 2>&1 || { log::error "failed to remove the Theme key (prior was absent); state left unchanged"; return 1; }
  else
    kwriteconfig6 --file kscreenlockerrc --group Greeter --key Theme "$prior" >/dev/null 2>&1 || { log::error "failed to restore prior lock-screen theme '$prior'; state left unchanged — delete $(_lockscreen_act_marker) to disown"; return 1; }
  fi
  _lockscreen_act_write inactive || return 1
  log::info "desktop/lockscreen deactivated; restored $prior; applies at next lock"
}
