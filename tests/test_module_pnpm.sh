#!/usr/bin/env bash
# development/pnpm - RFC-0015
#
# Tests sandbox system paths and mock DNF/RPM. No test mutates the host pnpm,
# DNF database, user caches, stores, projects, or /usr/bin.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/state"; export ATLAS_STATE_DIR
TEST_PNPM_BIN="$HOME/usr/bin/pnpm"; export TEST_PNPM_BIN
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
RPM_LOG="$HOME/rpm.log"; export RPM_LOG
PNPM_ARGV_LOG="$HOME/pnpm.argv"; export PNPM_ARGV_LOG
: > "$DNF_LOG"; : > "$RPM_LOG"; : > "$PNPM_ARGV_LOG"
mkdir -p "$HOME/bin" "$(dirname "$TEST_PNPM_BIN")"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/pnpm/module.sh"

_pnpm_bin() { printf "%s\n" "$TEST_PNPM_BIN"; }

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::dnf_install() {
  printf "%s\n" "$*" >> "$DNF_LOG"
  if [ "${DNF_ASSERT_MARKER_INSTALLING:-0}" = 1 ]; then
    grep -qxF state=installing "$(_pnpm_marker)" || return 1
  fi
  [ "${DNF_OK:-1}" = 1 ] || return 1
  RPM_INSTALLED="${RPM_INSTALLED:-} $*"; export RPM_INSTALLED
  _make_pnpm
}

rpm() {
  printf "%s\n" "$*" >> "$RPM_LOG"
  case "${1:-}" in
    -q)
      case " ${RPM_INSTALLED:-} " in *" ${2:-} "*) return 0 ;; *) return 1 ;; esac
      ;;
    -qf)
      case "${2:-}" in
        "$TEST_PNPM_BIN")
          [ "${PNPM_RPM_OWNER:-pnpm}" = none ] && return 1
          printf "%s-99.0.0-1.fc99.noarch\n" "${PNPM_RPM_OWNER:-pnpm}"
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

_make_pnpm() {
  mkdir -p "$(dirname "$TEST_PNPM_BIN")"
  cat > "$TEST_PNPM_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$PNPM_ARGV_LOG"
[ "${PNPM_OK:-1}" = 1 ] || exit 1
case "$*" in
  "--version") printf "99.0.0\n" ;;
esac
EOF
  chmod +x "$TEST_PNPM_BIN"
}

_pnpm_ready() {
  RPM_INSTALLED="pnpm"; export RPM_INSTALLED
  _make_pnpm
}

true
'
PRE="${PRE%$'\n'}"

assert_status "pnpm verify passes before install with pnpm absent" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; _make_pnpm; module::verify" 2>&1)"
assert_contains "pnpm verify reports unmanaged runtime when marker is absent" "$out" "present but not installed by Atlas"

assert_status "pnpm check fails before marker" 1 \
  bash -c "$PRE; module::check"

assert_status "pnpm declares dependency on development/node" 0 \
  bash -c "$PRE; [ \"\${MODULE_DEPENDS[*]}\" = \"development/node\" ]"

assert_status "pnpm verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_pnpm_marker)\")\"; printf \"state=installed\n\" > \"\$(_pnpm_marker)\"; chmod 600 \"\$(_pnpm_marker)\"; module::verify"

assert_status "pnpm verify fails on marker with unknown key" 1 \
  bash -c "$PRE; _pnpm_marker_write installed; printf \"unexpected=value\n\" >> \"\$(_pnpm_marker)\"; module::verify"

assert_status "pnpm verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _pnpm_marker_write installed; chmod 644 \"\$(_pnpm_marker)\"; module::verify"

assert_status "pnpm verify fails on installing marker" 1 \
  bash -c "$PRE; _pnpm_marker_write installing; _pnpm_ready; module::verify"

assert_status "pnpm verify passes when managed CLI is healthy" 0 \
  bash -c "$PRE; _pnpm_marker_write installed; _pnpm_ready; module::verify"

assert_status "pnpm verify fails when pnpm package is missing" 1 \
  bash -c "$PRE; _pnpm_marker_write installed; _pnpm_ready; RPM_INSTALLED=; export RPM_INSTALLED; module::verify"

assert_status "pnpm verify fails when pnpm command is missing" 1 \
  bash -c "$PRE; _pnpm_marker_write installed; _pnpm_ready; rm -f \"\$TEST_PNPM_BIN\"; module::verify"

assert_status "pnpm verify fails when pnpm command is not runnable" 1 \
  bash -c "$PRE; _pnpm_marker_write installed; _pnpm_ready; PNPM_OK=0; export PNPM_OK; module::verify"

assert_status "pnpm verify fails when pnpm RPM owner is wrong" 1 \
  bash -c "$PRE; _pnpm_marker_write installed; _pnpm_ready; PNPM_RPM_OWNER=evil-pnpm; export PNPM_RPM_OWNER; module::verify"

