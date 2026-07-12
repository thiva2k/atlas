#!/usr/bin/env bash
# development/fish - RFC-0014

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/state"; export ATLAS_STATE_DIR
XDG_CONFIG_HOME="$HOME/config"; export XDG_CONFIG_HOME
TEST_FISH_BIN="$HOME/usr/bin/fish"; export TEST_FISH_BIN
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
RPM_LOG="$HOME/rpm.log"; export RPM_LOG
FISH_ARGV_LOG="$HOME/fish.argv"; export FISH_ARGV_LOG
: > "$DNF_LOG"; : > "$RPM_LOG"; : > "$FISH_ARGV_LOG"
mkdir -p "$HOME/bin" "$(dirname "$TEST_FISH_BIN")"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/fish/module.sh"

_fish_bin() { printf "%s\n" "$TEST_FISH_BIN"; }

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::dnf_install() {
  printf "%s\n" "$*" >> "$DNF_LOG"
  if [ "${DNF_ASSERT_MARKER_INSTALLING:-0}" = 1 ]; then
    grep -qxF state=installing "$(_fish_marker)" || return 1
  fi
  [ "${DNF_OK:-1}" = 1 ] || return 1
  RPM_INSTALLED="${RPM_INSTALLED:-} $*"; export RPM_INSTALLED
  _make_fish
}

rpm() {
  printf "%s\n" "$*" >> "$RPM_LOG"
  case "${1:-}" in
    -q)
      case " ${RPM_INSTALLED:-} " in *" ${2:-} "*) return 0 ;; *) return 1 ;; esac
      ;;
    -qf)
      case "${2:-}" in
        "$TEST_FISH_BIN")
          [ "${FISH_RPM_OWNER:-fish}" = none ] && return 1
          printf "%s-99.0.0-1.fc99.x86_64\n" "${FISH_RPM_OWNER:-fish}"
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

_make_fish() {
  mkdir -p "$(dirname "$TEST_FISH_BIN")"
  cat > "$TEST_FISH_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$FISH_ARGV_LOG"
[ "${FISH_OK:-1}" = 1 ] || exit 1
case "$*" in
  "--version") printf "fish, version 99.0.0\n" ;;
esac
EOF
  chmod +x "$TEST_FISH_BIN"
}

_fish_ready() {
  RPM_INSTALLED="fish"; export RPM_INSTALLED
  _make_fish
  _fish_config_write
}

true
'
PRE="${PRE%$'\n'}"

assert_status "fish verify passes before install with Fish absent" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; _make_fish; module::verify" 2>&1)"
assert_contains "fish verify reports unmanaged runtime when marker is absent" "$out" "present but not installed by Atlas"

out="$(bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_fish_config_file)\")\"; printf \"# user\\n\" > \"\$(_fish_config_file)\"; module::verify" 2>&1)"
assert_contains "fish verify reports unmanaged Atlas snippet when marker is absent" "$out" "unmanaged Atlas Fish snippet"

assert_status "fish check fails before marker" 1 \
  bash -c "$PRE; module::check"

assert_status "fish declares no Atlas module dependencies" 0 \
  bash -c "$PRE; [ \"\${#MODULE_DEPENDS[@]}\" -eq 0 ]"

assert_status "fish install refuses unmanaged Atlas snippet before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_fish_config_file)\")\"; printf \"# user\\n\" > \"\$(_fish_config_file)\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_fish_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "fish verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_fish_marker)\")\"; printf \"state=installed\n\" > \"\$(_fish_marker)\"; chmod 600 \"\$(_fish_marker)\"; module::verify"

assert_status "fish verify fails on marker with unknown key" 1 \
  bash -c "$PRE; _fish_marker_write installed; printf \"unexpected=value\n\" >> \"\$(_fish_marker)\"; module::verify"

assert_status "fish verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _fish_marker_write installed; chmod 644 \"\$(_fish_marker)\"; module::verify"

assert_status "fish verify fails on installing marker" 1 \
  bash -c "$PRE; _fish_marker_write installing; _fish_ready; module::verify"

assert_status "fish verify passes when managed state is healthy" 0 \
  bash -c "$PRE; _fish_marker_write installed; _fish_ready; module::verify"

assert_status "fish verify fails when marker config hash mismatches" 1 \
  bash -c "$PRE; _fish_marker_write installed; _fish_ready; sed -i \"s/config_sha256=.*/config_sha256=bad/\" \"\$(_fish_marker)\"; module::verify"

