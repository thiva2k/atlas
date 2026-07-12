#!/usr/bin/env bash
# development/node - RFC-0013
#
# Tests sandbox system paths and mock DNF/RPM. No test mutates the host Node.js,
# npm, DNF database, project dependencies, global packages, or /usr/bin.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/state"; export ATLAS_STATE_DIR
TEST_NODE_BIN="$HOME/usr/bin/node"; export TEST_NODE_BIN
TEST_NPM_BIN="$HOME/usr/bin/npm"; export TEST_NPM_BIN
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
RPM_LOG="$HOME/rpm.log"; export RPM_LOG
NODE_ARGV_LOG="$HOME/node.argv"; export NODE_ARGV_LOG
NPM_ARGV_LOG="$HOME/npm.argv"; export NPM_ARGV_LOG
: > "$DNF_LOG"; : > "$RPM_LOG"; : > "$NODE_ARGV_LOG"; : > "$NPM_ARGV_LOG"
mkdir -p "$HOME/bin" "$(dirname "$TEST_NODE_BIN")"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/node/module.sh"

_node_node_bin() { printf "%s\n" "$TEST_NODE_BIN"; }
_node_npm_bin() { printf "%s\n" "$TEST_NPM_BIN"; }

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::dnf_install() {
  printf "%s\n" "$*" >> "$DNF_LOG"
  if [ "${DNF_ASSERT_MARKER_INSTALLING:-0}" = 1 ]; then
    grep -qxF state=installing "$(_node_marker)" || return 1
  fi
  [ "${DNF_OK:-1}" = 1 ] || return 1
  RPM_INSTALLED="${RPM_INSTALLED:-} $*"; export RPM_INSTALLED
  _make_node
  _make_npm
}

rpm() {
  printf "%s\n" "$*" >> "$RPM_LOG"
  case "${1:-}" in
    -q)
      case " ${RPM_INSTALLED:-} " in *" ${2:-} "*) return 0 ;; *) return 1 ;; esac
      ;;
    -qf)
      case "${2:-}" in
        "$TEST_NODE_BIN")
          [ "${NODE_RPM_OWNER:-nodejs24-bin}" = none ] && return 1
          printf "%s-99.0.0-1.fc99.noarch\n" "${NODE_RPM_OWNER:-nodejs24-bin}"
          return 0
          ;;
        "$TEST_NPM_BIN")
          [ "${NPM_RPM_OWNER:-nodejs24-npm-bin}" = none ] && return 1
          printf "%s-99.0.0-1.fc99.noarch\n" "${NPM_RPM_OWNER:-nodejs24-npm-bin}"
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

_make_node() {
  mkdir -p "$(dirname "$TEST_NODE_BIN")"
  cat > "$TEST_NODE_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$NODE_ARGV_LOG"
[ "${NODE_OK:-1}" = 1 ] || exit 1
case "$*" in
  "--version") printf "%s\n" "${NODE_VERSION_OUTPUT:-v24.99.0}" ;;
esac
EOF
  chmod +x "$TEST_NODE_BIN"
}

_make_npm() {
  mkdir -p "$(dirname "$TEST_NPM_BIN")"
  cat > "$TEST_NPM_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$NPM_ARGV_LOG"
[ "${NPM_OK:-1}" = 1 ] || exit 1
case "$*" in
  "--version") printf "99.0.0\n" ;;
esac
EOF
  chmod +x "$TEST_NPM_BIN"
}

_node_ready() {
  RPM_INSTALLED="nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin"; export RPM_INSTALLED
  _make_node
  _make_npm
}

true
'
PRE="${PRE%$'\n'}"

assert_status "node verify passes before install with Node absent" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; _make_node; _make_npm; module::verify" 2>&1)"
assert_contains "node verify reports unmanaged runtime when marker is absent" "$out" "present but not installed by Atlas"

assert_status "node check fails before marker" 1 \
  bash -c "$PRE; module::check"

assert_status "node declares no Atlas module dependencies" 0 \
  bash -c "$PRE; [ \"\${#MODULE_DEPENDS[@]}\" -eq 0 ]"

assert_status "node verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_node_marker)\")\"; printf \"state=installed\n\" > \"\$(_node_marker)\"; chmod 600 \"\$(_node_marker)\"; module::verify"

assert_status "node verify fails on marker with unknown key" 1 \
  bash -c "$PRE; _node_marker_write installed; printf \"unexpected=value\n\" >> \"\$(_node_marker)\"; module::verify"

assert_status "node verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _node_marker_write installed; chmod 644 \"\$(_node_marker)\"; module::verify"

assert_status "node verify fails on installing marker" 1 \
  bash -c "$PRE; _node_marker_write installing; _node_ready; module::verify"

assert_status "node verify passes when managed runtime is healthy" 0 \
  bash -c "$PRE; _node_marker_write installed; _node_ready; module::verify"

for pkg in nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin; do
  assert_status "node verify fails when $pkg package is missing" 1 \
    bash -c "$PRE; _node_marker_write installed; _node_ready; RPM_INSTALLED=\"\${RPM_INSTALLED//$pkg/}\"; export RPM_INSTALLED; module::verify"
done

