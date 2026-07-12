#!/usr/bin/env bash
# development/codex - RFC-0026
#
# Tests sandbox system paths and mock npm/RPM. No test mutates the host Codex
# installation, npm global prefix, user config, credentials, skills, or memory.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/state"; export ATLAS_STATE_DIR
TEST_CODEX_PREFIX="$HOME/usr/local"; export TEST_CODEX_PREFIX
TEST_CODEX_BIN="$TEST_CODEX_PREFIX/bin/codex"; export TEST_CODEX_BIN
TEST_CODEX_PACKAGE_DIR="$TEST_CODEX_PREFIX/lib/node_modules/@openai/codex"; export TEST_CODEX_PACKAGE_DIR
TEST_NPM_BIN="$HOME/usr/bin/npm"; export TEST_NPM_BIN
NPM_LOG="$HOME/npm.log"; export NPM_LOG
RPM_LOG="$HOME/rpm.log"; export RPM_LOG
CODEX_ARGV_LOG="$HOME/codex.argv"; export CODEX_ARGV_LOG
: > "$NPM_LOG"; : > "$RPM_LOG"; : > "$CODEX_ARGV_LOG"
mkdir -p "$HOME/bin" "$(dirname "$TEST_NPM_BIN")"

cat > "$TEST_NPM_BIN" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
case "${1:-}" in
  install)
    printf "%s\n" "$*" >> "$NPM_LOG"
    if [ "${NPM_ASSERT_MARKER_INSTALLING:-0}" = 1 ]; then
      grep -qxF state=installing "$ATLAS_STATE_DIR/installed/development-codex" || exit 1
    fi
    [ "${NPM_OK:-1}" = 1 ] || exit 1
    mkdir -p "$TEST_CODEX_PACKAGE_DIR/bin" "$(dirname "$TEST_CODEX_BIN")"
    cat > "$TEST_CODEX_PACKAGE_DIR/package.json" <<'"'"'JSON'"'"'
{
  "name": "@openai/codex",
  "version": "99.0.0"
}
JSON
    cat > "$TEST_CODEX_PACKAGE_DIR/bin/codex" <<'"'"'SH'"'"'
#!/usr/bin/env bash
printf "%s\n" "$*" >> "$CODEX_ARGV_LOG"
[ "${CODEX_OK:-1}" = 1 ] || exit 1
case "$*" in
  "--version") printf "codex-cli 99.0.0\n" ;;
esac
SH
    chmod +x "$TEST_CODEX_PACKAGE_DIR/bin/codex"
    ln -sfn "$TEST_CODEX_PACKAGE_DIR/bin/codex" "$TEST_CODEX_BIN"
    ;;
  uninstall)
    printf "%s\n" "$*" >> "$NPM_LOG"
    [ "${NPM_UNINSTALL_OK:-1}" = 1 ] || exit 1
    rm -f "$TEST_CODEX_BIN"
    rm -rf "$TEST_CODEX_PACKAGE_DIR"
    ;;
  --version)
    printf "99.0.0\n"
    ;;
esac
EOF
chmod +x "$TEST_NPM_BIN"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/codex/module.sh"

_codex_prefix() { printf "%s\n" "$TEST_CODEX_PREFIX"; }
_codex_bin() { printf "%s\n" "$TEST_CODEX_BIN"; }
_codex_package_dir() { printf "%s\n" "$TEST_CODEX_PACKAGE_DIR"; }
_codex_npm_bin() { printf "%s\n" "$TEST_NPM_BIN"; }
_codex_run_privileged() { "$@"; }

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::is_root() { return 0; }

rpm() {
  printf "%s\n" "$*" >> "$RPM_LOG"
  case "${1:-}" in
    -qf)
      case "${2:-}" in
        "$TEST_NPM_BIN")
          [ "${NPM_RPM_OWNER:-nodejs24-npm-bin}" = none ] && return 1
          printf "%s-99.0.0-1.fc99.x86_64\n" "${NPM_RPM_OWNER:-nodejs24-npm-bin}"
          return 0
          ;;
      esac
      ;;
  esac
  return 1
}

_make_codex_package() {
  "$TEST_NPM_BIN" install -g @openai/codex --prefix "$TEST_CODEX_PREFIX" --no-audit --no-fund >/dev/null
  : > "$NPM_LOG"
}

_make_user_codex() {
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/codex" <<'"'"'EOF'"'"'
#!/usr/bin/env bash
printf "user codex\n"
EOF
  chmod +x "$HOME/.local/bin/codex"
  PATH="$HOME/.local/bin:$PATH"; export PATH
}

