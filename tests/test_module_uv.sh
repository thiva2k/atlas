#!/usr/bin/env bash
# development/uv - RFC-0009
#
# Tests sandbox system paths and mock DNF/RPM. No test mutates the host uv,
# DNF database, user caches, projects, or /usr/bin.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/state"; export ATLAS_STATE_DIR
TEST_UV_BIN="$HOME/usr/bin/uv"; export TEST_UV_BIN
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
RPM_LOG="$HOME/rpm.log"; export RPM_LOG
UV_ARGV_LOG="$HOME/uv.argv"; export UV_ARGV_LOG
: > "$DNF_LOG"; : > "$RPM_LOG"; : > "$UV_ARGV_LOG"
mkdir -p "$HOME/bin" "$(dirname "$TEST_UV_BIN")"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/uv/module.sh"

_uv_bin() { printf "%s\n" "$TEST_UV_BIN"; }

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::dnf_install() {
  printf "%s\n" "$*" >> "$DNF_LOG"
  if [ "${DNF_ASSERT_MARKER_INSTALLING:-0}" = 1 ]; then
    grep -qxF state=installing "$(_uv_marker)" || return 1
  fi
  [ "${DNF_OK:-1}" = 1 ] || return 1
  RPM_INSTALLED="${RPM_INSTALLED:-} $*"; export RPM_INSTALLED
  _make_uv
}

rpm() {
  printf "%s\n" "$*" >> "$RPM_LOG"
  case "${1:-}" in
    -q)
      case " ${RPM_INSTALLED:-} " in *" ${2:-} "*) return 0 ;; *) return 1 ;; esac
      ;;
    -qf)
      case "${2:-}" in
        "$TEST_UV_BIN")
          [ "${UV_RPM_OWNER:-uv}" = none ] && return 1
          printf "%s-99.0.0-1.fc99.x86_64\n" "${UV_RPM_OWNER:-uv}"
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

_make_uv() {
  mkdir -p "$(dirname "$TEST_UV_BIN")"
  cat > "$TEST_UV_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$UV_ARGV_LOG"
[ "${UV_OK:-1}" = 1 ] || exit 1
case "$*" in
  "--version") printf "uv 99.0.0\n" ;;
esac
EOF
  chmod +x "$TEST_UV_BIN"
}

_uv_ready() {
  RPM_INSTALLED="uv"; export RPM_INSTALLED
  _make_uv
}

true
'
PRE="${PRE%$'\n'}"

assert_status "uv verify passes before install with uv absent" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; _make_uv; module::verify" 2>&1)"
assert_contains "uv verify reports unmanaged runtime when marker is absent" "$out" "present but not installed by Atlas"

assert_status "uv check fails before marker" 1 \
  bash -c "$PRE; module::check"

assert_status "uv declares dependency on development/python" 0 \
  bash -c "$PRE; [ \"\${MODULE_DEPENDS[*]}\" = \"development/python\" ]"

assert_status "uv verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_uv_marker)\")\"; printf \"state=installed\n\" > \"\$(_uv_marker)\"; chmod 600 \"\$(_uv_marker)\"; module::verify"

assert_status "uv verify fails on marker with unknown key" 1 \
  bash -c "$PRE; _uv_marker_write installed; printf \"unexpected=value\n\" >> \"\$(_uv_marker)\"; module::verify"

assert_status "uv verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _uv_marker_write installed; chmod 644 \"\$(_uv_marker)\"; module::verify"

assert_status "uv verify fails on installing marker" 1 \
  bash -c "$PRE; _uv_marker_write installing; _uv_ready; module::verify"

assert_status "uv verify passes when managed CLI is healthy" 0 \
  bash -c "$PRE; _uv_marker_write installed; _uv_ready; module::verify"

assert_status "uv verify fails when uv package is missing" 1 \
  bash -c "$PRE; _uv_marker_write installed; _uv_ready; RPM_INSTALLED=; export RPM_INSTALLED; module::verify"

assert_status "uv verify fails when uv command is missing" 1 \
  bash -c "$PRE; _uv_marker_write installed; _uv_ready; rm -f \"\$TEST_UV_BIN\"; module::verify"

