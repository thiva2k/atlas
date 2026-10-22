#!/usr/bin/env bash
# desktop/power - RFC-0022

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
KDE_STATE="$HOME/kde.state"; export KDE_STATE; : > "$KDE_STATE"
source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/os.sh"; source "$ATLAS_ROOT/modules/desktop/power/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
_power_has_tools() { [ "${TOOLS_OK:-1}" = 1 ]; }
_power_record() { printf "%s|%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" "$5"; }
_power_read_value() { local line; line="$(grep -F "$1|$2|$3|$4|" "$KDE_STATE" | tail -n 1 || true)"; [ -n "$line" ] || { printf "%s\n" "$5"; return 0; }; printf "%s\n" "${line#"$1|$2|$3|$4|"}"; }
_power_write_value() { grep -Fv "$1|$2|$3|$4|" "$KDE_STATE" > "$KDE_STATE.tmp" || true; mv "$KDE_STATE.tmp" "$KDE_STATE"; _power_record "$1" "$2" "$3" "$4" "$5" >> "$KDE_STATE"; }
_power_delete_value() { grep -Fv "$1|$2|$3|$4|" "$KDE_STATE" > "$KDE_STATE.tmp" || true; mv "$KDE_STATE.tmp" "$KDE_STATE"; }
'
PRE="${PRE%$'\n'}"

assert_status "power verify passes before install" 0 bash -c "$PRE; module::verify"
assert_status "power install refuses existing key before mutation" 1 bash -c "$PRE; _power_record powerdevilrc AC powerProfile string performance > \"\$KDE_STATE\"; module::install"
assert_status "power install writes balanced and saver profiles" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF \"powerdevilrc|AC|powerProfile|string|balanced\" \"\$KDE_STATE\"; grep -qxF \"powerdevilrc|Battery|powerProfile|string|power-saver\" \"\$KDE_STATE\"; module::verify"
assert_status "power update restores drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; grep -Fv \"powerdevilrc|AC|powerProfile|string|\" \"\$KDE_STATE\" > \"\$KDE_STATE.tmp\"; mv \"\$KDE_STATE.tmp\" \"\$KDE_STATE\"; _power_record powerdevilrc AC powerProfile string performance >> \"\$KDE_STATE\"; module::update >/dev/null 2>&1; module::verify"
assert_status "power remove detaches and deletes keys" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_power_marker)\"; [ ! -s \"\$KDE_STATE\" ]"
assert_status "power backup no-op" 0 bash -c "$PRE; module::backup"
assert_status "power restore no-op" 0 bash -c "$PRE; module::restore"

# Regression guard (pre-v1.0.1): the tests above MOCK the kread/kwriteconfig6
# helpers, so they never exercised `--type bool`. A bool row (e.g. batterySaver)
# must round-trip through the REAL helpers: a present bool reads back as the
# literal true/false, and an absent key returns the Atlas sentinel. Reintroducing
# `--type bool` on the READ path breaks both (present -> "", absent -> off-sentinel),
# which would make verify always fail and install refuse a fresh machine.
if command -v kreadconfig6 >/dev/null 2>&1 && command -v kwriteconfig6 >/dev/null 2>&1; then
  assert_status "power bool row round-trips through the real kconfig helpers" 0 bash -c '
    set -euo pipefail
    source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/log.sh"
    source "$ATLAS_ROOT/internal/os.sh"; source "$ATLAS_ROOT/modules/desktop/power/module.sh"
    f="$(mktemp)"; trap "rm -f \"$f\"" EXIT
    _power_write_value "$f" AC batterySaver bool true
    [ "$(_power_read_value "$f" AC batterySaver bool "$_POWER_ABSENT")" = "true" ]
    [ "$(_power_read_value "$f" AC missingKey  bool "$_POWER_ABSENT")" = "$_POWER_ABSENT" ]
  '
else
  _t_ok "power bool round-trip skipped (kreadconfig6/kwriteconfig6 not installed)"
fi