_codex_ready() {
  _make_codex_package
}

true
'
PRE="${PRE%$'\n'}"

assert_status "codex verify passes before install with Codex absent" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; _make_user_codex; module::verify" 2>&1)"
assert_contains "codex verify reports unmanaged CLI when marker is absent" "$out" "present but not installed by Atlas"

assert_status "codex check fails before marker" 1 \
  bash -c "$PRE; module::check"

assert_status "codex declares dependency on development/node" 0 \
  bash -c "$PRE; [ \"\${MODULE_DEPENDS[*]}\" = \"development/node\" ]"

assert_status "codex verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_codex_marker)\")\"; printf \"state=installed\n\" > \"\$(_codex_marker)\"; chmod 600 \"\$(_codex_marker)\"; module::verify"

assert_status "codex verify fails on marker with unknown key" 1 \
  bash -c "$PRE; _codex_marker_write installed; printf \"unexpected=value\n\" >> \"\$(_codex_marker)\"; module::verify"

assert_status "codex verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _codex_marker_write installed; chmod 644 \"\$(_codex_marker)\"; module::verify"

assert_status "codex verify fails on installing marker" 1 \
  bash -c "$PRE; _codex_marker_write installing; _codex_ready; module::verify"

assert_status "codex verify passes when managed CLI is healthy" 0 \
  bash -c "$PRE; _codex_marker_write installed; _codex_ready; module::verify"

assert_status "codex verify fails when npm is missing" 1 \
  bash -c "$PRE; _codex_marker_write installed; _codex_ready; rm -f \"\$TEST_NPM_BIN\"; module::verify"

assert_status "codex verify fails when npm RPM owner is wrong" 1 \
  bash -c "$PRE; _codex_marker_write installed; _codex_ready; NPM_RPM_OWNER=evil-npm; export NPM_RPM_OWNER; module::verify"

assert_status "codex verify fails when package is missing" 1 \
  bash -c "$PRE; _codex_marker_write installed; _codex_ready; rm -rf \"\$TEST_CODEX_PACKAGE_DIR\"; module::verify"

assert_status "codex verify fails when command is missing" 1 \
  bash -c "$PRE; _codex_marker_write installed; _codex_ready; rm -f \"\$TEST_CODEX_BIN\"; module::verify"

assert_status "codex verify fails when command is not runnable" 1 \
  bash -c "$PRE; _codex_marker_write installed; _codex_ready; CODEX_OK=0; export CODEX_OK; module::verify"

assert_status "codex verify fails when command is not package-owned" 1 \
  bash -c "$PRE; _codex_marker_write installed; _codex_ready; rm -f \"\$TEST_CODEX_BIN\"; printf \"#!/usr/bin/env bash\\nprintf fake\\n\" > \"\$TEST_CODEX_BIN\"; chmod +x \"\$TEST_CODEX_BIN\"; module::verify"

assert_status "codex install refuses non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_codex_marker)\" ]; [ ! -s \"\$NPM_LOG\" ]; exit \"\${rc:-0}\""

assert_status "codex install refuses unmanaged command before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$TEST_CODEX_BIN\")\"; printf \"#!/usr/bin/env bash\\nexit 0\\n\" > \"\$TEST_CODEX_BIN\"; chmod +x \"\$TEST_CODEX_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_codex_marker)\" ]; [ ! -s \"\$NPM_LOG\" ]; exit \"\${rc:-0}\""

assert_status "codex install refuses unmanaged package dir before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$TEST_CODEX_PACKAGE_DIR\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_codex_marker)\" ]; [ ! -s \"\$NPM_LOG\" ]; exit \"\${rc:-0}\""

assert_status "codex install refuses non-executable npm before mutation" 1 \
  bash -c "$PRE; chmod -x \"\$TEST_NPM_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_codex_marker)\" ]; [ ! -s \"\$NPM_LOG\" ]; exit \"\${rc:-0}\""

assert_status "codex install refuses wrong npm owner before mutation" 1 \
  bash -c "$PRE; NPM_RPM_OWNER=evil-npm; export NPM_RPM_OWNER; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_codex_marker)\" ]; [ ! -s \"\$NPM_LOG\" ]; exit \"\${rc:-0}\""