assert_status "uv verify fails when uv command is not runnable" 1 \
  bash -c "$PRE; _uv_marker_write installed; _uv_ready; UV_OK=0; export UV_OK; module::verify"

assert_status "uv verify fails when uv RPM owner is wrong" 1 \
  bash -c "$PRE; _uv_marker_write installed; _uv_ready; UV_RPM_OWNER=evil-uv; export UV_RPM_OWNER; module::verify"

assert_status "uv install writes installing marker before DNF" 0 \
  bash -c "$PRE; DNF_ASSERT_MARKER_INSTALLING=1; export DNF_ASSERT_MARKER_INSTALLING; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_uv_marker)\""

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")"
assert_eq "uv install uses exact Fedora package set" "$out" "uv"

assert_status "uv install promotes marker only after validation" 1 \
  bash -c "$PRE; UV_OK=0; export UV_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_uv_marker)\"; exit \"\${rc:-0}\""

assert_status "uv install leaves installing marker after DNF failure" 1 \
  bash -c "$PRE; DNF_OK=0; export DNF_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_uv_marker)\"; exit \"\${rc:-0}\""

assert_status "uv install refuses non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_uv_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "uv install refuses non-executable system uv before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_UV_BIN\")\"; : > \"\$TEST_UV_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_uv_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "uv install refuses wrong system uv owner before mutation" 1 \
  bash -c "$PRE; _make_uv; UV_RPM_OWNER=evil-uv; export UV_RPM_OWNER; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_uv_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "uv install repairs installing marker" 0 \
  bash -c "$PRE; _uv_marker_write installing; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_uv_marker)\"; module::verify"

assert_status "uv repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_uv_marker)\" \"\$HOME/marker1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/marker1\" \"\$(_uv_marker)\"; module::verify"

assert_status "uv repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "uv probes ignore hostile PATH shims" 0 \
  bash -c "$PRE; mkdir -p \"\$HOME/bin\"; printf \"#!/usr/bin/env bash\\nexit 99\\n\" > \"\$HOME/bin/uv\"; chmod +x \"\$HOME/bin/uv\"; PATH=\"\$HOME/bin:\$PATH\"; export PATH; module::install >/dev/null 2>&1; module::verify"

assert_status "uv probes ignore hostile uv and Python environment" 0 \
  bash -c "$PRE; UV_CACHE_DIR=/bad/cache; UV_CONFIG_FILE=/bad/uv.toml; UV_TOOL_DIR=/bad/tools; UV_PYTHON_INSTALL_DIR=/bad/python; UV_PROJECT_ENVIRONMENT=/bad/project; VIRTUAL_ENV=/bad/venv; CONDA_PREFIX=/bad/conda; PYTHONHOME=/bad; PYTHONPATH=/bad; export UV_CACHE_DIR UV_CONFIG_FILE UV_TOOL_DIR UV_PYTHON_INSTALL_DIR UV_PROJECT_ENVIRONMENT VIRTUAL_ENV CONDA_PREFIX PYTHONHOME PYTHONPATH; module::install >/dev/null 2>&1; module::verify"

for hook in update backup restore; do
  assert_status "uv $hook is a documented no-op" 0 \
    bash -c "$PRE; module::$hook"
done

assert_status "uv remove is a no-op when never installed" 0 \
  bash -c "$PRE; module::remove"

assert_status "uv remove deletes only marker and never invokes DNF" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; [ ! -e \"\$(_uv_marker)\" ]; [ \"\$(wc -l < \"\$DNF_LOG\")\" -eq 1 ]"

assert_status "uv remove refuses malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_uv_marker)\")\"; printf \"bad\n\" > \"\$(_uv_marker)\"; chmod 600 \"\$(_uv_marker)\"; module::remove"

assert_status "uv runner status reports not installed before marker" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/uv 2>&1); case \"\$out\" in *\"not installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "uv runner status reports installed after marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/uv 2>&1); case \"\$out\" in *\"installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "uv runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor development/uv"
