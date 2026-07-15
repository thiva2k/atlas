#!/usr/bin/env bash
# desktop/ksplash - RFC-0037.
#
# Atlas does not ship its own KSplash package — the org.atlas.hud look-and-feel
# package already carries a contents/splash/Splash.qml (installed by
# desktop/lockscreen). desktop/ksplash is activation-only: install/check/verify
# are thin hooks that confirm the splash the package needs is present (they own
# nothing new to install), and module::activate/deactivate reversibly switch
# ksplashrc [KSplash] Theme to org.atlas.hud, reusing the RFC-0029 escrow
# pattern exactly as desktop/lockscreen does for kscreenlockerrc [Greeter] Theme.
MODULE_NAME="ksplash"
MODULE_DESCRIPTION="Startup splash: activates the org.atlas.hud KSplash theme shipped by desktop/lockscreen."
MODULE_DEPENDS=(desktop/lockscreen)

_KSPLASH_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_KSPLASH_PACKAGE_ID="org.atlas.hud"

_ksplash_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/plasma/look-and-feel/$_KSPLASH_PACKAGE_ID"; }
_ksplash_splash_qml() { printf '%s\n' "$(_ksplash_dir)/contents/splash/Splash.qml"; }

# --- install/check/verify: thin presence checks, nothing Atlas-owned to write ---
_ksplash_present() { [ -r "$(_ksplash_splash_qml)" ]; }

module::check() { _ksplash_present; }
module::install() {
  _ksplash_present || {
    log::error "the org.atlas.hud KSplash package is missing: $(_ksplash_splash_qml)"
    log::error "  fix: run 'atlas install desktop/lockscreen' first (it ships the splash)"
    return 1
  }
  log::info "the Atlas KSplash theme (org.atlas.hud) is present; nothing further to install"
}
module::verify() {
  _ksplash_present || {
    log::error "the org.atlas.hud KSplash package is missing or unreadable: $(_ksplash_splash_qml)"
    return 1
  }
}
module::update()  { module::verify; }
module::remove()  { log::info "desktop/ksplash owns no installed files; nothing to remove (the package itself belongs to desktop/lockscreen)"; }
module::backup()  { log::info "nothing to back up: desktop/ksplash owns no installed files"; }
module::restore() { log::info "nothing to restore: desktop/ksplash owns no installed files"; }

# --- RFC-0029 activation (reversible, opt-in switch of ksplashrc [KSplash] Theme) ---
# Reuses the desktop/lockscreen escrow pattern exactly: a transitional `activating`
# state, write-once prior, refuse-to-clobber on drift, already-restored finalize on
# deactivate, and an absent sentinel + delete-on-restore when the Theme key did not
# previously exist. Applies at next login/startup — ksplashqml reads the Theme key
# when it spawns between login and the desktop appearing, not live.
#
# Engine: on this Plasma 6.7 install, Engine=KSplashQML is already the effective
# default via the kdedefaults cascade (the active look-and-feel package's
# contents/defaults ships [ksplashrc][KSplash] Engine=KSplashQML), confirmed with
# `kreadconfig6 --file ksplashrc --group KSplash --key Engine` resolving to
# KSplashQML even with no user-scope ksplashrc present. Atlas therefore does not
# manage Engine — only Theme. If a future environment's default engine is not
# KSplashQML, activate() checks the resolved value and fails with guidance rather
# than silently writing a splash theme that will never run.
_KSPLASH_ACT_ABSENT="__ATLAS_ABSENT__"
_ksplash_act_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/activated/desktop-ksplash"; }
_ksplash_read_theme() { kreadconfig6 --file ksplashrc --group KSplash --key Theme --default "$_KSPLASH_ACT_ABSENT"; }
_ksplash_read_engine() { kreadconfig6 --file ksplashrc --group KSplash --key Engine --default "$_KSPLASH_ACT_ABSENT"; }

