#!/usr/bin/env bash
# development/claude - RFC-0016
#
# Tests sandbox system paths and mock DNF/RPM/rpmkeys. No test mutates the host
# Claude installation, RPM database, DNF repository, user config, or /etc.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/state"; export ATLAS_STATE_DIR
TEST_CLAUDE_BIN="$HOME/usr/bin/claude"; export TEST_CLAUDE_BIN
TEST_REPO_FILE="$HOME/etc/yum.repos.d/claude-code.repo"; export TEST_REPO_FILE
TEST_SETTINGS_FILE="$HOME/etc/claude-code/managed-settings.d/00-atlas.json"; export TEST_SETTINGS_FILE
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
RPM_LOG="$HOME/rpm.log"; export RPM_LOG
RPMKEYS_LOG="$HOME/rpmkeys.log"; export RPMKEYS_LOG
CLAUDE_ARGV_LOG="$HOME/claude.argv"; export CLAUDE_ARGV_LOG
: > "$DNF_LOG"; : > "$RPM_LOG"; : > "$RPMKEYS_LOG"; : > "$CLAUDE_ARGV_LOG"
mkdir -p "$HOME/bin" "$(dirname "$TEST_CLAUDE_BIN")"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/claude/module.sh"

_claude_bin() { printf "%s\n" "$TEST_CLAUDE_BIN"; }
_claude_repo_file() { printf "%s\n" "$TEST_REPO_FILE"; }
_claude_settings_file() { printf "%s\n" "$TEST_SETTINGS_FILE"; }
_claude_run_privileged() { "$@"; }

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::is_root() { return 0; }
os::dnf_install() {
  printf "%s\n" "$*" >> "$DNF_LOG"
  if [ "${DNF_ASSERT_MARKER_INSTALLING:-0}" = 1 ]; then
    grep -qxF state=installing "$(_claude_marker)" || return 1
  fi
  [ "${DNF_OK:-1}" = 1 ] || return 1
  RPM_INSTALLED="${RPM_INSTALLED:-} $*"; export RPM_INSTALLED
  _make_claude
}

rpm() {
  printf "%s\n" "$*" >> "$RPM_LOG"
  case "${1:-}" in
    -q)
      case " ${RPM_INSTALLED:-} " in *" ${2:-} "*) return 0 ;; *) return 1 ;; esac
      ;;
    -qf)
      case "${2:-}" in
        "$TEST_CLAUDE_BIN")
          [ "${CLAUDE_RPM_OWNER:-claude-code}" = none ] && return 1
          printf "%s-99.0.0-1.x86_64\n" "${CLAUDE_RPM_OWNER:-claude-code}"
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

rpmkeys() {
  printf "%s\n" "$*" >> "$RPMKEYS_LOG"
  case "$*" in
    *"--import"*)
      case "$*" in
        *"--root "*) ;;
        *)
          if [ "${RPMKEYS_ASSERT_MARKER_INSTALLING:-0}" = 1 ]; then
            grep -qxF state=installing "$(_claude_marker)" || return 1
            [ ! -e "$TEST_REPO_FILE" ] || return 1
            [ ! -e "$TEST_SETTINGS_FILE" ] || return 1
            [ ! -s "$DNF_LOG" ] || return 1
          fi
          ;;
      esac
      [ "${RPMKEYS_IMPORT_OK:-1}" = 1 ] || return 1
      KEY_IMPORTED=1; export KEY_IMPORTED
      return 0
      ;;
    *"--list"*)
      if [ "${KEY_PRESENT:-${KEY_IMPORTED:-0}}" = 1 ]; then
        printf "31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE Anthropic Claude Code Release Signing\n"
      else
        printf "0000000000000000000000000000000000000000 Other Key\n"
      fi
      return 0
      ;;
  esac
  return 0
}

_make_claude() {
  mkdir -p "$(dirname "$TEST_CLAUDE_BIN")"
  cat > "$TEST_CLAUDE_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$CLAUDE_ARGV_LOG"
[ "${CLAUDE_OK:-1}" = 1 ] || exit 1
case "$*" in
  "--version") printf "claude-code 99.0.0\n" ;;
esac
EOF
  chmod +x "$TEST_CLAUDE_BIN"
}

_claude_ready() {
  RPM_INSTALLED="claude-code"; export RPM_INSTALLED
  KEY_PRESENT=1; export KEY_PRESENT
  _make_claude
  _claude_write_repo
  _claude_write_settings
}

