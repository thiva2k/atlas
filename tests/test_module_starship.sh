#!/usr/bin/env bash
# development/starship - RFC-0011
#
# Tests sandbox HOME/XDG/ATLAS state and mock Starship. No test touches the
# user's default Starship config or shell startup files.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_CONFIG_HOME="$HOME/.config"; export XDG_CONFIG_HOME
ATLAS_CONFIG_HOME="$HOME/.config/atlas"; export ATLAS_CONFIG_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
STARSHIP_BIN="$HOME/bin/starship"; export STARSHIP_BIN
STARSHIP_ARGV_LOG="$HOME/starship.argv"; export STARSHIP_ARGV_LOG
STARSHIP_ENV_LOG="$HOME/starship.env"; export STARSHIP_ENV_LOG
: > "$STARSHIP_ARGV_LOG"; : > "$STARSHIP_ENV_LOG"
mkdir -p "$HOME/bin"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/starship/module.sh"

_starship_binary() { printf "%s\n" starship; }
_starship_user_config_file() { printf "%s\n" "$XDG_CONFIG_HOME/starship.toml"; }
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::has_cmd() {
  case "$1" in
    starship) [ -x "$STARSHIP_BIN" ] ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}
starship() {
  printf "%s\n" "$*" >> "$STARSHIP_ARGV_LOG"
  printf "STARSHIP_CONFIG=%s\n" "${STARSHIP_CONFIG:-}" >> "$STARSHIP_ENV_LOG"
  [ "${STARSHIP_FAIL:-0}" = 1 ] && return 1
  printf "starship mock\n"
}
'
PRE="${PRE%$'\n'}"
APPROVED_STARSHIP_FORMAT='$directory$git_branch$git_status$python$nodejs$docker_context$cmd_duration$time$line_break$character'
ALL_STARSHIP_FORMAT='$all'
export APPROVED_STARSHIP_FORMAT ALL_STARSHIP_FORMAT

assert_status "starship verify passes before install" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; : > \"\$STARSHIP_BIN\"; chmod +x \"\$STARSHIP_BIN\"; module::verify" 2>&1)"
assert_contains "starship verify treats unmanaged binary as user-owned" "$out" "not installed by Atlas"

assert_status "starship check fails before install" 1 \
  bash -c "$PRE; module::check"

assert_status "starship install refuses existing Atlas config before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$ATLAS_CONFIG_HOME/starship\"; printf \"format = \\\"user\\\"\n\" > \"\$ATLAS_CONFIG_HOME/starship/starship.toml\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_starship_marker)\" ]; exit \"\${rc:-0}\""

assert_status "starship install fails on non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_starship_marker)\" ]; exit \"\${rc:-0}\""

assert_status "starship install writes installed marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_starship_marker)\""

assert_status "starship install writes Atlas config" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -q \"format =\" \"\$ATLAS_CONFIG_HOME/starship/starship.toml\""

assert_status "starship config displays only approved modules" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cfg=\"\$ATLAS_CONFIG_HOME/starship/starship.toml\"; grep -qF \"\$APPROVED_STARSHIP_FORMAT\" \"\$cfg\"; ! grep -qF \"\$ALL_STARSHIP_FORMAT\" \"\$cfg\"; ! grep -q \"\\[custom\" \"\$cfg\""

assert_status "starship user default config is preserved" 0 \
  bash -c "$PRE; mkdir -p \"\$XDG_CONFIG_HOME\"; printf \"format = \\\"mine\\\"\n\" > \"\$XDG_CONFIG_HOME/starship.toml\"; module::install >/dev/null 2>&1; grep -qxF \"format = \\\"mine\\\"\" \"\$XDG_CONFIG_HOME/starship.toml\""

assert_status "starship validates with STARSHIP_CONFIG when binary exists" 0 \
  bash -c "$PRE; : > \"\$STARSHIP_BIN\"; chmod +x \"\$STARSHIP_BIN\"; module::install >/dev/null 2>&1; grep -qxF \"prompt\" \"\$STARSHIP_ARGV_LOG\"; grep -qxF \"STARSHIP_CONFIG=\$ATLAS_CONFIG_HOME/starship/starship.toml\" \"\$STARSHIP_ENV_LOG\""

assert_status "starship verify passes after install without binary" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"

assert_status "starship check passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::check"

assert_status "starship repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_starship_marker)\" \"\$HOME/marker1\"; cp \"\$ATLAS_CONFIG_HOME/starship/starship.toml\" \"\$HOME/config1\"; module::install >/dev/null 2>&1; module::verify; cmp -s \"\$HOME/marker1\" \"\$(_starship_marker)\"; cmp -s \"\$HOME/config1\" \"\$ATLAS_CONFIG_HOME/starship/starship.toml\""

assert_status "starship repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "starship verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_starship_marker)\")\"; printf \"state=installed\n\" > \"\$(_starship_marker)\"; module::verify"

assert_status "starship verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _starship_marker_write installed; chmod 644 \"\$(_starship_marker)\"; module::verify"

assert_status "starship verify fails when marker hash is truncated" 1 \
  bash -c "$PRE; _starship_marker_write installed; sed -i \"s/^config_sha256=.*/config_sha256=deadbeef/\" \"\$(_starship_marker)\"; module::verify"

assert_status "starship verify fails on installing marker" 1 \
  bash -c "$PRE; _starship_marker_write installing; module::verify"

assert_status "starship verify fails when managed config drifts" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"drift\n\" >> \"\$ATLAS_CONFIG_HOME/starship/starship.toml\"; module::verify"

assert_status "starship verify fails when command rejects config" 1 \
  bash -c "$PRE; : > \"\$STARSHIP_BIN\"; chmod +x \"\$STARSHIP_BIN\"; module::install >/dev/null 2>&1; STARSHIP_FAIL=1; export STARSHIP_FAIL; module::verify"

assert_status "starship update restores managed config drift" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"drift\n\" >> \"\$ATLAS_CONFIG_HOME/starship/starship.toml\"; module::update >/dev/null 2>&1; module::verify"

assert_status "starship remove detaches and deletes only Atlas config" 0 \
  bash -c "$PRE; mkdir -p \"\$XDG_CONFIG_HOME\"; printf \"format = \\\"mine\\\"\n\" > \"\$XDG_CONFIG_HOME/starship.toml\"; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_starship_marker)\"; [ ! -e \"\$ATLAS_CONFIG_HOME/starship/starship.toml\" ]; grep -qxF \"format = \\\"mine\\\"\" \"\$XDG_CONFIG_HOME/starship.toml\""

assert_status "starship remove is idempotent after detach" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; module::remove"

assert_status "starship detached reinstall refuses user-created Atlas config" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; mkdir -p \"\$ATLAS_CONFIG_HOME/starship\"; printf \"format = \\\"user\\\"\n\" > \"\$ATLAS_CONFIG_HOME/starship/starship.toml\"; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF \"format = \\\"user\\\"\" \"\$ATLAS_CONFIG_HOME/starship/starship.toml\"; exit \"\${rc:-0}\""

assert_status "starship remove refuses drifted config" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"drift\n\" >> \"\$ATLAS_CONFIG_HOME/starship/starship.toml\"; module::remove"

assert_status "starship backup is a documented no-op" 0 \
  bash -c "$PRE; module::backup"

assert_status "starship restore is a documented no-op" 0 \
  bash -c "$PRE; module::restore"

assert_status "starship runner verify succeeds before install" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run verify development/starship"

assert_status "starship runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor development/starship"
