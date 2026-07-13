#!/usr/bin/env bash
# desktop/notifications - RFC-0023.
MODULE_NAME="notifications"
MODULE_DESCRIPTION="Notifications: applies Atlas-owned quiet notification defaults."
MODULE_DEPENDS=()
_NOTIFICATIONS_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_NOTIFICATIONS_ABSENT="__ATLAS_NOTIFICATIONS_ABSENT__"
_notifications_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-notifications"; }
_notifications_profile() { printf '%s\n' "$_NOTIFICATIONS_MODULE_DIR/profile.tsv"; }
_notifications_has_tools() { os::has_cmd kreadconfig6 && os::has_cmd kwriteconfig6; }
_notifications_marker_init() { _NOTIFICATIONS_MARKER_STATE=absent; }
_notifications_marker_load() { _notifications_marker_init; local marker="$(_notifications_marker)" line val s=0 t=0; [ -e "$marker" ] || return 0; [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || return 1; [ "$(stat -c '%a' "$marker" 2>/dev/null)" = 600 ] || return 1; while IFS= read -r line || [ -n "$line" ]; do line="${line%$'\r'}"; case "$line" in schema=1) s=1 ;; state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _NOTIFICATIONS_MARKER_STATE="$val" ;; *) return 1 ;; esac; t=1 ;; "") ;; *) return 1 ;; esac; done < "$marker"; [ "$s" -eq 1 ] && [ "$t" -eq 1 ]; }
_notifications_marker_write() { local state="$1" marker dir tmp; marker="$(_notifications_marker)"; dir="$(dirname "$marker")"; mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1; tmp="$(mktemp "$dir/.desktop-notifications.XXXXXX")" || return 1; { printf 'schema=1\nstate=%s\n' "$state"; } > "$tmp" || { rm -f "$tmp"; return 1; }; chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }; mv -f "$tmp" "$marker" || { rm -f "$tmp"; return 1; }; }
_notifications_read_value() { kreadconfig6 --file "$1" --group "$2" --key "$3" --default "$5"; }
_notifications_write_value() { if [ "$4" = bool ]; then kwriteconfig6 --file "$1" --group "$2" --key "$3" --type bool "$5"; else kwriteconfig6 --file "$1" --group "$2" --key "$3" "$5"; fi; }
_notifications_delete_value() { if [ "$4" = bool ]; then kwriteconfig6 --file "$1" --group "$2" --key "$3" --type bool --delete ""; else kwriteconfig6 --file "$1" --group "$2" --key "$3" --delete ""; fi; }
_notifications_each() { local cb="$1" f g k ty v; while IFS='|' read -r f g k ty v || [ -n "${f:-}${g:-}${k:-}${ty:-}${v:-}" ]; do [ -z "${f:-}" ] && continue; "$cb" "$f" "$g" "$k" "$ty" "$v" || return 1; done < "$(_notifications_profile)"; }
_notifications_absent_one() { [ "$(_notifications_read_value "$1" "$2" "$3" "$4" "$_NOTIFICATIONS_ABSENT")" = "$_NOTIFICATIONS_ABSENT" ]; }
_notifications_apply_one() { [ "$(_notifications_read_value "$1" "$2" "$3" "$4" "$_NOTIFICATIONS_ABSENT")" = "$5" ] || _notifications_write_value "$1" "$2" "$3" "$4" "$5"; }
_notifications_verify_one() { [ "$(_notifications_read_value "$1" "$2" "$3" "$4" "$_NOTIFICATIONS_ABSENT")" = "$5" ]; }
_notifications_delete_one() { _notifications_delete_value "$1" "$2" "$3" "$4"; }
module::check() { _notifications_marker_load || return 1; [ "$_NOTIFICATIONS_MARKER_STATE" = installed ] || return 1; _notifications_has_tools || return 1; _notifications_each _notifications_verify_one; }
module::install() { os::is_fedora || return 1; _notifications_has_tools || return 1; _notifications_marker_load || return 1; case "$_NOTIFICATIONS_MARKER_STATE" in absent|detached) _notifications_each _notifications_absent_one || return 1 ;; esac; _notifications_marker_write installing || return 1; _notifications_each _notifications_apply_one || return 1; _notifications_each _notifications_verify_one || return 1; _notifications_marker_write installed; }
module::verify() { _notifications_marker_load || return 1; case "$_NOTIFICATIONS_MARKER_STATE" in absent|detached) return 0 ;; installing) return 1 ;; esac; _notifications_has_tools || return 1; _notifications_each _notifications_verify_one; }
module::update() { _notifications_marker_load || return 1; case "$_NOTIFICATIONS_MARKER_STATE" in absent|detached) return 0 ;; esac; _notifications_each _notifications_apply_one || return 1; _notifications_marker_write installed; }
module::remove() { _notifications_marker_load || return 1; case "$_NOTIFICATIONS_MARKER_STATE" in absent|detached) return 0 ;; esac; _notifications_each _notifications_verify_one || return 1; _notifications_each _notifications_delete_one || return 1; _notifications_marker_write detached; }
module::backup() { log::info "nothing to back up: desktop/notifications is reconstructable"; }
module::restore() { log::info "nothing to restore: reinstall desktop/notifications"; }
