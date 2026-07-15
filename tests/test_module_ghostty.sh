#!/usr/bin/env bash
# development/ghostty - RFC-0007
#
# The tests sandbox HOME/XDG/ATLAS state and mock DNF/RPM/Fedora probes. No test
# touches the host Ghostty install, host COPR repos, /etc, or a GUI session.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_CONFIG_HOME="$HOME/.config"; export XDG_CONFIG_HOME
ATLAS_CONFIG_HOME="$HOME/.config/atlas"; export ATLAS_CONFIG_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
GHOSTTY_CONFIG_DIR="$XDG_CONFIG_HOME/ghostty"; export GHOSTTY_CONFIG_DIR
GHOSTTY_REPO_FILE="$HOME/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:scottames:ghostty.repo"; export GHOSTTY_REPO_FILE
GHOSTTY_DESKTOP_FILE="$HOME/share/applications/com.mitchellh.ghostty.desktop"; export GHOSTTY_DESKTOP_FILE
GHOSTTY_BIN="$HOME/bin/ghostty"; export GHOSTTY_BIN
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
: > "$DNF_LOG"
mkdir -p "$HOME/bin" "$(dirname "$GHOSTTY_REPO_FILE")" "$(dirname "$GHOSTTY_DESKTOP_FILE")"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/ghostty/module.sh"

_ghostty_repo_file() { printf "%s\n" "$GHOSTTY_REPO_FILE"; }
_ghostty_desktop_file() { printf "%s\n" "$GHOSTTY_DESKTOP_FILE"; }
_ghostty_binary() { printf "%s\n" "$GHOSTTY_BIN"; }

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::has_cmd() {
  case "$1" in
    ghostty) [ -x "$GHOSTTY_BIN" ] ;;
    dnf) [ "${DNF_PRESENT:-1}" = 1 ] ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}
os::dnf_install() {
  printf "%s\n" "$*" >> "$DNF_LOG"
  [ "${DNF_FAIL:-0}" = 1 ] && return 1
  local pkg
  for pkg in "$@"; do
    case "$pkg" in
      dnf-plugins-core) DNF_COPR=1; export DNF_COPR ;;
      ghostty)
        GHOSTTY_RPM_OWNER=ghostty; export GHOSTTY_RPM_OWNER
        cat > "$GHOSTTY_BIN" <<EOF
#!/usr/bin/env bash
[ "\${1:-}" = "--version" ] && { printf "Ghostty 1.2.3 (mock)\n"; exit 0; }
exit 0
EOF
        chmod +x "$GHOSTTY_BIN"
        printf "[Desktop Entry]\nName=Ghostty\nExec=ghostty\n" > "$GHOSTTY_DESKTOP_FILE"
        ;;
    esac
  done
}
_ghostty_run_privileged() {
  case "$*" in
    "dnf -y copr enable scottames/ghostty")
      [ "${COPR_FAIL:-0}" = 1 ] && return 1
      DNF_COPR=1; export DNF_COPR
      printf "[copr:copr.fedorainfracloud.org:scottames:ghostty]\nname=Copr repo for ghostty owned by scottames\nbaseurl=https://download.copr.fedorainfracloud.org/results/scottames/ghostty/fedora-\$releasever-\$basearch/\nenabled=1\ngpgcheck=1\n" > "$GHOSTTY_REPO_FILE"
      ;;
    *) "$@" ;;
  esac
}
_ghostty_dnf_copr_available() { [ "${DNF_COPR:-0}" = 1 ]; }
rpm() {
  case "$*" in
    "-qf $GHOSTTY_BIN")
      [ "${GHOSTTY_RPM_OWNER:-}" = ghostty ] && printf "ghostty-1.2.3-1.fc99.x86_64\n" && return 0
      [ -n "${GHOSTTY_RPM_OWNER:-}" ] && printf "%s-1.0-1.fc99.x86_64\n" "$GHOSTTY_RPM_OWNER" && return 0
      return 1
      ;;
  esac
  return 1
}
'
PRE="${PRE%$'\n'}"

assert_status "ghostty verify passes before install (not installed)" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; : > \"\$GHOSTTY_BIN\"; chmod +x \"\$GHOSTTY_BIN\"; module::verify" 2>&1)"
assert_contains "ghostty verify treats unmanaged binary as user-owned" "$out" "not installed by Atlas"

assert_status "ghostty check fails before install" 1 \
  bash -c "$PRE; module::check"

