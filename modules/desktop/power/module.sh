#!/usr/bin/env bash
# desktop/power - RFC-0022.
MODULE_NAME="power"
MODULE_DESCRIPTION="Power: applies conservative developer-laptop power defaults."
MODULE_DEPENDS=()
_POWER_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_POWER_ABSENT="__ATLAS_POWER_ABSENT__"
_power_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-power"; }
_power_profile() { printf '%s\n' "$_POWER_MODULE_DIR/profile.tsv"; }
_power_has_tools() { os::has_cmd kreadconfig6 && os::has_cmd kwriteconfig6; }
_power_marker_init() { _POWER_MARKER_STATE=absent; }
_power_marker_load() { _power_marker_init; local marker="$(_power_marker)" line val s=0 t=0; [ -e "$marker" ] || return 0; [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || return 1; [ "$(stat -c '%a' "$marker" 2>/dev/null)" = 600 ] || return 1; while IFS= read -r line || [ -n "$line" ]; do line="${line%$'\r'}"; case "$line" in schema=1) s=1 ;; state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _POWER_MARKER_STATE="$val" ;; *) return 1 ;; esac; t=1 ;; "") ;; *) return 1 ;; esac; done < "$marker"; [ "$s" -eq 1 ] && [ "$t" -eq 1 ]; }
_power_marker_write() { local state="$1" marker dir tmp; marker="$(_power_marker)"; dir="$(dirname "$marker")"; mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1; tmp="$(mktemp "$dir/.desktop-power.XXXXXX")" || return 1; { printf 'schema=1\nstate=%s\n' "$state"; } > "$tmp" || { rm -f "$tmp"; return 1; }; chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }; }
# Reads never pass `--type bool`: kreadconfig6 validates a typed default and
# rejects the non-boolean Atlas sentinel, dropping a present bool to "" and an
# absent key off the sentinel — which would make verify always fail, apply never
# idempotent, and install refuse a fresh machine. A bool written with `--type
# bool` reads back as the literal string true/false, exactly what profile.tsv
# records, so a plain string read compares correctly. (Matches desktop/kde-profile.)
_power_read_value() { kreadconfig6 --file "$1" --group "$2" --key "$3" --default "$5"; }
_power_write_value() { if [ "$4" = bool ]; then kwriteconfig6 --file "$1" --group "$2" --key "$3" --type bool "$5"; else kwriteconfig6 --file "$1" --group "$2" --key "$3" "$5"; fi; }
_power_delete_value() { if [ "$4" = bool ]; then kwriteconfig6 --file "$1" --group "$2" --key "$3" --type bool --delete ""; else kwriteconfig6 --file "$1" --group "$2" --key "$3" --delete ""; fi; }
_power_each() { local cb="$1" f g k ty v; while IFS='|' read -r f g k ty v || [ -n "${f:-}${g:-}${k:-}${ty:-}${v:-}" ]; do [ -z "${f:-}" ] && continue; "$cb" "$f" "$g" "$k" "$ty" "$v" || return 1; done < "$(_power_profile)"; }
_power_absent_one() { [ "$(_power_read_value "$1" "$2" "$3" "$4" "$_POWER_ABSENT")" = "$_POWER_ABSENT" ]; }
_power_apply_one() { [ "$(_power_read_value "$1" "$2" "$3" "$4" "$_POWER_ABSENT")" = "$5" ] || _power_write_value "$1" "$2" "$3" "$4" "$5"; }
_power_verify_one() { [ "$(_power_read_value "$1" "$2" "$3" "$4" "$_POWER_ABSENT")" = "$5" ]; }
_power_delete_one() { _power_delete_value "$1" "$2" "$3" "$4"; }
module::check() { _power_marker_load || return 1; [ "$_POWER_MARKER_STATE" = installed ] || return 1; _power_has_tools || return 1; _power_each _power_verify_one; }
module::install() { os::is_fedora || return 1; _power_has_tools || return 1; _power_marker_load || return 1; case "$_POWER_MARKER_STATE" in absent|detached) _power_each _power_absent_one || return 1 ;; esac; _power_marker_write installing || return 1; _power_each _power_apply_one || return 1; _power_each _power_verify_one || return 1; _power_marker_write installed; }
module::verify() { _power_marker_load || return 1; case "$_POWER_MARKER_STATE" in absent|detached) return 0 ;; installing) return 1 ;; esac; _power_has_tools || return 1; _power_each _power_verify_one; }
module::update() { _power_marker_load || return 1; case "$_POWER_MARKER_STATE" in absent|detached) return 0 ;; esac; _power_each _power_apply_one || return 1; _power_marker_write installed; }
module::remove() { _power_marker_load || return 1; case "$_POWER_MARKER_STATE" in absent|detached) return 0 ;; esac; _power_each _power_verify_one || return 1; _power_each _power_delete_one || return 1; _power_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/power is reconstructable"; }
module::restore() { log::info "nothing to restore: reinstall desktop/power"; }