_ksplash_act_init() { _KSPLASH_ACT_STATE=absent; _KSPLASH_ACT_PRIOR=; }
_ksplash_act_load() {
  _ksplash_act_init
  local marker line key val seen_schema=0 seen_state=0 seen_prior=0
  marker="$(_ksplash_act_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then log::error "ksplash activation marker is not a readable regular file: $marker"; return 1; fi
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "ksplash activation marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue; case "$line" in \#*) continue ;; esac
    case "$line" in *=*) key="${line%%=*}"; val="${line#*=}" ;; *) log::error "ksplash activation marker has an invalid line: $line"; return 1 ;; esac
    case "$key" in
      schema) [ "$val" = "1" ] || { log::error "ksplash activation schema is unsupported: $val"; return 1; }; seen_schema=1 ;;
      state) case "$val" in activating|active|inactive) _KSPLASH_ACT_STATE="$val" ;; *) log::error "ksplash activation state is invalid: $val"; return 1 ;; esac; seen_state=1 ;;
      prior_theme) _KSPLASH_ACT_PRIOR="$val"; seen_prior=1 ;;
      *) log::error "ksplash activation marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] || { log::error "ksplash activation marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "ksplash activation marker is missing state"; return 1; }
  case "$_KSPLASH_ACT_STATE" in
    inactive) [ "$seen_prior" -eq 0 ] || { log::error "ksplash activation marker has prior_theme under inactive state"; return 1; } ;;
    activating|active) [ "$seen_prior" -eq 1 ] && [ -n "$_KSPLASH_ACT_PRIOR" ] || { log::error "ksplash activation marker is missing prior_theme under $_KSPLASH_ACT_STATE"; return 1; } ;;
  esac
}
_ksplash_act_write() {
  local state="$1" prior="${2:-}" marker dir tmp
  marker="$(_ksplash_act_marker)"; dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.desktop-ksplash.act.XXXXXX")" || { log::error "cannot create ksplash activation temp file"; return 1; }
  {
    printf 'schema=1\n'; printf 'state=%s\n' "$state"
    case "$state" in activating|active) printf 'prior_theme=%s\n' "$prior" ;; esac
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

module::activate() {
  _ksplash_present || { log::error "the org.atlas.hud KSplash package is not installed; run 'atlas install desktop/lockscreen' before activating"; return 1; }
  { command -v kreadconfig6 && command -v kwriteconfig6; } >/dev/null 2>&1 || { log::error "kreadconfig6/kwriteconfig6 not found; cannot manage the KSplash theme"; return 1; }
  local engine; engine="$(_ksplash_read_engine)"
  [ "$engine" = "KSplashQML" ] || { log::error "ksplashrc [KSplash] Engine is '$engine', not KSplashQML; Atlas will not activate a QML splash theme that will not run — set Engine=KSplashQML first"; return 1; }
  _ksplash_act_load || return 1
  local current; current="$(_ksplash_read_theme)"
  if [ "$_KSPLASH_ACT_STATE" = "active" ]; then
    [ "$current" = "$_KSPLASH_PACKAGE_ID" ] && { log::info "Atlas KSplash theme is already active"; return 0; }
    log::error "KSplash theme changed since activation (now: $current); refusing to clobber — delete $(_ksplash_act_marker) to disown"; return 1
  fi
  # transition (absent|activating|inactive) -> active, recording the prior write-once.
  local prior="$_KSPLASH_ACT_PRIOR"; [ -n "$prior" ] || prior="$current"
  _ksplash_act_write activating "$prior" || return 1
  kwriteconfig6 --file ksplashrc --group KSplash --key Theme "$_KSPLASH_PACKAGE_ID" >/dev/null 2>&1 || { log::error "failed to set the KSplash theme"; return 1; }
  _ksplash_act_write active "$prior" || return 1
  log::info "Atlas KSplash theme activated (prior recorded: $prior); applies at next login/startup"
}
module::deactivate() {
  _ksplash_act_load || return 1
  case "$_KSPLASH_ACT_STATE" in absent|inactive) log::info "desktop/ksplash is not activated by Atlas"; return 0 ;; esac
  command -v kwriteconfig6 >/dev/null 2>&1 || { log::error "kwriteconfig6 not found; cannot restore the KSplash theme"; return 1; }
  local current prior="$_KSPLASH_ACT_PRIOR"; current="$(_ksplash_read_theme)"
  if [ "$_KSPLASH_ACT_STATE" = "active" ] && [ "$current" != "$_KSPLASH_PACKAGE_ID" ]; then
    if [ "$current" = "$prior" ]; then _ksplash_act_write inactive || return 1; log::info "desktop/ksplash already restored to $prior; marked inactive"; return 0; fi
    log::error "KSplash theme changed since activation (now: $current); refusing to restore — delete $(_ksplash_act_marker) to disown"; return 1
  fi
  if [ "$prior" = "$_KSPLASH_ACT_ABSENT" ]; then
    kwriteconfig6 --file ksplashrc --group KSplash --key Theme --delete "" >/dev/null 2>&1 || { log::error "failed to remove the Theme key (prior was absent); state left unchanged"; return 1; }
  else
    kwriteconfig6 --file ksplashrc --group KSplash --key Theme "$prior" >/dev/null 2>&1 || { log::error "failed to restore prior KSplash theme '$prior'; state left unchanged — delete $(_ksplash_act_marker) to disown"; return 1; }
  fi
  _ksplash_act_write inactive || return 1
  log::info "desktop/ksplash deactivated; restored $prior; applies at next login/startup"
}