assert_status "pnpm verify fails when pnpm version output is unexpected" 1 \
  bash -c "$PRE; _pnpm_marker_write installed; _pnpm_ready; printf \"#!/usr/bin/env bash\\nprintf bad-version\\n\" > \"\$TEST_PNPM_BIN\"; chmod +x \"\$TEST_PNPM_BIN\"; module::verify"

assert_status "pnpm install writes installing marker before DNF" 0 \
  bash -c "$PRE; DNF_ASSERT_MARKER_INSTALLING=1; export DNF_ASSERT_MARKER_INSTALLING; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_pnpm_marker)\""

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")"
assert_eq "pnpm install uses exact Fedora package set" "$out" "pnpm"

assert_status "pnpm install promotes marker only after validation" 1 \
  bash -c "$PRE; PNPM_OK=0; export PNPM_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_pnpm_marker)\"; exit \"\${rc:-0}\""

assert_status "pnpm install leaves installing marker after DNF failure" 1 \
  bash -c "$PRE; DNF_OK=0; export DNF_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_pnpm_marker)\"; exit \"\${rc:-0}\""

assert_status "pnpm install refuses non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_pnpm_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "pnpm install refuses non-executable system pnpm before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_PNPM_BIN\")\"; : > \"\$TEST_PNPM_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_pnpm_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "pnpm install refuses wrong system pnpm owner before mutation" 1 \
  bash -c "$PRE; _make_pnpm; PNPM_RPM_OWNER=evil-pnpm; export PNPM_RPM_OWNER; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_pnpm_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "pnpm install repairs installing marker" 0 \
  bash -c "$PRE; _pnpm_marker_write installing; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_pnpm_marker)\"; module::verify"

assert_status "pnpm repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_pnpm_marker)\" \"\$HOME/marker1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/marker1\" \"\$(_pnpm_marker)\"; module::verify"

assert_status "pnpm repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "pnpm probes ignore hostile PATH shims" 0 \
  bash -c "$PRE; mkdir -p \"\$HOME/bin\"; printf \"#!/usr/bin/env bash\\nexit 99\\n\" > \"\$HOME/bin/pnpm\"; chmod +x \"\$HOME/bin/pnpm\"; PATH=\"\$HOME/bin:\$PATH\"; export PATH; module::install >/dev/null 2>&1; module::verify"

assert_status "pnpm probes ignore hostile pnpm, npm, Node, and Corepack environment" 0 \
  bash -c "$PRE; PNPM_HOME=/bad/pnpm; PNPM_STORE_PATH=/bad/store; NPM_CONFIG_USERCONFIG=/bad/npmrc; NPM_CONFIG_GLOBALCONFIG=/bad/global-npmrc; NPM_CONFIG_PREFIX=/bad/prefix; npm_config_userconfig=/bad/npmrc; npm_config_globalconfig=/bad/global-npmrc; npm_config_prefix=/bad/prefix; NODE_OPTIONS=--bad; NODE_PATH=/bad/node; COREPACK_HOME=/bad/corepack; COREPACK_ENABLE_PROJECT_SPEC=0; export PNPM_HOME PNPM_STORE_PATH NPM_CONFIG_USERCONFIG NPM_CONFIG_GLOBALCONFIG NPM_CONFIG_PREFIX npm_config_userconfig npm_config_globalconfig npm_config_prefix NODE_OPTIONS NODE_PATH COREPACK_HOME COREPACK_ENABLE_PROJECT_SPEC; module::install >/dev/null 2>&1; module::verify"

assert_status "pnpm install and verify only run pnpm --version" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify >/dev/null 2>&1; if grep -vx -- \"--version\" \"\$PNPM_ARGV_LOG\" >/dev/null; then exit 1; fi"

for hook in update backup restore; do
  assert_status "pnpm $hook is a documented no-op" 0 \
    bash -c "$PRE; module::$hook"
done

assert_status "pnpm remove is a no-op when never installed" 0 \
  bash -c "$PRE; module::remove"

assert_status "pnpm remove deletes only marker and never invokes DNF" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; [ ! -e \"\$(_pnpm_marker)\" ]; [ \"\$(wc -l < \"\$DNF_LOG\")\" -eq 1 ]"

assert_status "pnpm remove refuses malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_pnpm_marker)\")\"; printf \"bad\n\" > \"\$(_pnpm_marker)\"; chmod 600 \"\$(_pnpm_marker)\"; module::remove"

assert_status "pnpm runner status reports not installed before marker" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/pnpm 2>&1); case \"\$out\" in *\"not installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "pnpm runner status reports installed after marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/pnpm 2>&1); case \"\$out\" in *\"installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "pnpm runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor development/pnpm"