assert_status "node verify fails when node command is missing" 1 \
  bash -c "$PRE; _node_marker_write installed; _node_ready; rm -f \"\$TEST_NODE_BIN\"; module::verify"

assert_status "node verify fails when npm command is missing" 1 \
  bash -c "$PRE; _node_marker_write installed; _node_ready; rm -f \"\$TEST_NPM_BIN\"; module::verify"

assert_status "node verify fails when node command is not runnable" 1 \
  bash -c "$PRE; _node_marker_write installed; _node_ready; NODE_OK=0; export NODE_OK; module::verify"

assert_status "node verify fails when npm command is not runnable" 1 \
  bash -c "$PRE; _node_marker_write installed; _node_ready; NPM_OK=0; export NPM_OK; module::verify"

assert_status "node verify fails when node RPM owner is wrong" 1 \
  bash -c "$PRE; _node_marker_write installed; _node_ready; NODE_RPM_OWNER=evil-node; export NODE_RPM_OWNER; module::verify"

assert_status "node verify fails when npm RPM owner is wrong" 1 \
  bash -c "$PRE; _node_marker_write installed; _node_ready; NPM_RPM_OWNER=evil-npm; export NPM_RPM_OWNER; module::verify"

assert_status "node verify fails when Node major is wrong" 1 \
  bash -c "$PRE; _node_marker_write installed; _node_ready; NODE_VERSION_OUTPUT=v22.99.0; export NODE_VERSION_OUTPUT; module::verify"

assert_status "node install writes installing marker before DNF" 0 \
  bash -c "$PRE; DNF_ASSERT_MARKER_INSTALLING=1; export DNF_ASSERT_MARKER_INSTALLING; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_node_marker)\""

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")"
assert_eq "node install uses exact Fedora package set" "$out" "nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin"

assert_status "node install promotes marker only after validation" 1 \
  bash -c "$PRE; NPM_OK=0; export NPM_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_node_marker)\"; exit \"\${rc:-0}\""

assert_status "node install leaves installing marker after DNF failure" 1 \
  bash -c "$PRE; DNF_OK=0; export DNF_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_node_marker)\"; exit \"\${rc:-0}\""

assert_status "node install refuses non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_node_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "node install refuses non-executable system node before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_NODE_BIN\")\"; : > \"\$TEST_NODE_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_node_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "node install refuses wrong system node owner before mutation" 1 \
  bash -c "$PRE; _make_node; NODE_RPM_OWNER=evil-node; export NODE_RPM_OWNER; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_node_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "node install refuses non-executable system npm before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_NPM_BIN\")\"; : > \"\$TEST_NPM_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_node_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "node install refuses wrong system npm owner before mutation" 1 \
  bash -c "$PRE; _make_npm; NPM_RPM_OWNER=evil-npm; export NPM_RPM_OWNER; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_node_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "node install repairs installing marker" 0 \
  bash -c "$PRE; _node_marker_write installing; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_node_marker)\"; module::verify"

assert_status "node repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_node_marker)\" \"\$HOME/marker1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/marker1\" \"\$(_node_marker)\"; module::verify"

assert_status "node repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "node probes ignore hostile PATH shims" 0 \
  bash -c "$PRE; mkdir -p \"\$HOME/bin\"; printf \"#!/usr/bin/env bash\\nexit 99\\n\" > \"\$HOME/bin/node\"; printf \"#!/usr/bin/env bash\\nexit 99\\n\" > \"\$HOME/bin/npm\"; chmod +x \"\$HOME/bin/node\" \"\$HOME/bin/npm\"; PATH=\"\$HOME/bin:\$PATH\"; export PATH; module::install >/dev/null 2>&1; module::verify"

assert_status "node probes ignore hostile Node and npm environment" 0 \
  bash -c "$PRE; NODE_OPTIONS=\"--require /bad\"; NODE_PATH=/bad; NPM_CONFIG_USERCONFIG=/bad/npmrc; NPM_CONFIG_GLOBALCONFIG=/bad/global; NPM_CONFIG_PREFIX=/bad/prefix; npm_config_userconfig=/bad/lower; export NODE_OPTIONS NODE_PATH NPM_CONFIG_USERCONFIG NPM_CONFIG_GLOBALCONFIG NPM_CONFIG_PREFIX npm_config_userconfig; module::install >/dev/null 2>&1; module::verify"

for hook in update backup restore; do
  assert_status "node $hook is a documented no-op" 0 \
    bash -c "$PRE; module::$hook"
done

assert_status "node remove is a no-op when never installed" 0 \
  bash -c "$PRE; module::remove"

assert_status "node remove deletes only marker and never invokes DNF" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; [ ! -e \"\$(_node_marker)\" ]; [ \"\$(wc -l < \"\$DNF_LOG\")\" -eq 1 ]"

assert_status "node remove refuses malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_node_marker)\")\"; printf \"bad\n\" > \"\$(_node_marker)\"; chmod 600 \"\$(_node_marker)\"; module::remove"

assert_status "node runner status reports not installed before marker" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/node 2>&1); case \"\$out\" in *\"not installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "node runner status reports installed after marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/node 2>&1); case \"\$out\" in *\"installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "node runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor development/node"