assert_status "ghostty install refuses existing config.ghostty before mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$GHOSTTY_CONFIG_DIR\"; printf \"font-size = 20\n\" > \"\$GHOSTTY_CONFIG_DIR/config.ghostty\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_ghostty_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "ghostty install refuses unmanaged binary before mutation" 1 \
  bash -c "$PRE; : > \"\$GHOSTTY_BIN\"; chmod +x \"\$GHOSTTY_BIN\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_ghostty_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "ghostty install fails on non-Fedora before mutation" 1 \
  bash -c "$PRE; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_ghostty_marker)\" ]; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

out="$(bash -c "$PRE; DNF_COPR=0; export DNF_COPR; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")"
assert_contains "ghostty installs dnf-plugins-core when copr plugin is absent" "$out" "dnf-plugins-core"
assert_contains "ghostty installs ghostty package" "$out" "ghostty"

assert_status "ghostty install writes installed marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_ghostty_marker)\""

assert_status "ghostty install writes managed config and theme" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ -r \"\$GHOSTTY_CONFIG_DIR/config.ghostty\" ]; [ -r \"\$GHOSTTY_CONFIG_DIR/themes/atlas-reference\" ]"

assert_status "ghostty config exposes user override seam" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF \"config-file = ?user.ghostty\" \"\$GHOSTTY_CONFIG_DIR/config.ghostty\""

assert_status "ghostty user override seam remains last" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ \"\$(tail -n 1 \"\$GHOSTTY_CONFIG_DIR/config.ghostty\")\" = \"config-file = ?user.ghostty\" ]"

assert_status "ghostty experience config includes developer defaults" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cfg=\"\$GHOSTTY_CONFIG_DIR/config.ghostty\"; grep -qxF \"window-padding-x = 10\" \"\$cfg\"; grep -qxF \"window-padding-y = 8\" \"\$cfg\"; grep -qxF \"window-padding-balance = true\" \"\$cfg\"; grep -qxF \"adjust-cell-height = 6%\" \"\$cfg\"; grep -qxF \"font-feature = -calt, -liga, -dlig\" \"\$cfg\"; grep -qxF \"cursor-style = bar\" \"\$cfg\"; grep -qxF \"scrollback-limit = 50000000\" \"\$cfg\"; grep -qxF \"window-save-state = never\" \"\$cfg\"; grep -qxF \"window-inherit-working-directory = true\" \"\$cfg\"; grep -qxF \"tab-inherit-working-directory = true\" \"\$cfg\"; grep -qxF \"split-inherit-working-directory = true\" \"\$cfg\""

# RFC-0034: the HUD "glass instrument" feel — the cursor is the one live element
# (a blinking cyan bar), the terminal is subtly translucent, split seams read as
# dividers.
assert_status "ghostty config carries the HUD glass + live cursor" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cfg=\"\$GHOSTTY_CONFIG_DIR/config.ghostty\"; grep -qxF \"background-opacity = 0.94\" \"\$cfg\"; grep -qxF \"background-blur-radius = 20\" \"\$cfg\"; grep -qxF \"split-divider-color = 243247\" \"\$cfg\"; grep -qxF \"cursor-style = bar\" \"\$cfg\"; grep -qxF \"cursor-style-blink = true\" \"\$cfg\""

# RFC-0034: the theme carries the locked HUD palette (cursor earns the scarce cyan;
# blue migrated #4ea1ff->#5aa2ff, cyan #7dd3fc->#57e5ff, red ->#ff6b5a). Opacity is a
# config concern, never in the theme file.
assert_status "ghostty theme uses the locked HUD palette" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; theme=\"\$GHOSTTY_CONFIG_DIR/themes/atlas-reference\"; grep -qxF \"background = 0f141b\" \"\$theme\"; grep -qxF \"foreground = e6edf3\" \"\$theme\"; grep -qxF \"cursor-color = 57e5ff\" \"\$theme\"; grep -qxF \"palette = 4=#5aa2ff\" \"\$theme\"; grep -qxF \"palette = 6=#57e5ff\" \"\$theme\"; grep -qxF \"palette = 1=#ff6b5a\" \"\$theme\"; ! grep -q \"4ea1ff\" \"\$theme\"; ! grep -q \"background-opacity\" \"\$theme\"; ! grep -q \"background-blur\" \"\$theme\""

