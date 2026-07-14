#!/usr/bin/env bash
# desktop/plymouth - RFC-0024.
MODULE_NAME="plymouth"
MODULE_DESCRIPTION="Plymouth: installs the minimal Atlas boot splash theme."
MODULE_DEPENDS=()
_PLYMOUTH_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_plymouth_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-plymouth"; }
_plymouth_source_dir() { printf '%s\n' "$_PLYMOUTH_MODULE_DIR/assets"; }
_plymouth_theme_dir() { printf '%s\n' "/usr/share/plymouth/themes/atlas"; }
_plymouth_run_privileged() { if os::is_root; then "$@"; else sudo "$@"; fi; }
_plymouth_manifest_source() { (cd "$(_plymouth_source_dir)" && find . -type f -print | sort | xargs sha256sum) 2>/dev/null; }
_plymouth_manifest_current() { (cd "$(_plymouth_theme_dir)" && find . -type f -print | sort | xargs sha256sum) 2>/dev/null; }
_plymouth_marker_init() { _PLYMOUTH_MARKER_STATE=absent; }
_plymouth_marker_load() { _plymouth_marker_init; local marker="$(_plymouth_marker)" line val s=0 t=0; [ -e "$marker" ] || return 0; [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || return 1; [ "$(stat -c '%a' "$marker" 2>/dev/null)" = 600 ] || return 1; while IFS= read -r line || [ -n "$line" ]; do line="${line%$'\r'}"; case "$line" in schema=1) s=1 ;; state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _PLYMOUTH_MARKER_STATE="$val" ;; *) return 1 ;; esac; t=1 ;; "") ;; *) return 1 ;; esac; done < "$marker"; [ "$s" -eq 1 ] && [ "$t" -eq 1 ]; }
_plymouth_marker_write() { local state="$1" marker dir tmp; marker="$(_plymouth_marker)"; dir="$(dirname "$marker")"; mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1; tmp="$(mktemp "$dir/.desktop-plymouth.XXXXXX")" || return 1; { printf 'schema=1\nstate=%s\n' "$state"; } > "$tmp" || { rm -f "$tmp"; return 1; }; chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }; }
_plymouth_matches() { [ -d "$(_plymouth_theme_dir)" ] && [ "$(_plymouth_manifest_source)" = "$(_plymouth_manifest_current)" ]; }
_plymouth_write() { local dest="$(_plymouth_theme_dir)" parent tmp; parent="$(dirname "$dest")"; _plymouth_run_privileged mkdir -p "$parent" || return 1; tmp="$(_plymouth_run_privileged mktemp -d "$parent/.atlas-plymouth.XXXXXX")" || return 1; _plymouth_run_privileged cp "$(_plymouth_source_dir)"/* "$tmp"/ || { _plymouth_run_privileged rm -rf "$tmp" 2>/dev/null || true; return 1; }; _plymouth_run_privileged chmod 755 "$tmp" || { _plymouth_run_privileged rm -rf "$tmp" 2>/dev/null || true; return 1; }; _plymouth_run_privileged chmod 644 "$tmp"/* || { _plymouth_run_privileged rm -rf "$tmp" 2>/dev/null || true; return 1; }; _plymouth_run_privileged rm -rf "$dest" || { _plymouth_run_privileged rm -rf "$tmp" 2>/dev/null || true; return 1; }; _plymouth_run_privileged mv "$tmp" "$dest"; }
# RFC-0024a: a ModuleName=script theme is inert without /usr/lib64/plymouth/script.so
# (Fedora pkg plymouth-plugin-script). check/verify gate on the plugin so "healthy"
# implies "renderable"; install adopts the plugin as the theme's runtime dependency.
module::check() { _plymouth_marker_load || return 1; [ "$_PLYMOUTH_MARKER_STATE" = installed ] || return 1; os::pkg_installed plymouth-plugin-script || return 1; _plymouth_matches; }
module::install() { os::is_fedora || return 1; _plymouth_marker_load || return 1; case "$_PLYMOUTH_MARKER_STATE" in absent|detached) [ ! -e "$(_plymouth_theme_dir)" ] || return 1 ;; esac; _plymouth_marker_write installing || return 1; os::dnf_install plymouth-plugin-script || return 1; _plymouth_write || return 1; _plymouth_matches || return 1; _plymouth_marker_write installed; }
module::verify() { _plymouth_marker_load || return 1; case "$_PLYMOUTH_MARKER_STATE" in absent|detached) return 0 ;; installing) return 1 ;; esac; os::pkg_installed plymouth-plugin-script || { log::error "plymouth-plugin-script not installed; Atlas script theme cannot render"; return 1; }; _plymouth_matches; }
module::update() { _plymouth_marker_load || return 1; case "$_PLYMOUTH_MARKER_STATE" in absent|detached) return 0 ;; esac; _plymouth_write || return 1; _plymouth_marker_write installed; }
module::remove() { _plymouth_marker_load || return 1; case "$_PLYMOUTH_MARKER_STATE" in absent|detached) return 0 ;; esac; _plymouth_matches || return 1; _plymouth_run_privileged rm -rf "$(_plymouth_theme_dir)" || return 1; _plymouth_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/plymouth is reconstructable"; }
module::restore() { log::info "nothing to restore: reinstall desktop/plymouth"; }

# --- RFC-0032 activation --------------------------------------------------------
# Reversible, opt-in switch of the system default plymouth theme to `atlas`.
# Applying/restoring is `plymouth-set-default-theme -R <name>` (privileged, rebuilds
# the initramfs). The recorded prior is the default theme *name*, captured via the
# unprivileged no-arg read (never empty per the real tool; no sentinel). A terminal
# state (active|inactive) is written only AFTER the matching -R rebuild succeeds.
_PLYMOUTH_ACT_THEME="atlas"
_plymouth_act_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/activated/desktop-plymouth"; }
# Unprivileged read of the current system default theme name (wrapper so tests can mock).
_plymouth_read_default() { plymouth-set-default-theme; }
_plymouth_act_init() { _PLYMOUTH_ACT_STATE=absent; _PLYMOUTH_ACT_PRIOR=; }
_plymouth_act_load() {
  _plymouth_act_init
  local marker line key val seen_schema=0 seen_state=0 seen_prior=0
  marker="$(_plymouth_act_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then log::error "Plymouth activation marker is not a readable regular file: $marker"; return 1; fi
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || { log::error "Plymouth activation marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; [ -z "$line" ] && continue; case "$line" in \#*) continue ;; esac
    case "$line" in *=*) key="${line%%=*}"; val="${line#*=}" ;; *) log::error "Plymouth activation marker has an invalid line: $line"; return 1 ;; esac
    case "$key" in
      schema) [ "$val" = "1" ] || { log::error "Plymouth activation schema is unsupported: $val"; return 1; }; seen_schema=1 ;;
      state) case "$val" in activating|active|inactive) _PLYMOUTH_ACT_STATE="$val" ;; *) log::error "Plymouth activation state is invalid: $val"; return 1 ;; esac; seen_state=1 ;;
      prior_default_theme) _PLYMOUTH_ACT_PRIOR="$val"; seen_prior=1 ;;
      *) log::error "Plymouth activation marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"
  [ "$seen_schema" -eq 1 ] || { log::error "Plymouth activation marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Plymouth activation marker is missing state"; return 1; }
  # §5.2: prior_default_theme present and non-empty iff state is activating|active.
  case "$_PLYMOUTH_ACT_STATE" in
    inactive) [ "$seen_prior" -eq 0 ] || { log::error "Plymouth activation marker has prior_default_theme under inactive state"; return 1; } ;;
    activating|active) [ "$seen_prior" -eq 1 ] && [ -n "$_PLYMOUTH_ACT_PRIOR" ] || { log::error "Plymouth activation marker is missing/empty prior_default_theme under $_PLYMOUTH_ACT_STATE"; return 1; } ;;
  esac
}
_plymouth_act_write() {
  local state="$1" prior="${2:-}" marker dir tmp
  marker="$(_plymouth_act_marker)"; dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.desktop-plymouth.act.XXXXXX")" || { log::error "cannot create Plymouth activation temp file"; return 1; }
  {
    printf 'schema=1\n'; printf 'state=%s\n' "$state"
    case "$state" in activating|active) printf 'prior_default_theme=%s\n' "$prior" ;; esac
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}
# §5.3: non-interactive privilege preflight — never starts a cancellable prompt.
_plymouth_privilege_ok() { os::is_root || sudo -n true 2>/dev/null; }
_plymouth_sudo_guidance() {
  log::error "plymouth activation requires root to rebuild the initramfs (plymouth-set-default-theme -R). Re-run with sudo available and a terminal, e.g.:"
  log::error "  sudo atlas activate desktop/plymouth"
  log::error "This step rebuilds the initramfs and takes seconds to minutes."
}
module::activate() {
  # §5.4 step 1: preconditions.
  _plymouth_marker_load || return 1
  [ "$_PLYMOUTH_MARKER_STATE" = "installed" ] || { log::error "desktop/plymouth is not installed; run 'atlas install desktop/plymouth' before activating"; return 1; }
  os::pkg_installed plymouth-plugin-script || { log::error "plymouth-plugin-script not installed; run 'atlas install desktop/plymouth' before activating"; return 1; }
  command -v plymouth-set-default-theme >/dev/null 2>&1 || { log::error "plymouth-set-default-theme not found; cannot activate the Atlas boot splash"; return 1; }
  _plymouth_privilege_ok || { _plymouth_sudo_guidance; return 1; }
  # §5.4 step 2: load activation state; read current default (unprivileged, never empty).
  _plymouth_act_load || return 1
  local current; current="$(_plymouth_read_default)"
  # §5.4 step 3: already active.
  if [ "$_PLYMOUTH_ACT_STATE" = "active" ]; then
    [ "$current" = "$_PLYMOUTH_ACT_THEME" ] && { log::info "Atlas boot splash is already active"; return 0; }
    log::error "the default plymouth theme changed since activation (now: $current); refusing to clobber — delete $(_plymouth_act_marker) to disown"; return 1
  fi
  # §5.4 step 4: transition (absent|activating|inactive) -> active, prior write-once.
  local prior="$_PLYMOUTH_ACT_PRIOR"; [ -n "$prior" ] || prior="$current"
  _plymouth_act_write activating "$prior" || return 1
  log::info "rebuilding the initramfs to apply the Atlas boot splash; this takes seconds to minutes"
  _plymouth_run_privileged plymouth-set-default-theme -R "$_PLYMOUTH_ACT_THEME" >/dev/null || { log::error "failed to apply the Atlas boot splash (initramfs rebuild failed); state left at 'activating'"; return 1; }
  _plymouth_act_write active "$prior" || return 1
  log::info "Atlas boot splash activated (prior default recorded: $prior)"
}
module::deactivate() {
  # §5.5 step 1: nothing to do without an active-ish record.
  _plymouth_act_load || return 1
  case "$_PLYMOUTH_ACT_STATE" in absent|inactive) log::info "desktop/plymouth is not activated by Atlas"; return 0 ;; esac
  # §5.5 step 2: require tool + privilege (restore also rebuilds).
  command -v plymouth-set-default-theme >/dev/null 2>&1 || { log::error "plymouth-set-default-theme not found; cannot restore the prior boot splash"; return 1; }
  _plymouth_privilege_ok || { _plymouth_sudo_guidance; return 1; }
  # §5.5 step 3: refuse-to-clobber user drift under state=active. If current==prior the
  # restore's config write already landed (interrupted-deactivate finalize) — not drift;
  # fall through to step 4 and re-run -R <prior> to earn `inactive` (no no-rebuild path).
  local current prior="$_PLYMOUTH_ACT_PRIOR"; current="$(_plymouth_read_default)"
  if [ "$_PLYMOUTH_ACT_STATE" = "active" ] && [ "$current" != "$_PLYMOUTH_ACT_THEME" ] && [ "$current" != "$prior" ]; then
    log::error "the default plymouth theme changed since activation (now: $current); not restoring — delete $(_plymouth_act_marker) to disown"; return 1
  fi
  # §5.5 step 4: restore the recorded prior; always rebuild (no no-rebuild finalize).
  log::info "rebuilding the initramfs to restore the prior boot splash ($prior); this takes seconds to minutes"
  _plymouth_run_privileged plymouth-set-default-theme -R "$prior" >/dev/null || { log::error "failed to restore prior boot splash '$prior' (it may no longer exist); state left unchanged — pick a default with 'sudo plymouth-set-default-theme -R <theme>' then delete $(_plymouth_act_marker) to disown"; return 1; }
  # §5.5 step 5: earn the terminal inactive state (escrow consumed).
  _plymouth_act_write inactive || return 1
  log::info "desktop/plymouth deactivated; restored prior default theme $prior"
}
