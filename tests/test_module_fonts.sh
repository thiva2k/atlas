#!/usr/bin/env bash
# desktop/fonts - RFC-0008
#
# Tests sandbox XDG/Atlas state and mock DNF, download, extraction, fc-cache,
# fc-list, and fc-match. No test installs host fonts or refreshes host caches.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
DOWNLOAD_LOG="$HOME/download.log"; export DOWNLOAD_LOG
FC_CACHE_LOG="$HOME/fc-cache.log"; export FC_CACHE_LOG
: > "$DNF_LOG"; : > "$DOWNLOAD_LOG"; : > "$FC_CACHE_LOG"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/fonts/module.sh"

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::dnf_install() {
  printf "%s\n" "$*" >> "$DNF_LOG"
  [ "${DNF_FAIL:-0}" = 1 ] && return 1
  local pkg
  for pkg in "$@"; do
    [ "$pkg" = rsms-inter-fonts ] && INTER_INSTALLED=1
  done
  export INTER_INSTALLED
}
_fonts_fetch_nerd_archive() {
  printf "%s\n" "$1 $2" >> "$DOWNLOAD_LOG"
  [ "${DOWNLOAD_FAIL:-0}" = 1 ] && return 1
  printf "archive\n" > "$1"
  printf "checksum\n" > "$2"
}
_fonts_verify_nerd_archive() {
  [ "${CHECKSUM_FAIL:-0}" = 1 ] && return 1
  return 0
}
_fonts_extract_nerd_archive() {
  [ "${EXTRACT_FAIL:-0}" = 1 ] && return 1
  mkdir -p "$(_fonts_font_dir)"
  printf "font\n" > "$(_fonts_font_dir)/JetBrainsMonoNerdFont-Regular.ttf"
  JETBRAINS_INSTALLED=1
  export JETBRAINS_INSTALLED
}
_fonts_fc_cache() {
  printf "%s\n" "$*" >> "$FC_CACHE_LOG"
  [ "${FC_CACHE_FAIL:-0}" = 1 ] && return 1
  return 0
}
fc-list() {
  [ "${FC_LIST_FAIL:-0}" = 1 ] && return 1
  if [ "${JETBRAINS_INSTALLED:-0}" = 1 ]; then printf "%s\n" "$(_fonts_font_dir)/JetBrainsMonoNerdFont-Regular.ttf: JetBrainsMono Nerd Font:style=Regular"; fi
  if [ "${INTER_INSTALLED:-0}" = 1 ]; then printf "%s\n" "/usr/share/fonts/rsms-inter/Inter-Regular.otf: Inter:style=Regular"; fi
}
fc-match() {
  case "${1:-}" in
    "JetBrainsMono Nerd Font")
      [ "${JETBRAINS_MATCH_FAIL:-0}" = 1 ] && { printf "NotoSans-Regular.ttf: Noto Sans\n"; return 0; }
      [ "${JETBRAINS_INSTALLED:-0}" = 1 ] && { printf "JetBrainsMonoNerdFont-Regular.ttf: JetBrainsMono Nerd Font\n"; return 0; }
      printf "NotoSans-Regular.ttf: Noto Sans\n"
      ;;
    Inter)
      [ "${INTER_MATCH_FAIL:-0}" = 1 ] && { printf "NotoSans-Regular.ttf: Noto Sans\n"; return 0; }
      [ "${INTER_INSTALLED:-0}" = 1 ] && { printf "Inter-Regular.otf: Inter\n"; return 0; }
      printf "NotoSans-Regular.ttf: Noto Sans\n"
      ;;
    *) return 1 ;;
  esac
}
'
PRE="${PRE%$'\n'}"

assert_status "fonts verify passes before install" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; JETBRAINS_INSTALLED=1 INTER_INSTALLED=1; export JETBRAINS_INSTALLED INTER_INSTALLED; module::verify" 2>&1)"
assert_contains "fonts verify reports unmanaged matching fonts" "$out" "not installed by Atlas"

assert_status "fonts check fails before install" 1 \
  bash -c "$PRE; module::check"

