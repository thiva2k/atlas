#!/usr/bin/env bash
# desktop/sddm - RFC-0025.
MODULE_NAME="sddm"
MODULE_DESCRIPTION="SDDM: installs the Atlas login theme and Atlas-owned selector drop-in."
MODULE_DEPENDS=()
_SDDM_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_sddm_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-sddm"; }
_sddm_source_dir() { printf '%s\n' "$_SDDM_MODULE_DIR/assets"; }
_sddm_config_source() { printf '%s\n' "$_SDDM_MODULE_DIR/config/90-atlas-theme.conf"; }
_sddm_theme_dir() { printf '%s\n' "/usr/share/sddm/themes/atlas"; }
_sddm_config_file() { printf '%s\n' "/etc/sddm.conf.d/90-atlas-theme.conf"; }
_sddm_run_privileged() { if os::is_root; then "$@"; else sudo "$@"; fi; }
_sddm_manifest_source() { (cd "$(_sddm_source_dir)" && find . -type f -print | sort | xargs sha256sum; sha256sum "$(_sddm_config_source)" | awk '{print $1"  ./90-atlas-theme.conf"}') 2>/dev/null; }
_sddm_manifest_current() { (cd "$(_sddm_theme_dir)" && find . -type f -print | sort | xargs sha256sum; sha256sum "$(_sddm_config_file)" | awk '{print $1"  ./90-atlas-theme.conf"}') 2>/dev/null; }
_sddm_marker_init() { _SDDM_MARKER_STATE=absent; }
_sddm_marker_load() { _sddm_marker_init; local marker="$(_sddm_marker)" line val s=0 t=0; [ -e "$marker" ] || return 0; [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || return 1; [ "$(stat -c '%a' "$marker" 2>/dev/null)" = 600 ] || return 1; while IFS= read -r line || [ -n "$line" ]; do line="${line%$'\r'}"; case "$line" in schema=1) s=1 ;; state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _SDDM_MARKER_STATE="$val" ;; *) return 1 ;; esac; t=1 ;; "") ;; *) return 1 ;; esac; done < "$marker"; [ "$s" -eq 1 ] && [ "$t" -eq 1 ]; }
_sddm_marker_write() { local state="$1" marker dir tmp; marker="$(_sddm_marker)"; dir="$(dirname "$marker")"; mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1; tmp="$(mktemp "$dir/.desktop-sddm.XXXXXX")" || return 1; { printf 'schema=1\nstate=%s\n' "$state"; } > "$tmp" || { rm -f "$tmp"; return 1; }; chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }; }
_sddm_matches() { [ -d "$(_sddm_theme_dir)" ] && [ -f "$(_sddm_config_file)" ] && [ "$(_sddm_manifest_source)" = "$(_sddm_manifest_current)" ]; }
_sddm_write() { local theme="$(_sddm_theme_dir)" conf="$(_sddm_config_file)" tmp parent; parent="$(dirname "$theme")"; _sddm_run_privileged mkdir -p "$parent" "$(dirname "$conf")" || return 1; tmp="$(_sddm_run_privileged mktemp -d "$parent/.atlas-sddm.XXXXXX")" || return 1; _sddm_run_privileged cp "$(_sddm_source_dir)"/* "$tmp"/ || { _sddm_run_privileged rm -rf "$tmp" 2>/dev/null || true; return 1; }; _sddm_run_privileged chmod 755 "$tmp" || { _sddm_run_privileged rm -rf "$tmp" 2>/dev/null || true; return 1; }; _sddm_run_privileged chmod 644 "$tmp"/* || { _sddm_run_privileged rm -rf "$tmp" 2>/dev/null || true; return 1; }; _sddm_run_privileged rm -rf "$theme" || { _sddm_run_privileged rm -rf "$tmp" 2>/dev/null || true; return 1; }; _sddm_run_privileged mv "$tmp" "$theme" || return 1; _sddm_run_privileged cp "$(_sddm_config_source)" "$conf" || return 1; _sddm_run_privileged chmod 644 "$conf"; }
module::check() { _sddm_marker_load || return 1; [ "$_SDDM_MARKER_STATE" = installed ] || return 1; _sddm_matches; }
module::install() { os::is_fedora || return 1; _sddm_marker_load || return 1; case "$_SDDM_MARKER_STATE" in absent|detached) [ ! -e "$(_sddm_theme_dir)" ] && [ ! -e "$(_sddm_config_file)" ] || return 1 ;; esac; _sddm_marker_write installing || return 1; _sddm_write || return 1; _sddm_matches || return 1; _sddm_marker_write installed; }
module::verify() { _sddm_marker_load || return 1; case "$_SDDM_MARKER_STATE" in absent|detached) return 0 ;; installing) return 1 ;; esac; _sddm_matches; }
module::update() { _sddm_marker_load || return 1; case "$_SDDM_MARKER_STATE" in absent|detached) return 0 ;; esac; _sddm_write || return 1; _sddm_marker_write installed; }
module::remove() { _sddm_marker_load || return 1; case "$_SDDM_MARKER_STATE" in absent|detached) return 0 ;; esac; _sddm_matches || return 1; _sddm_run_privileged rm -rf "$(_sddm_theme_dir)" "$(_sddm_config_file)" || return 1; _sddm_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/sddm is reconstructable"; }
module::restore() { log::info "nothing to restore: reinstall desktop/sddm"; }