assert_status "fish verify fails when marker config path mismatches" 1 \
  bash -c "$PRE; _fish_marker_write installed; _fish_ready; sed -i \"s#config_path=.*#config_path=/tmp/elsewhere#\" \"\$(_fish_marker)\"; module::verify"

assert_status "fish verify fails when fish package is missing" 1 \
  bash -c "$PRE; _fish_marker_write installed; _fish_ready; RPM_INSTALLED=; export RPM_INSTALLED; module::verify"

assert_status "fish verify fails when fish command is missing" 1 \
  bash -c "$PRE; _fish_marker_write installed; _fish_ready; rm -f \"\$TEST_FISH_BIN\"; module::verify"

assert_status "fish verify fails when fish command is not runnable" 1 \
  bash -c "$PRE; _fish_marker_write installed; _fish_ready; FISH_OK=0; export FISH_OK; module::verify"

assert_status "fish verify fails when fish RPM owner is wrong" 1 \
  bash -c "$PRE; _fish_marker_write installed; _fish_ready; FISH_RPM_OWNER=evil-fish; export FISH_RPM_OWNER; module::verify"

assert_status "fish verify fails when Atlas snippet is missing" 1 \
  bash -c "$PRE; _fish_marker_write installed; _fish_ready; rm -f \"\$(_fish_config_file)\"; module::verify"

assert_status "fish verify fails when Atlas snippet drifts" 1 \
  bash -c "$PRE; _fish_marker_write installed; _fish_ready; printf \"# drift\\n\" >> \"\$(_fish_config_file)\"; module::verify"

assert_status "fish install writes installing marker before DNF" 0 \
  bash -c "$PRE; DNF_ASSERT_MARKER_INSTALLING=1; export DNF_ASSERT_MARKER_INSTALLING; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_fish_marker)\""

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")"
assert_eq "fish install uses exact Fedora package set" "$out" "fish"

assert_status "fish install promotes marker only after validation" 1 \
  bash -c "$PRE; FISH_OK=0; export FISH_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_fish_marker)\"; exit \"\${rc:-0}\""

assert_status "fish install leaves installing marker after DNF failure" 1 \
  bash -c "$PRE; DNF_OK=0; export DNF_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_fish_marker)\"; exit \"\${rc:-0}\""

assert_status "fish install refuses non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_fish_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "fish install refuses non-executable system fish before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_FISH_BIN\")\"; : > \"\$TEST_FISH_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_fish_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "fish install refuses wrong system fish owner before mutation" 1 \
  bash -c "$PRE; _make_fish; FISH_RPM_OWNER=evil-fish; export FISH_RPM_OWNER; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_fish_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "fish install repairs installing marker" 0 \
  bash -c "$PRE; _fish_marker_write installing; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_fish_marker)\"; module::verify"

assert_status "fish repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_fish_marker)\" \"\$HOME/marker1\"; cp \"\$(_fish_config_file)\" \"\$HOME/config1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/marker1\" \"\$(_fish_marker)\"; cmp -s \"\$HOME/config1\" \"\$(_fish_config_file)\"; module::verify"

assert_status "fish repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "fish update restores Atlas snippet drift" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"# drift\\n\" >> \"\$(_fish_config_file)\"; module::update >/dev/null 2>&1; module::verify"

assert_status "fish update fails before install" 1 \
  bash -c "$PRE; module::update"

for hook in backup restore; do
  assert_status "fish $hook is a documented no-op" 0 \
    bash -c "$PRE; module::$hook"
done

assert_status "fish remove is a no-op when never installed" 0 \
  bash -c "$PRE; module::remove"

assert_status "fish remove deletes only Atlas snippet and marker, never invokes DNF" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; [ ! -e \"\$(_fish_marker)\" ]; [ ! -e \"\$(_fish_config_file)\" ]; [ \"\$(wc -l < \"\$DNF_LOG\")\" -eq 1 ]"

assert_status "fish remove refuses drifted Atlas snippet" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"# drift\\n\" >> \"\$(_fish_config_file)\"; module::remove"

assert_status "fish remove refuses malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_fish_marker)\")\"; printf \"bad\n\" > \"\$(_fish_marker)\"; chmod 600 \"\$(_fish_marker)\"; module::remove"

assert_status "fish runner status reports not installed before marker" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/fish 2>&1); case \"\$out\" in *\"not installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "fish runner status reports installed after marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/fish 2>&1); case \"\$out\" in *\"installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "fish runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor development/fish"