assert_status "codex install writes installing marker before npm" 0 \
  bash -c "$PRE; NPM_ASSERT_MARKER_INSTALLING=1; export NPM_ASSERT_MARKER_INSTALLING; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_codex_marker)\""

assert_status "codex install uses exact npm package command" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; actual=\"\$(cat \"\$NPM_LOG\")\"; expected=\"install -g @openai/codex --prefix \$TEST_CODEX_PREFIX --no-audit --no-fund\"; [ \"\$actual\" = \"\$expected\" ]"

assert_status "codex install promotes marker only after validation" 1 \
  bash -c "$PRE; CODEX_OK=0; export CODEX_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_codex_marker)\"; exit \"\${rc:-0}\""

assert_status "codex install leaves installing marker after npm failure" 1 \
  bash -c "$PRE; NPM_OK=0; export NPM_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_codex_marker)\"; exit \"\${rc:-0}\""

assert_status "codex install repairs installing marker" 0 \
  bash -c "$PRE; _codex_marker_write installing; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_codex_marker)\"; module::verify"

assert_status "codex repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_codex_marker)\" \"\$HOME/marker1\"; module::install >/dev/null 2>&1; cmp -s \"\$HOME/marker1\" \"\$(_codex_marker)\"; module::verify"

assert_status "codex repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "codex probes ignore hostile PATH shims and environment" 0 \
  bash -c "$PRE; mkdir -p \"\$HOME/bin\"; printf \"#!/usr/bin/env bash\\nexit 99\\n\" > \"\$HOME/bin/codex\"; chmod +x \"\$HOME/bin/codex\"; PATH=\"\$HOME/bin:\$PATH\"; OPENAI_API_KEY=secret; CODEX_HOME=/bad; NPM_CONFIG_PREFIX=/bad/prefix; npm_config_prefix=/bad/prefix; NODE_OPTIONS=--bad; NODE_PATH=/bad/node; export PATH OPENAI_API_KEY CODEX_HOME NPM_CONFIG_PREFIX npm_config_prefix NODE_OPTIONS NODE_PATH; module::install >/dev/null 2>&1; module::verify"

assert_status "codex install and verify only run codex --version" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify >/dev/null 2>&1; if grep -vx -- \"--version\" \"\$CODEX_ARGV_LOG\" >/dev/null; then exit 1; fi"

assert_status "codex update refreshes npm package" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; : > \"\$NPM_LOG\"; module::update >/dev/null 2>&1; module::verify; grep -qxF \"install -g @openai/codex --prefix \$TEST_CODEX_PREFIX --no-audit --no-fund\" \"\$NPM_LOG\""

assert_status "codex backup is a documented no-op" 0 \
  bash -c "$PRE; module::backup"

assert_status "codex restore is a documented no-op" 0 \
  bash -c "$PRE; module::restore"

assert_status "codex remove is a no-op when never installed" 0 \
  bash -c "$PRE; module::remove"

assert_status "codex remove deletes only Atlas package and marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; : > \"\$NPM_LOG\"; module::remove >/dev/null 2>&1; [ ! -e \"\$(_codex_marker)\" ]; [ ! -e \"\$TEST_CODEX_BIN\" ]; [ ! -e \"\$TEST_CODEX_PACKAGE_DIR\" ]; grep -qxF \"uninstall -g @openai/codex --prefix \$TEST_CODEX_PREFIX --no-audit --no-fund\" \"\$NPM_LOG\""

assert_status "codex remove refuses command ownership drift" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$TEST_CODEX_BIN\"; printf \"#!/usr/bin/env bash\\nexit 0\\n\" > \"\$TEST_CODEX_BIN\"; chmod +x \"\$TEST_CODEX_BIN\"; module::remove"

assert_status "codex remove refuses package metadata drift" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf '{\"name\":\"other\"}\n' > \"\$TEST_CODEX_PACKAGE_DIR/package.json\"; module::remove"

assert_status "codex runner status reports not installed before marker" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"$ATLAS_ROOT/internal/module.sh\"; source \"$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/codex 2>&1); case \"\$out\" in *\"not installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "codex runner status reports installed after marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; set +e; set -uo pipefail; source \"$ATLAS_ROOT/internal/module.sh\"; source \"$ATLAS_ROOT/internal/runner.sh\"; out=\$(runner::run status development/codex 2>&1); case \"\$out\" in *\"installed\"*) exit 0 ;; *) exit 1 ;; esac"

assert_status "codex runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"$ATLAS_ROOT/internal/module.sh\"; source \"$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor development/codex"