true
'
PRE="${PRE%$'\n'}"

assert_status "claude verify passes before install with Claude absent" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; _make_claude; module::verify" 2>&1)"
assert_contains "claude verify reports unmanaged CLI when marker is absent" "$out" "present but not installed by Atlas"

assert_status "claude check fails before marker" 1 \
  bash -c "$PRE; module::check"

assert_status "claude declares no Atlas module dependencies" 0 \
  bash -c "$PRE; [ \"\${MODULE_DEPENDS[*]}\" = \"\" ]"

assert_status "claude bundled key source validates" 0 \
  bash -c "$PRE; _claude_key_source_valid"

assert_status "claude bundled key hash mismatch is rejected" 1 \
  bash -c "$PRE; bad=\"\$HOME/bad.asc\"; cp \"\$(_claude_key_source)\" \"\$bad\"; printf x >> \"\$bad\"; _claude_key_source() { printf \"%s\n\" \"\$bad\"; }; _claude_key_source_valid"

assert_status "claude repo and settings sources validate" 0 \
  bash -c "$PRE; _claude_repo_source_valid; _claude_settings_source_valid"

assert_status "claude verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_claude_marker)\")\"; printf \"state=installed\n\" > \"\$(_claude_marker)\"; chmod 600 \"\$(_claude_marker)\"; module::verify"

assert_status "claude verify fails on marker with unknown key" 1 \
  bash -c "$PRE; _claude_marker_write installed; printf \"unexpected=value\n\" >> \"\$(_claude_marker)\"; module::verify"

assert_status "claude verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _claude_marker_write installed; chmod 644 \"\$(_claude_marker)\"; module::verify"

assert_status "claude verify fails on marker repo hash mismatch" 1 \
  bash -c "$PRE; _claude_marker_write installed; sed -i \"s/^repo_sha256=.*/repo_sha256=0/\" \"\$(_claude_marker)\"; module::verify"

assert_status "claude verify fails on marker settings hash mismatch" 1 \
  bash -c "$PRE; _claude_marker_write installed; sed -i \"s/^settings_sha256=.*/settings_sha256=0/\" \"\$(_claude_marker)\"; module::verify"

assert_status "claude verify fails on installing marker" 1 \
  bash -c "$PRE; _claude_marker_write installing; _claude_ready; module::verify"

assert_status "claude verify passes when managed CLI is healthy" 0 \
  bash -c "$PRE; _claude_marker_write installed; _claude_ready; module::verify"

assert_status "claude verify fails when package is missing" 1 \
  bash -c "$PRE; _claude_marker_write installed; _claude_ready; RPM_INSTALLED=; export RPM_INSTALLED; module::verify"

assert_status "claude verify fails when command is missing" 1 \
  bash -c "$PRE; _claude_marker_write installed; _claude_ready; rm -f \"\$TEST_CLAUDE_BIN\"; module::verify"

assert_status "claude verify fails when command is not runnable" 1 \
  bash -c "$PRE; _claude_marker_write installed; _claude_ready; CLAUDE_OK=0; export CLAUDE_OK; module::verify"

assert_status "claude verify fails when command RPM owner is wrong" 1 \
  bash -c "$PRE; _claude_marker_write installed; _claude_ready; CLAUDE_RPM_OWNER=evil-claude; export CLAUDE_RPM_OWNER; module::verify"

assert_status "claude verify fails when repo drifts" 1 \
  bash -c "$PRE; _claude_marker_write installed; _claude_ready; printf drift >> \"\$TEST_REPO_FILE\"; module::verify"

assert_status "claude verify fails when managed settings drift" 1 \
  bash -c "$PRE; _claude_marker_write installed; _claude_ready; printf drift >> \"\$TEST_SETTINGS_FILE\"; module::verify"

assert_status "claude install refuses non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_claude_marker)\" ]; [ ! -e \"\$TEST_REPO_FILE\" ]; [ ! -e \"\$TEST_SETTINGS_FILE\" ]; [ ! -s \"\$DNF_LOG\" ]; [ ! -s \"\$RPMKEYS_LOG\" ]; exit \"\${rc:-0}\""

assert_status "claude install refuses unmanaged repo before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_REPO_FILE\")\"; printf unmanaged > \"\$TEST_REPO_FILE\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_claude_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; [ ! -s \"\$RPMKEYS_LOG\" ]; exit \"\${rc:-0}\""

