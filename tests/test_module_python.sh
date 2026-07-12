#!/usr/bin/env bash
# development/python - RFC-0006
#
# Tests sandbox system paths and mock DNF/RPM. No test mutates the host Python,
# pip, DNF database, or /usr/bin.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/state"; export ATLAS_STATE_DIR
TEST_PYTHON_BIN="$HOME/usr/bin/python3"; export TEST_PYTHON_BIN
TEST_PIP_BIN="$HOME/usr/bin/pip3"; export TEST_PIP_BIN
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
RPM_LOG="$HOME/rpm.log"; export RPM_LOG
PYTHON_ARGV_LOG="$HOME/python.argv"; export PYTHON_ARGV_LOG
PIP_ARGV_LOG="$HOME/pip.argv"; export PIP_ARGV_LOG
: > "$DNF_LOG"; : > "$RPM_LOG"; : > "$PYTHON_ARGV_LOG"; : > "$PIP_ARGV_LOG"
mkdir -p "$HOME/bin" "$(dirname "$TEST_PYTHON_BIN")"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/python/module.sh"

_python_python_bin() { printf "%s\n" "$TEST_PYTHON_BIN"; }
_python_pip_bin() { printf "%s\n" "$TEST_PIP_BIN"; }

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::dnf_install() {
  printf "%s\n" "$*" >> "$DNF_LOG"
  if [ "${DNF_ASSERT_MARKER_INSTALLING:-0}" = 1 ]; then
    grep -qxF state=installing "$(_python_marker)" || return 1
  fi
  [ "${DNF_OK:-1}" = 1 ] || return 1
  RPM_INSTALLED="${RPM_INSTALLED:-} $*"; export RPM_INSTALLED
  _make_python
  _make_pip
}

rpm() {
  printf "%s\n" "$*" >> "$RPM_LOG"
  case "${1:-}" in
    -q)
      case " ${RPM_INSTALLED:-} " in *" ${2:-} "*) return 0 ;; *) return 1 ;; esac
      ;;
    -qf)
      case "${2:-}" in
        "$TEST_PYTHON_BIN")
          [ "${PYTHON_RPM_OWNER:-python3}" = none ] && return 1
          printf "%s-99.0.0-1.fc99.x86_64\n" "${PYTHON_RPM_OWNER:-python3}"
          return 0
          ;;
        "$TEST_PIP_BIN")
          [ "${PIP_RPM_OWNER:-python3-pip}" = none ] && return 1
          printf "%s-99.0.0-1.fc99.x86_64\n" "${PIP_RPM_OWNER:-python3-pip}"
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

_make_python() {
  mkdir -p "$(dirname "$TEST_PYTHON_BIN")"
  cat > "$TEST_PYTHON_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$PYTHON_ARGV_LOG"
[ "${PYTHON_OK:-1}" = 1 ] || exit 1
case "$*" in
  "--version") printf "Python 3.99.0\n" ;;
esac
EOF
  chmod +x "$TEST_PYTHON_BIN"
}

_make_pip() {
  mkdir -p "$(dirname "$TEST_PIP_BIN")"
  cat > "$TEST_PIP_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$PIP_ARGV_LOG"
[ "${PIP_OK:-1}" = 1 ] || exit 1
case "$*" in
  "--version") printf "pip 99.0 from /usr/lib/python3/site-packages/pip (python 3.99)\n" ;;
esac
EOF
  chmod +x "$TEST_PIP_BIN"
}

_python_ready() {
  RPM_INSTALLED="python3 python3-pip"; export RPM_INSTALLED
  _make_python
  _make_pip
}

true
'
PRE="${PRE%$'\n'}"

assert_status "python verify passes before install with Python absent" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; _make_python; _make_pip; module::verify" 2>&1)"
assert_contains "python verify reports unmanaged runtime when marker is absent" "$out" "present but not installed by Atlas"

assert_status "python check fails before marker" 1 \
  bash -c "$PRE; module::check"

assert_status "python verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_python_marker)\")\"; printf \"state=installed\n\" > \"\$(_python_marker)\"; chmod 600 \"\$(_python_marker)\"; module::verify"

assert_status "python verify fails on marker with unknown key" 1 \
  bash -c "$PRE; _python_marker_write installed; printf \"unexpected=value\n\" >> \"\$(_python_marker)\"; module::verify"

assert_status "python verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _python_marker_write installed; chmod 644 \"\$(_python_marker)\"; module::verify"

assert_status "python verify fails on installing marker" 1 \
  bash -c "$PRE; _python_marker_write installing; _python_ready; module::verify"

assert_status "python verify passes when managed runtime is healthy" 0 \
  bash -c "$PRE; _python_marker_write installed; _python_ready; module::verify"