assert_status "fonts install refuses pre-existing Atlas font dir before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$(_fonts_font_dir)\"; printf \"user font\n\" > \"\$(_fonts_font_dir)/user.ttf\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_fonts_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "fonts install fails on non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_fonts_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "fonts install refuses font dir outside HOME before mutation" 1 \
  bash -c "$PRE; XDG_DATA_HOME=/tmp/atlas-fonts-outside-home; export XDG_DATA_HOME; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_fonts_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")"
assert_eq "fonts install uses exact package set" "$out" "fontconfig curl xz rsms-inter-fonts"

assert_status "fonts install writes installed marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_fonts_marker)\""

assert_status "fonts install writes Atlas font files" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ -r \"\$(_fonts_font_dir)/JetBrainsMonoNerdFont-Regular.ttf\" ]"

assert_status "fonts install refreshes font cache" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF \"\$(_fonts_font_dir)\" \"\$FC_CACHE_LOG\""

assert_status "fonts verify passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"

assert_status "fonts check passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::check"

assert_status "fonts repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_fonts_marker)\" \"\$HOME/marker1\"; : > \"\$DOWNLOAD_LOG\"; module::install >/dev/null 2>&1; module::verify; cmp -s \"\$HOME/marker1\" \"\$(_fonts_marker)\"; [ ! -s \"\$DOWNLOAD_LOG\" ]"

assert_status "fonts repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "fonts verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_fonts_marker)\")\"; printf \"state=installed\n\" > \"\$(_fonts_marker)\"; module::verify"

assert_status "fonts verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _fonts_marker_write installed; chmod 644 \"\$(_fonts_marker)\"; module::verify"

assert_status "fonts verify fails on installing marker" 1 \
  bash -c "$PRE; _fonts_marker_write installing; module::verify"

assert_status "fonts verify fails when fc-list fails" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; FC_LIST_FAIL=1; export FC_LIST_FAIL; module::verify"

assert_status "fonts verify fails when JetBrainsMono Nerd Font does not match" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; JETBRAINS_MATCH_FAIL=1; export JETBRAINS_MATCH_FAIL; module::verify"

assert_status "fonts verify fails when Inter does not match" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; INTER_MATCH_FAIL=1; export INTER_MATCH_FAIL; module::verify"

assert_status "fonts package failure leaves installing marker" 1 \
  bash -c "$PRE; DNF_FAIL=1; export DNF_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_fonts_marker)\"; exit \"\${rc:-0}\""

assert_status "fonts download failure leaves installing marker" 1 \
  bash -c "$PRE; DOWNLOAD_FAIL=1; export DOWNLOAD_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_fonts_marker)\"; exit \"\${rc:-0}\""

assert_status "fonts checksum failure leaves installing marker" 1 \
  bash -c "$PRE; CHECKSUM_FAIL=1; export CHECKSUM_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_fonts_marker)\"; exit \"\${rc:-0}\""

assert_status "fonts update restores missing Atlas font files" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$(_fonts_font_dir)/JetBrainsMonoNerdFont-Regular.ttf\"; JETBRAINS_INSTALLED=0; export JETBRAINS_INSTALLED; module::update >/dev/null 2>&1; module::verify"

assert_status "fonts remove detaches and deletes only Atlas font dir" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_fonts_marker)\"; [ ! -e \"\$(_fonts_font_dir)\" ]; [ \"\${INTER_INSTALLED:-0}\" = 1 ]"

assert_status "fonts remove is idempotent after detach" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; module::remove"

assert_status "fonts detached reinstall refuses user-created Atlas font dir" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; mkdir -p \"\$(_fonts_font_dir)\"; printf \"user\n\" > \"\$(_fonts_font_dir)/user.ttf\"; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF \"user\" \"\$(_fonts_font_dir)/user.ttf\"; exit \"\${rc:-0}\""

assert_status "fonts backup is a documented no-op" 0 \
  bash -c "$PRE; module::backup"

assert_status "fonts restore is a documented no-op" 0 \
  bash -c "$PRE; module::restore"

assert_status "fonts runner verify succeeds before install" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run verify desktop/fonts"

assert_status "fonts runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor desktop/fonts"
