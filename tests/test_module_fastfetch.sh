#!/usr/bin/env bash
# desktop/fastfetch - RFC-0010
#
# Tests mock DNF and Fastfetch and redirect the system config path into a
# sandbox. No test writes /etc or touches user Fastfetch config.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
FASTFETCH_CONFIG="$HOME/etc/xdg/fastfetch/config.jsonc"; export FASTFETCH_CONFIG
FASTFETCH_BIN="$HOME/bin/fastfetch"; export FASTFETCH_BIN
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
FASTFETCH_ARGV_LOG="$HOME/fastfetch.argv"; export FASTFETCH_ARGV_LOG
: > "$DNF_LOG"; : > "$FASTFETCH_ARGV_LOG"
mkdir -p "$HOME/bin" "$(dirname "$FASTFETCH_CONFIG")"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/fastfetch/module.sh"

_fastfetch_config_file() { printf "%s\n" "$FASTFETCH_CONFIG"; }
_fastfetch_binary() { printf "%s\n" fastfetch; }
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::has_cmd() {
  case "$1" in
    fastfetch) [ -x "$FASTFETCH_BIN" ] ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}
os::dnf_install() {
  printf "%s\n" "$*" >> "$DNF_LOG"
  [ "${DNF_FAIL:-0}" = 1 ] && return 1
  if [ "$1" = fastfetch ]; then
    printf "#!/usr/bin/env bash\nprintf \"fastfetch mock\\n\"\n" > "$FASTFETCH_BIN"
    chmod +x "$FASTFETCH_BIN"
  fi
}
fastfetch() {
  printf "%s\n" "$*" >> "$FASTFETCH_ARGV_LOG"
  [ "${FASTFETCH_FAIL:-0}" = 1 ] && return 1
  printf "Atlas Workstation\n"
}
'
PRE="${PRE%$'\n'}"

assert_status "fastfetch verify passes before install" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; : > \"\$FASTFETCH_BIN\"; chmod +x \"\$FASTFETCH_BIN\"; module::verify" 2>&1)"
assert_contains "fastfetch verify treats unmanaged binary as user-owned" "$out" "not installed by Atlas"

assert_status "fastfetch check fails before install" 1 \
  bash -c "$PRE; module::check"

assert_status "fastfetch install refuses existing system config before mutation" 1 \
  bash -c "$PRE; printf \"user config\n\" > \"\$FASTFETCH_CONFIG\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_fastfetch_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "fastfetch install fails on non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_fastfetch_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_eq "fastfetch install uses exact package" \
  "$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")" "fastfetch"

assert_status "fastfetch install writes installed marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_fastfetch_marker)\""

assert_status "fastfetch install writes the Atlas config" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -q \"workstation · online\" \"\$FASTFETCH_CONFIG\"; grep -q \"ATLAS ✓\" \"\$FASTFETCH_CONFIG\""

# RFC-0034: the SYSTEM ONLINE greeting — a fast telemetry readout (host/kernel/
# uptime/shell) with the tool checks collapsed into ONE line, and the orbital-A
# mark rendered in ASCII. No heavy hardware dump (cpu/gpu), no per-tool row wall.
assert_status "fastfetch config is the SYSTEM ONLINE greeting" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; c=\"\$FASTFETCH_CONFIG\"; grep -q '\"kernel\"' \"\$c\"; grep -q '\"uptime\"' \"\$c\"; grep -q '\"shell\"' \"\$c\"; grep -q 'ATLAS ✓' \"\$c\"; grep -q 'python3 node docker claude git' \"\$c\"; grep -q '◐' \"\$c\"; ! grep -q '\"cpu\"' \"\$c\"; ! grep -q '\"gpu\"' \"\$c\"; ! grep -q '✓ Codex' \"\$c\""

assert_status "fastfetch install validates with Atlas config" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF -- \"--config \$FASTFETCH_CONFIG\" \"\$FASTFETCH_ARGV_LOG\""

assert_status "fastfetch verify passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"

assert_status "fastfetch check passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::check"

assert_status "fastfetch repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_fastfetch_marker)\" \"\$HOME/marker1\"; cp \"\$FASTFETCH_CONFIG\" \"\$HOME/config1\"; module::install >/dev/null 2>&1; module::verify; cmp -s \"\$HOME/marker1\" \"\$(_fastfetch_marker)\"; cmp -s \"\$HOME/config1\" \"\$FASTFETCH_CONFIG\""

assert_status "fastfetch repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "fastfetch verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_fastfetch_marker)\")\"; printf \"state=installed\n\" > \"\$(_fastfetch_marker)\"; module::verify"

assert_status "fastfetch verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _fastfetch_marker_write installed; chmod 644 \"\$(_fastfetch_marker)\"; module::verify"

assert_status "fastfetch verify fails on installing marker" 1 \
  bash -c "$PRE; _fastfetch_marker_write installing; module::verify"

assert_status "fastfetch verify fails when managed config drifts" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"drift\n\" >> \"\$FASTFETCH_CONFIG\"; module::verify"

assert_status "fastfetch verify fails when command fails" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; FASTFETCH_FAIL=1; export FASTFETCH_FAIL; module::verify"

assert_status "fastfetch package failure leaves installing marker" 1 \
  bash -c "$PRE; DNF_FAIL=1; export DNF_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_fastfetch_marker)\"; exit \"\${rc:-0}\""

assert_status "fastfetch update restores managed config drift" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"drift\n\" >> \"\$FASTFETCH_CONFIG\"; module::update >/dev/null 2>&1; module::verify"

# RFC-0034: in-place upgrade. When Atlas's OWN managed config changes after
# install, the marker's recorded config_sha256 no longer matches the new source.
# marker-load must NOT hard-fail on that (the fixed bug); update reconciles the
# config AND refreshes the marker hash.
assert_status "fastfetch marker-load tolerates a changed source hash (in-place upgrade)" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; m=\"\$(_fastfetch_marker)\"; sed -i 's/^config_sha256=.*/config_sha256=0000000000000000000000000000000000000000000000000000000000000000/' \"\$m\"; chmod 600 \"\$m\"; _fastfetch_marker_load; [ \"\$_FASTFETCH_MARKER_STATE\" = installed ]"
assert_status "fastfetch update reconciles a source change and refreshes the marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; m=\"\$(_fastfetch_marker)\"; sed -i 's/^config_sha256=.*/config_sha256=0000000000000000000000000000000000000000000000000000000000000000/' \"\$m\"; chmod 600 \"\$m\"; printf 'drift\\n' >> \"\$FASTFETCH_CONFIG\"; module::update >/dev/null 2>&1; module::verify >/dev/null 2>&1; grep -qxF \"config_sha256=\$(_fastfetch_sha256 \"\$(_fastfetch_config_source)\")\" \"\$m\""

assert_status "fastfetch remove detaches and deletes only Atlas config" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_fastfetch_marker)\"; [ ! -e \"\$FASTFETCH_CONFIG\" ]; [ -x \"\$FASTFETCH_BIN\" ]"

assert_status "fastfetch remove refuses drifted config" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"drift\n\" >> \"\$FASTFETCH_CONFIG\"; module::remove"

assert_status "fastfetch backup is a documented no-op" 0 \
  bash -c "$PRE; module::backup"

assert_status "fastfetch restore is a documented no-op" 0 \
  bash -c "$PRE; module::restore"

assert_status "fastfetch runner verify succeeds before install" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run verify desktop/fastfetch"