assert_status "claude install refuses unmanaged settings before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_SETTINGS_FILE\")\"; printf unmanaged > \"\$TEST_SETTINGS_FILE\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_claude_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; [ ! -s \"\$RPMKEYS_LOG\" ]; exit \"\${rc:-0}\""

assert_status "claude install refuses non-executable system command before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_CLAUDE_BIN\")\"; : > \"\$TEST_CLAUDE_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_claude_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; [ ! -s \"\$RPMKEYS_LOG\" ]; exit \"\${rc:-0}\""

assert_status "claude install refuses wrong system command owner before mutation" 1 \
  bash -c "$PRE; _make_claude; CLAUDE_RPM_OWNER=evil-claude; export CLAUDE_RPM_OWNER; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_claude_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; [ ! -s \"\$RPMKEYS_LOG\" ]; exit \"\${rc:-0}\""

assert_status "claude install writes installing marker before key repo settings and dnf" 0 \
  bash -c "$PRE; RPMKEYS_ASSERT_MARKER_INSTALLING=1; export RPMKEYS_ASSERT_MARKER_INSTALLING; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_claude_marker)\""

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")"
assert_eq "claude install uses exact package set" "$out" "claude-code"

assert_status "claude install imports only bundled key" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -F -- \"--import \$(_claude_key_source)\" \"\$RPMKEYS_LOG\""

assert_status "claude install promotes marker only after validation" 1 \
  bash -c "$PRE; CLAUDE_OK=0; export CLAUDE_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_claude_marker)\"; exit \"\${rc:-0}\""

assert_status "claude install leaves installing marker after DNF failure" 1 \
  bash -c "$PRE; DNF_OK=0; export DNF_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_claude_marker)\"; exit \"\${rc:-0}\""

assert_status "claude install repairs installing marker" 0 \
  bash -c "$PRE; _claude_marker_write installing; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_claude_marker)\"; module::verify"

assert_status "claude repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_claude_marker)\" \"\$HOME/marker1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/marker1\" \"\$(_claude_marker)\"; module::verify"

assert_status "claude probes ignore hostile PATH shims and environment" 0 \
  bash -c "$PRE; mkdir -p \"\$HOME/bin\"; printf \"#!/usr/bin/env bash\\nexit 99\\n\" > \"\$HOME/bin/claude\"; chmod +x \"\$HOME/bin/claude\"; PATH=\"\$HOME/bin:\$PATH\"; CLAUDE_CONFIG_DIR=/bad; CLAUDE_CODE_USE_BEDROCK=1; ANTHROPIC_API_KEY=secret; export PATH CLAUDE_CONFIG_DIR CLAUDE_CODE_USE_BEDROCK ANTHROPIC_API_KEY; module::install >/dev/null 2>&1; module::verify"

assert_status "claude install and verify only run claude --version" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify >/dev/null 2>&1; if grep -vx -- \"--version\" \"\$CLAUDE_ARGV_LOG\" >/dev/null; then exit 1; fi"

assert_status "claude update restores managed repo and settings drift" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$TEST_REPO_FILE\"; printf drift >> \"\$TEST_SETTINGS_FILE\"; module::update >/dev/null 2>&1; module::verify"

assert_status "claude backup is a documented no-op" 0 \
  bash -c "$PRE; module::backup"

assert_status "claude restore is a documented no-op" 0 \
  bash -c "$PRE; module::restore"

assert_status "claude remove is a no-op when never installed" 0 \
  bash -c "$PRE; module::remove"

assert_status "claude remove deletes only Atlas repo settings and marker, never invokes DNF" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; [ ! -e \"\$(_claude_marker)\" ]; [ ! -e \"\$TEST_REPO_FILE\" ]; [ ! -e \"\$TEST_SETTINGS_FILE\" ]; [ \"\$(wc -l < \"\$DNF_LOG\")\" -eq 1 ]"

assert_status "claude remove refuses drifted repo" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$TEST_REPO_FILE\"; module::remove"

assert_status "claude remove refuses drifted settings" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf drift >> \"\$TEST_SETTINGS_FILE\"; module::remove"

assert_status "claude runner status reports not installed before marker" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"$ATLAS_ROOT/internal/module.sh\"; source \"$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/claude 2>&1); case \"\$out\" in *\"not installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "claude runner status reports installed after marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; set +e; set -uo pipefail; source \"$ATLAS_ROOT/internal/module.sh\"; source \"$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/claude 2>&1); case \"\$out\" in *\"installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "claude runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"$ATLAS_ROOT/internal/module.sh\"; source \"$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor development/claude"
