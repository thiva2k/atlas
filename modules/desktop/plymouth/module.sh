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
module::check() { _plymouth_marker_load || return 1; [ "$_PLYMOUTH_MARKER_STATE" = installed ] || return 1; _plymouth_matches; }
module::install() { os::is_fedora || return 1; _plymouth_marker_load || return 1; case "$_PLYMOUTH_MARKER_STATE" in absent|detached) [ ! -e "$(_plymouth_theme_dir)" ] || return 1 ;; esac; _plymouth_marker_write installing || return 1; _plymouth_write || return 1; _plymouth_matches || return 1; _plymouth_marker_write installed; }
module::verify() { _plymouth_marker_load || return 1; case "$_PLYMOUTH_MARKER_STATE" in absent|detached) return 0 ;; installing) return 1 ;; esac; _plymouth_matches; }
module::update() { _plymouth_marker_load || return 1; case "$_PLYMOUTH_MARKER_STATE" in absent|detached) return 0 ;; esac; _plymouth_write || return 1; _plymouth_marker_write installed; }
module::remove() { _plymouth_marker_load || return 1; case "$_PLYMOUTH_MARKER_STATE" in absent|detached) return 0 ;; esac; _plymouth_matches || return 1; _plymouth_run_privileged rm -rf "$(_plymouth_theme_dir)" || return 1; _plymouth_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/plymouth is reconstructable"; }
module::restore() { log::info "nothing to restore: reinstall desktop/plymouth"; }
