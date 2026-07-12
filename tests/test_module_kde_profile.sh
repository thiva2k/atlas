#!/usr/bin/env bash
# desktop/kde-profile - RFC-0012
#
# Tests mock KConfig reads/writes. No test touches the user's KDE config.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
KDE_STATE="$HOME/kde.state"; export KDE_STATE
KDE_LOG="$HOME/kde.log"; export KDE_LOG
: > "$KDE_STATE"; : > "$KDE_LOG"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/kde-profile/module.sh"

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
_kde_profile_has_tools() { [ "${TOOLS_OK:-1}" = 1 ]; }
_kde_profile_record() { printf "%s|%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" "$5"; }
_kde_profile_read_value() {
  [ "${READ_FAIL:-0}" = 1 ] && return 1
  local file="$1" group="$2" key="$3" type="$4" default="$5" line
  line="$(grep -F "$file|$group|$key|$type|" "$KDE_STATE" | tail -n 1 || true)"
  [ -n "$line" ] || { printf "%s\n" "$default"; return 0; }
  printf "%s\n" "${line#"$file|$group|$key|$type|"}"
}
_kde_profile_write_value() {
  [ "${WRITE_FAIL:-0}" = 1 ] && return 1
  local file="$1" group="$2" key="$3" type="$4" value="$5" tmp
  tmp="$KDE_STATE.tmp"
  grep -Fv "$file|$group|$key|$type|" "$KDE_STATE" > "$tmp" || true
  mv "$tmp" "$KDE_STATE"
  _kde_profile_record "$file" "$group" "$key" "$type" "$value" >> "$KDE_STATE"
  printf "write|%s|%s|%s|%s|%s\n" "$file" "$group" "$key" "$type" "$value" >> "$KDE_LOG"
}
_kde_profile_delete_value() {
  local file="$1" group="$2" key="$3" type="$4" tmp
  tmp="$KDE_STATE.tmp"
  grep -Fv "$file|$group|$key|$type|" "$KDE_STATE" > "$tmp" || true
  mv "$tmp" "$KDE_STATE"
  printf "delete|%s|%s|%s|%s\n" "$file" "$group" "$key" "$type" >> "$KDE_LOG"
}
'
PRE="${PRE%$'\n'}"

assert_status "kde-profile verify passes before install" 0 \
  bash -c "$PRE; module::verify"

assert_status "kde-profile check fails before install" 1 \
  bash -c "$PRE; module::check"

assert_status "kde-profile install refuses existing user key before mutation" 1 \
  bash -c "$PRE; _kde_profile_record kwinrc Plugins blurEnabled bool true > \"\$KDE_STATE\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_kde_profile_marker)\" ]; [ ! -s \"\$KDE_LOG\" ]; exit \"\${rc:-0}\""

assert_status "kde-profile install fails on non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_kde_profile_marker)\" ]; [ ! -s \"\$KDE_LOG\" ]; exit \"\${rc:-0}\""

assert_status "kde-profile install fails when KConfig tools are missing before mutation" 1 \
  bash -c "$PRE; TOOLS_OK=0; export TOOLS_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_kde_profile_marker)\" ]; [ ! -s \"\$KDE_LOG\" ]; exit \"\${rc:-0}\""

assert_status "kde-profile install writes installed marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_kde_profile_marker)\""

assert_status "kde-profile install writes managed KConfig keys" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF \"kwinrc|Plugins|blurEnabled|bool|false\" \"\$KDE_STATE\"; grep -qxF \"kdeglobals|KDE|AnimationDurationFactor|string|0.5\" \"\$KDE_STATE\""

assert_status "kde-profile verify passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"

assert_status "kde-profile check passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::check"

assert_status "kde-profile repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_kde_profile_marker)\" \"\$HOME/marker1\"; cp \"\$KDE_STATE\" \"\$HOME/state1\"; module::install >/dev/null 2>&1; module::verify; cmp -s \"\$HOME/marker1\" \"\$(_kde_profile_marker)\"; cmp -s \"\$HOME/state1\" \"\$KDE_STATE\""

assert_status "kde-profile repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "kde-profile verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_kde_profile_marker)\")\"; printf \"state=installed\n\" > \"\$(_kde_profile_marker)\"; module::verify"

assert_status "kde-profile verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _kde_profile_marker_write installed; chmod 644 \"\$(_kde_profile_marker)\"; module::verify"

assert_status "kde-profile verify fails on installing marker" 1 \
  bash -c "$PRE; _kde_profile_marker_write installing; module::verify"

assert_status "kde-profile verify fails when managed key drifts" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -Fv \"kwinrc|Plugins|blurEnabled|bool|\" \"\$KDE_STATE\" > \"\$KDE_STATE.tmp\"; mv \"\$KDE_STATE.tmp\" \"\$KDE_STATE\"; _kde_profile_record kwinrc Plugins blurEnabled bool true >> \"\$KDE_STATE\"; module::verify"

assert_status "kde-profile update restores managed key drift" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -Fv \"kwinrc|Plugins|blurEnabled|bool|\" \"\$KDE_STATE\" > \"\$KDE_STATE.tmp\"; mv \"\$KDE_STATE.tmp\" \"\$KDE_STATE\"; _kde_profile_record kwinrc Plugins blurEnabled bool true >> \"\$KDE_STATE\"; module::update >/dev/null 2>&1; module::verify"

assert_status "kde-profile remove detaches and deletes only managed keys" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_kde_profile_marker)\"; [ ! -s \"\$KDE_STATE\" ]; grep -q \"delete|kwinrc|Plugins|blurEnabled|bool\" \"\$KDE_LOG\""

assert_status "kde-profile remove is idempotent after detach" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; module::remove"

assert_status "kde-profile detached reinstall refuses user-created key" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; _kde_profile_record kwinrc Plugins blurEnabled bool true > \"\$KDE_STATE\"; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF \"kwinrc|Plugins|blurEnabled|bool|true\" \"\$KDE_STATE\"; exit \"\${rc:-0}\""

assert_status "kde-profile remove refuses drifted key" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -Fv \"kwinrc|Plugins|blurEnabled|bool|\" \"\$KDE_STATE\" > \"\$KDE_STATE.tmp\"; mv \"\$KDE_STATE.tmp\" \"\$KDE_STATE\"; _kde_profile_record kwinrc Plugins blurEnabled bool true >> \"\$KDE_STATE\"; module::remove"

assert_status "kde-profile backup is a documented no-op" 0 \
  bash -c "$PRE; module::backup"

assert_status "kde-profile restore is a documented no-op" 0 \
  bash -c "$PRE; module::restore"

assert_status "kde-profile runner verify succeeds before install" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run verify desktop/kde-profile"

assert_status "kde-profile runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor desktop/kde-profile"
