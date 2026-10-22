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

# Regression guard (pre-v1.0.1): the tests above replace _power_read/write_value,
# so they never exercised `--type bool`. A present bool must read back as
# true/false and an absent key must return the Atlas sentinel. `--type bool` on
# the read rejects the non-boolean sentinel (present -> "", absent -> off-sentinel).
# Same typed-default rejection as notifications and kde-profile; the store is
# only there so a written bool is not echoed back as --default.
PRE_PROD_READ='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"; source "$ATLAS_ROOT/modules/desktop/power/module.sh"
KCFG="$HOME/kcfg"; : > "$KCFG"
kwriteconfig6() {
  local file="" group="" key="" val=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --file) file="$2"; shift 2 ;;
      --group) group="$2"; shift 2 ;;
      --key) key="$2"; shift 2 ;;
      --type) shift 2 ;;
      --delete) shift ;;
      *) val="$1"; shift ;;
    esac
  done
  grep -Fv "$file|$group|$key|" "$KCFG" > "$KCFG.tmp" || true
  mv "$KCFG.tmp" "$KCFG"
  printf "%s|%s|%s|%s\n" "$file" "$group" "$key" "$val" >> "$KCFG"
}
kreadconfig6() {
  local default="" type="" file="" group="" key="" arg line
  while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --default) default="$2"; shift 2 ;;
      --type) type="$2"; shift 2 ;;
      --file) file="$2"; shift 2 ;;
      --group) group="$2"; shift 2 ;;
      --key) key="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [ "$type" = bool ]; then
    case "$default" in true|false) ;; *) return 64 ;; esac
  fi
  line="$(grep -F "$file|$group|$key|" "$KCFG" | tail -n 1 || true)"
  if [ -n "$line" ]; then printf "%s\n" "${line#"$file|$group|$key|"}"; else printf "%s\n" "$default"; fi
}
'
PRE_PROD_READ="${PRE_PROD_READ%$'\n'}"

assert_status "power bool row round-trips through kconfig helpers" 0 \
  bash -c "$PRE_PROD_READ; f=\"\$HOME/powerdevilrc\"; _power_write_value \"\$f\" AC batterySaver bool true; [ \"\$(_power_read_value \"\$f\" AC batterySaver bool \"\$_POWER_ABSENT\")\" = \"true\" ]; [ \"\$(_power_read_value \"\$f\" AC missingKey bool \"\$_POWER_ABSENT\")\" = \"\$_POWER_ABSENT\" ]"