assert_status "python verify fails when python package is missing" 1 \
  bash -c "$PRE; _python_marker_write installed; _python_ready; RPM_INSTALLED=python3-pip; export RPM_INSTALLED; module::verify"

assert_status "python verify fails when pip package is missing" 1 \
  bash -c "$PRE; _python_marker_write installed; _python_ready; RPM_INSTALLED=python3; export RPM_INSTALLED; module::verify"

assert_status "python verify fails when python command is missing" 1 \
  bash -c "$PRE; _python_marker_write installed; _python_ready; rm -f \"\$TEST_PYTHON_BIN\"; module::verify"

assert_status "python verify fails when pip command is missing" 1 \
  bash -c "$PRE; _python_marker_write installed; _python_ready; rm -f \"\$TEST_PIP_BIN\"; module::verify"

assert_status "python verify fails when python RPM owner is wrong" 1 \
  bash -c "$PRE; _python_marker_write installed; _python_ready; PYTHON_RPM_OWNER=evil-python; export PYTHON_RPM_OWNER; module::verify"

assert_status "python verify fails when pip RPM owner is wrong" 1 \
  bash -c "$PRE; _python_marker_write installed; _python_ready; PIP_RPM_OWNER=evil-pip; export PIP_RPM_OWNER; module::verify"

assert_status "python install writes installing marker before DNF" 0 \
  bash -c "$PRE; DNF_ASSERT_MARKER_INSTALLING=1; export DNF_ASSERT_MARKER_INSTALLING; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_python_marker)\""

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")"
assert_eq "python install uses exact Fedora package set" "$out" "python3 python3-pip"

assert_status "python install promotes marker only after validation" 1 \
  bash -c "$PRE; PIP_OK=0; export PIP_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_python_marker)\"; exit \"\${rc:-0}\""

assert_status "python install leaves installing marker after DNF failure" 1 \
  bash -c "$PRE; DNF_OK=0; export DNF_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_python_marker)\"; exit \"\${rc:-0}\""

assert_status "python install refuses non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_python_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "python install refuses non-executable system python before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_PYTHON_BIN\")\"; : > \"\$TEST_PYTHON_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_python_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "python install refuses wrong system python owner before mutation" 1 \
  bash -c "$PRE; _make_python; PYTHON_RPM_OWNER=evil-python; export PYTHON_RPM_OWNER; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_python_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "python install refuses non-executable system pip before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_PIP_BIN\")\"; : > \"\$TEST_PIP_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_python_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "python install refuses wrong system pip owner before mutation" 1 \
  bash -c "$PRE; _make_pip; PIP_RPM_OWNER=evil-pip; export PIP_RPM_OWNER; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_python_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "python install repairs installing marker" 0 \
  bash -c "$PRE; _python_marker_write installing; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_python_marker)\"; module::verify"

assert_status "python repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_python_marker)\" \"\$HOME/marker1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/marker1\" \"\$(_python_marker)\"; module::verify"

assert_status "python repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "python probes ignore hostile PATH shims" 0 \
  bash -c "$PRE; mkdir -p \"\$HOME/bin\"; printf \"#!/usr/bin/env bash\\nexit 99\\n\" > \"\$HOME/bin/python3\"; chmod +x \"\$HOME/bin/python3\"; PATH=\"\$HOME/bin:\$PATH\"; export PATH; module::install >/dev/null 2>&1; module::verify"

assert_status "python probes ignore hostile Python and pip environment" 0 \
  bash -c "$PRE; PYTHONHOME=/bad; PYTHONPATH=/bad; PYTHONUSERBASE=/bad; PIP_CONFIG_FILE=/bad/pip.conf; PIP_REQUIRE_VIRTUALENV=1; export PYTHONHOME PYTHONPATH PYTHONUSERBASE PIP_CONFIG_FILE PIP_REQUIRE_VIRTUALENV; module::install >/dev/null 2>&1; module::verify"

for hook in update backup restore; do
  assert_status "python $hook is a documented no-op" 0 \
    bash -c "$PRE; module::$hook"
done

assert_status "python remove is a no-op when never installed" 0 \
  bash -c "$PRE; module::remove"

assert_status "python remove deletes only marker and never invokes DNF" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; [ ! -e \"\$(_python_marker)\" ]; [ \"\$(wc -l < \"\$DNF_LOG\")\" -eq 1 ]"

assert_status "python remove refuses malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_python_marker)\")\"; printf \"bad\n\" > \"\$(_python_marker)\"; chmod 600 \"\$(_python_marker)\"; module::remove"

assert_status "python runner status reports not installed before marker" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/python 2>&1); case \"\$out\" in *\"not installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "python runner status reports installed after marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/python 2>&1); case \"\$out\" in *\"installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "python runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor development/python"