assert_status "ghostty user override file is preserved" 0 \
  bash -c "$PRE; mkdir -p \"\$GHOSTTY_CONFIG_DIR\"; printf \"font-size = 99\n\" > \"\$GHOSTTY_CONFIG_DIR/config\"; printf \"font-size = 18\n\" > \"\$GHOSTTY_CONFIG_DIR/user.ghostty\"; module::install >/dev/null 2>&1; grep -qxF \"font-size = 18\" \"\$GHOSTTY_CONFIG_DIR/user.ghostty\"; grep -qxF \"font-size = 99\" \"\$GHOSTTY_CONFIG_DIR/config\""

assert_status "ghostty verify passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"

assert_status "ghostty check passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::check"

assert_status "ghostty repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_ghostty_marker)\" \"\$HOME/marker1\"; cp \"\$GHOSTTY_CONFIG_DIR/config.ghostty\" \"\$HOME/config1\"; module::install >/dev/null 2>&1; module::verify; cmp -s \"\$HOME/marker1\" \"\$(_ghostty_marker)\"; cmp -s \"\$HOME/config1\" \"\$GHOSTTY_CONFIG_DIR/config.ghostty\""

assert_status "ghostty repeated verify is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify; module::verify"

assert_status "ghostty verify fails when marker is malformed" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_ghostty_marker)\")\"; printf \"state=installed\n\" > \"\$(_ghostty_marker)\"; module::verify"

assert_status "ghostty verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _ghostty_marker_write installed; chmod 644 \"\$(_ghostty_marker)\"; module::verify"

assert_status "ghostty verify fails when marker hash is truncated" 1 \
  bash -c "$PRE; _ghostty_marker_write installed; sed -i \"s/^config_sha256=.*/config_sha256=deadbeef/\" \"\$(_ghostty_marker)\"; module::verify"

assert_status "ghostty verify fails when managed config drifts" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"font-size = 99\n\" >> \"\$GHOSTTY_CONFIG_DIR/config.ghostty\"; module::verify"

assert_status "ghostty verify fails when managed theme drifts" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"background = ff0000\n\" >> \"\$GHOSTTY_CONFIG_DIR/themes/atlas-reference\"; module::verify"

assert_status "ghostty verify fails when desktop launcher is missing" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$GHOSTTY_DESKTOP_FILE\"; module::verify"

assert_status "ghostty verify fails when COPR repo disables gpgcheck" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; sed -i \"s/gpgcheck=1/gpgcheck=0/\" \"\$GHOSTTY_REPO_FILE\"; module::verify"

assert_status "ghostty package failure leaves installing marker" 1 \
  bash -c "$PRE; DNF_FAIL=1; export DNF_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_ghostty_marker)\"; exit \"\${rc:-0}\""

assert_status "ghostty copr failure leaves installing marker" 1 \
  bash -c "$PRE; COPR_FAIL=1; export COPR_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_ghostty_marker)\"; exit \"\${rc:-0}\""

assert_status "ghostty update restores managed config drift" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"font-size = 99\n\" >> \"\$GHOSTTY_CONFIG_DIR/config.ghostty\"; module::update >/dev/null 2>&1; module::verify"

assert_status "ghostty remove detaches and deletes only Atlas files" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"font-size = 18\n\" > \"\$GHOSTTY_CONFIG_DIR/user.ghostty\"; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_ghostty_marker)\"; [ ! -e \"\$GHOSTTY_CONFIG_DIR/config.ghostty\" ]; [ ! -e \"\$GHOSTTY_CONFIG_DIR/themes/atlas-reference\" ]; grep -qxF \"font-size = 18\" \"\$GHOSTTY_CONFIG_DIR/user.ghostty\""

assert_status "ghostty remove is idempotent after detach" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; module::remove"

assert_status "ghostty detached reinstall refuses user-created config" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; printf \"font-size = 22\n\" > \"\$GHOSTTY_CONFIG_DIR/config.ghostty\"; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF \"font-size = 22\" \"\$GHOSTTY_CONFIG_DIR/config.ghostty\"; exit \"\${rc:-0}\""

assert_status "ghostty remove refuses drifted managed config" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; printf \"font-size = 99\n\" >> \"\$GHOSTTY_CONFIG_DIR/config.ghostty\"; module::remove"

assert_status "ghostty backup is a documented no-op" 0 \
  bash -c "$PRE; module::backup"

assert_status "ghostty restore is a documented no-op" 0 \
  bash -c "$PRE; module::restore"

assert_status "ghostty runner verify succeeds before install" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run verify development/ghostty"

assert_status "ghostty runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor development/ghostty"
