#!/usr/bin/env bash
# desktop/notifications - RFC-0023

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
KDE_STATE="$HOME/kde.state"; export KDE_STATE; : > "$KDE_STATE"
source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/os.sh"; source "$ATLAS_ROOT/modules/desktop/notifications/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
_notifications_has_tools() { [ "${TOOLS_OK:-1}" = 1 ]; }
_notifications_record() { printf "%s|%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" "$5"; }
_notifications_read_value() { local line; line="$(grep -F "$1|$2|$3|$4|" "$KDE_STATE" | tail -n 1 || true)"; [ -n "$line" ] || { printf "%s\n" "$5"; return 0; }; printf "%s\n" "${line#"$1|$2|$3|$4|"}"; }
_notifications_write_value() { grep -Fv "$1|$2|$3|$4|" "$KDE_STATE" > "$KDE_STATE.tmp" || true; mv "$KDE_STATE.tmp" "$KDE_STATE"; _notifications_record "$1" "$2" "$3" "$4" "$5" >> "$KDE_STATE"; }
_notifications_delete_value() { grep -Fv "$1|$2|$3|$4|" "$KDE_STATE" > "$KDE_STATE.tmp" || true; mv "$KDE_STATE.tmp" "$KDE_STATE"; }
'
PRE="${PRE%$'\n'}"

assert_status "notifications verify passes before install" 0 bash -c "$PRE; module::verify"
assert_status "notifications install refuses existing key" 1 bash -c "$PRE; _notifications_record plasmanotifyrc Notifications LowPriorityPopups bool true > \"\$KDE_STATE\"; module::install"
assert_status "notifications install writes quiet profile" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF \"plasmanotifyrc|Notifications|LowPriorityPopups|bool|false\" \"\$KDE_STATE\"; grep -qxF \"plasmanotifyrc|Notifications|CriticalAlwaysOnTop|bool|true\" \"\$KDE_STATE\"; module::verify"
assert_status "notifications update restores drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -Fv \"plasmanotifyrc|Notifications|LowPriorityPopups|bool|\" \"\$KDE_STATE\" > \"\$KDE_STATE.tmp\"; mv \"\$KDE_STATE.tmp\" \"\$KDE_STATE\"; _notifications_record plasmanotifyrc Notifications LowPriorityPopups bool true >> \"\$KDE_STATE\"; module::update >/dev/null 2>&1; module::verify"
assert_status "notifications remove detaches and deletes keys" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_notifications_marker)\"; [ ! -s \"\$KDE_STATE\" ]"
assert_status "notifications backup no-op" 0 bash -c "$PRE; module::backup"
assert_status "notifications restore no-op" 0 bash -c "$PRE; module::restore"

