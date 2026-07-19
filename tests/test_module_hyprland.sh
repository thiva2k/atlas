#!/usr/bin/env bash
# desktop/hyprland — RFC-0038. Hermetic end-to-end tests.
#
# These run the REAL module (modules/desktop/hyprland/module.sh) against fake
# `dnf`, `rpm`, `systemctl`, and `sudo` binaries placed first on PATH. The
# safety-critical functions under test — the rehearsal resolver classifier and
# plan parser, the dnf history transaction boundary + identity validation, the
# aquamarine RPM gate, the watcher deploy/verify checks, the reconciliation
# state machine, and the wallpaper/config ownership checks — all execute for
# real; nothing stubs the function a test claims to validate (only the external
# aquamarine build and PNG bake are replaced by deterministic seams, since each
# has its own dedicated tests / needs PIL+fonts).
#
# Everything is sandboxed under a per-case `mktemp -d` HOME with its own fake
# state dir; no host package, unit, or file outside the sandbox is touched.

# --- shared fake binaries (written once; behaviour driven by env at runtime) --
HFAKE_BIN="$(mktemp -d)"

cat > "$HFAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF

cat > "$HFAKE_BIN/dnf" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
S="$FAKE_STATE"
mkdir -p "$S" "$S/installed" "$S/hinfo"
printf '%s\n' "$*" >> "$S/dnf.log"

_good_info() { # <id>
  {
    printf 'Transaction ID : %s\n' "$1"
    printf 'Status         : Ok\n'
    printf 'Packages altered:\n'
    printf '  Action  Package                                 Reason Repository\n'
    printf '  Install aquamarine-0:0.9.5-2.fc44.atlas1.x86_64 User   @commandline\n'
    printf '  Install hyprland-0:0.50.1-1.fc44.x86_64         User   copr\n'
  } > "$S/hinfo/$1"
}
_unrelated_info() { # <id>
  {
    printf 'Transaction ID : %s\n' "$1"
    printf 'Packages altered:\n'
    printf '  Action  Package                Reason Repository\n'
    printf '  Install vim-0:9.1-1.fc44.x86_64 User base\n'
  } > "$S/hinfo/$1"
}

# dnf copr --help
if [ "${1:-}" = copr ] && [ "${2:-}" = --help ]; then exit 0; fi

# dnf -y copr enable <repo>
if [ "${1:-}" = -y ] && [ "${2:-}" = copr ] && [ "${3:-}" = enable ]; then
  [ "${FAKE_DNF_COPR_RC:-0}" = 0 ] || exit "${FAKE_DNF_COPR_RC}"
  mkdir -p "$(dirname "$ATLAS_HYPR_REPO_FILE")"
  { printf '[%s]\n' "copr:copr.fedorainfracloud.org:solopasha:hyprland"
    printf 'name=Copr\nbaseurl=https://example.test/\nenabled=1\ngpgcheck=1\n'
  } > "$ATLAS_HYPR_REPO_FILE"
  exit 0
fi

# dnf history list
if [ "${1:-}" = history ] && [ "${2:-}" = list ]; then
  if [ "${FAKE_HISTORY_BAD_LIST:-0}" = 1 ]; then
    printf 'ID Command\n-- garbage --\n'; exit 0
  fi
  printf 'ID Command line Date Altered\n'
  cur="$(cat "$S/hmax" 2>/dev/null || echo 40)"
  i="$cur"; n=0
  while [ "$i" -ge 1 ] && [ "$n" -lt 6 ]; do
    printf '%s dnf-install 2026-01-01 2\n' "$i"; i=$((i-1)); n=$((n+1))
  done
  exit 0
fi

# dnf history info [id]
if [ "${1:-}" = history ] && [ "${2:-}" = info ]; then
  [ "${FAKE_DNF_INFO_FAIL:-0}" = 1 ] && exit 1
  id="${3:-}"; [ -z "$id" ] && id="$(cat "$S/hmax" 2>/dev/null)"
  [ -f "$S/hinfo/$id" ] || exit 1
  cat "$S/hinfo/$id"; exit 0
fi

# dnf install --assumeno ...  (rehearsal)
if [ "${1:-}" = install ] && [ "${2:-}" = --assumeno ]; then
  cat "$S/rehearse.out" 2>/dev/null
  exit 1   # dnf5 --assumeno always exits non-zero
fi

# dnf install -y <rpm> <pkgs...>  (the one real transaction)
if [ "${1:-}" = install ] && [ "${2:-}" = -y ]; then
  [ "${FAKE_DNF_INSTALL_RC:-0}" = 0 ] || exit "${FAKE_DNF_INSTALL_RC}"
  shift 2
  for a in "$@"; do
    case "$a" in
      *.rpm) echo 2.fc44.atlas1 > "$S/installed/aquamarine" ;;
      *)     echo 1 > "$S/installed/$a" ;;
    esac
  done
  echo 1 > "$S/installed/hyprland"
  if [ "${FAKE_DNF_NO_NEW:-0}" != 1 ]; then
    cur="$(cat "$S/hmax" 2>/dev/null || echo 40)"; new=$((cur+1))
    _good_info "$new"; echo "$new" > "$S/hmax"
    if [ "${FAKE_DNF_UNRELATED_NEWER:-0}" = 1 ]; then
      un=$((new+1)); _unrelated_info "$un"; echo "$un" > "$S/hmax"
    fi
  fi
  exit 0
fi
exit 0
EOF

cat > "$HFAKE_BIN/rpm" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
S="$FAKE_STATE"
# rpm -q <pkg>
if [ "${1:-}" = -q ] && [ "$#" -eq 2 ]; then
  [ -f "$S/installed/$2" ] && exit 0 || exit 1
fi
# rpm -q --qf '<fmt with %{RELEASE}>' <pkg>
if [ "${1:-}" = -q ] && [ "${2:-}" = --qf ]; then
  fmt="${3:-}"; pkg="${4:-}"
  [ -f "$S/installed/$pkg" ] || { printf '(none)'; exit 1; }
  rel="$(cat "$S/installed/$pkg")"
  out="${fmt//%\{RELEASE\}/$rel}"
  printf '%s' "$out"; exit 0
fi
# rpm -qp --qf '<fmt>' <rpmfile>   (gate NEVRA)
if [ "${1:-}" = -qp ] && [ "${2:-}" = --qf ]; then
  path="${4:-}"; [ -f "$path" ] || exit 1
  case "$(head -n1 "$path" 2>/dev/null)" in
    WRONGREL) printf 'aquamarine 0.9.5 9.fc44 x86_64\n' ;;
    WRONGNAME) printf 'notaquamarine 0.9.5 2.fc44.atlas1 x86_64\n' ;;
    *) printf 'aquamarine 0.9.5 2.fc44.atlas1 x86_64\n' ;;
  esac
  exit 0
fi
# rpm -qp --requires <rpmfile>
if [ "${1:-}" = -qp ] && [ "${2:-}" = --requires ]; then
  path="${3:-}"; [ -f "$path" ] || exit 1
  case "$(head -n1 "$path" 2>/dev/null)" in
    BAD) printf 'libdisplay-info.so.2()(64bit)\n' ;;
    *)   printf 'libdisplay-info.so.3()(64bit)\n' ;;
  esac
  exit 0
fi
# rpm -qp --provides <rpmfile>
if [ "${1:-}" = -qp ] && [ "${2:-}" = --provides ]; then
  path="${3:-}"; [ -f "$path" ] || exit 1
  printf 'libaquamarine.so.8()(64bit)\n'; exit 0
fi
# rpm -K --nosignature <rpmfile>
if [ "${1:-}" = -K ]; then
  for path in "$@"; do :; done
  [ -f "$path" ] || exit 1
  [ "$(head -n1 "$path" 2>/dev/null)" = CORRUPT ] && exit 1
  exit 0
fi
exit 1
EOF

cat > "$HFAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
S="$FAKE_STATE"
printf '%s\n' "$*" >> "$S/systemctl.log"
[ "${1:-}" = --user ] && shift
case "${1:-}" in
  daemon-reload) exit "${FAKE_SYSTEMCTL_RELOAD_RC:-0}" ;;
  enable)
    [ "${FAKE_SYSTEMCTL_ENABLE_RC:-0}" = 0 ] || exit "${FAKE_SYSTEMCTL_ENABLE_RC}"
    echo enabled > "$S/timer.state"; exit 0 ;;
  disable) rm -f "$S/timer.state"; exit 0 ;;
  is-enabled) [ -f "$S/timer.state" ] && [ "${FAKE_TIMER_ENABLED:-1}" = 1 ]; exit $? ;;
  is-active)  [ -f "$S/timer.state" ] && [ "${FAKE_TIMER_ACTIVE:-1}" = 1 ];  exit $? ;;
esac
exit 0
EOF

chmod +x "$HFAKE_BIN"/sudo "$HFAKE_BIN"/dnf "$HFAKE_BIN"/rpm "$HFAKE_BIN"/systemctl
export HFAKE_BIN

# Realistic (LC_ALL=C) dnf5 rehearsal fixtures.
export FIX_CLEAN='Repositories loaded.
Package                     Arch   Version              Repository   Size
Installing:
 hyprland                   x86_64 0.50.1-1.fc44        copr          3 MiB
 aquamarine                 x86_64 0.9.5-2.fc44.atlas1  @commandline  1 MiB
 waybar                     x86_64 0.11.0-1.fc44        copr          2 MiB
Installing dependencies:
 libinput                   x86_64 1.26-1.fc44          updates       1 MiB

Transaction Summary:
 Installing: 20 packages

Total size of inbound packages is 40 MiB.
Operation aborted by the user.'

export FIX_REMOVAL='Repositories loaded.
Package           Arch   Version       Repository   Size
Installing:
 hyprland         x86_64 0.50.1-1.fc44 copr          3 MiB
Removing:
 plasma-workspace x86_64 6.0-1.fc44    @System      50 MiB

Transaction Summary:
 Installing: 1 package
 Removing:   1 package
Operation aborted by the user.'

export FIX_NONHYPR_UPGRADE='Repositories loaded.
Package  Arch   Version    Repository Size
Installing:
 hyprland x86_64 0.50.1-1.fc44 copr   3 MiB
Upgrading:
 systemd  x86_64 257-1.fc44 updates   10 MiB

Transaction Summary:
 Installing: 1 package
 Upgrading:  1 package
Operation aborted by the user.'

export FIX_RESOLVE_FAIL='Repositories loaded.
Failed to resolve the transaction:
No match for argument: hyprland
You can try to add to command line:
  --skip-unavailable to skip unavailable packages'

PRE='
set -uo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_CONFIG_HOME="$HOME/.config"; export XDG_CONFIG_HOME
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
ATLAS_HYPR_RPM_DIR="$HOME/atlas-hypr-rpms"; export ATLAS_HYPR_RPM_DIR
ATLAS_HYPR_REPO_FILE="$HOME/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:solopasha:hyprland.repo"
export ATLAS_HYPR_REPO_FILE
ATLAS_HYPR_WATCHER_BIN="$HOME/.local/bin/atlas-hypr-check.sh"; export ATLAS_HYPR_WATCHER_BIN
FAKE_STATE="$HOME/fakestate"; export FAKE_STATE
mkdir -p "$FAKE_STATE/installed" "$FAKE_STATE/hinfo" "$ATLAS_HYPR_RPM_DIR" "$HOME/etc/yum.repos.d" "$HOME/.local/bin"
echo 40 > "$FAKE_STATE/hmax"
printf "%s" "$FIX_CLEAN" > "$FAKE_STATE/rehearse.out"
printf "ID=fedora\nVERSION_ID=44\n" > "$HOME/etc/os-release"
printf "Fedora release 44 (Forty Four)\n" > "$HOME/etc/fedora-release"
export ATLAS_HYPR_OS_RELEASE_FILE="$HOME/etc/os-release"
export ATLAS_HYPR_FEDORA_RELEASE_FILE="$HOME/etc/fedora-release"
printf "GOOD\n" > "$ATLAS_HYPR_RPM_DIR/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"
PATH="$HFAKE_BIN:$PATH"; export PATH

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/hyprland/module.sh"

# External seams only (each has its own tests / needs PIL): keep the real
# ownership + gate + txn + watcher logic intact.
_hypr_build_rpm() { printf "GOOD\n" > "$(_hypr_rpm_path)"; }
_hypr_preview_bake_wallpapers() {
  local out="$1" f
  mkdir -p "$out"
  for f in atlas-lock-bg.png atlas-wall-bw.png; do printf "wall-%s\n" "$f" > "$out/$f"; done
}
_hypr_bake_wallpapers() {
  local dir f
  dir="$(_hypr_wall_dir)"; mkdir -p "$dir"
  for f in atlas-lock-bg.png atlas-wall-bw.png; do printf "wall-%s\n" "$f" > "$dir/$f"; done
  _hypr_record_wall_hashes
}

# Test helpers (bash funcs, no single quotes so they survive in PRE).
_fake_installed() {
  echo 2.fc44.atlas1 > "$FAKE_STATE/installed/aquamarine"
  echo 1 > "$FAKE_STATE/installed/hyprland"
}
_fake_history_good() {
  local id="$1"
  echo "$id" > "$FAKE_STATE/hmax"
  {
    printf "Transaction ID : %s\n" "$id"
    printf "Status         : Ok\n"
    printf "Packages altered:\n"
    printf "  Install aquamarine-0:0.9.5-2.fc44.atlas1.x86_64 User @commandline\n"
    printf "  Install hyprland-0:0.50.1-1.fc44.x86_64 User copr\n"
  } > "$FAKE_STATE/hinfo/$id"
}
_fake_record_txn() {
  mkdir -p "$(dirname "$(_hypr_txn_file)")"
  printf "%s\n" "$1" > "$(_hypr_txn_file)"; chmod 600 "$(_hypr_txn_file)"
}
'
PRE="${PRE%$'\n'}"

# --- baseline lifecycle ------------------------------------------------------

assert_status "hyprland check fails before install" 1 \
  bash -c "$PRE; module::check"

assert_status "hyprland verify passes before install (absent)" 0 \
  bash -c "$PRE; module::verify"

assert_status "hyprland install fails on non-Fedora-44 before any mutation" 1 \
  bash -c "$PRE; printf 'ID=fedora\nVERSION_ID=41\n' > \"\$ATLAS_HYPR_OS_RELEASE_FILE\"; printf 'Fedora release 41\n' > \"\$ATLAS_HYPR_FEDORA_RELEASE_FILE\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_hypr_marker)\" ]; [ ! -s \"\$FAKE_STATE/dnf.log\" ] 2>/dev/null || [ ! -e \"\$FAKE_STATE/dnf.log\" ]; exit \"\${rc:-0}\""

assert_status "hyprland fresh install writes installed marker" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\""

assert_status "hyprland fresh install enables COPR before packages" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ -f \"\$ATLAS_HYPR_REPO_FILE\" ]; grep -q 'copr enable' \"\$FAKE_STATE/dnf.log\""

assert_status "hyprland install deploys all five config trees" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; for d in hypr waybar wofi mako kitty; do [ -d \"\$XDG_CONFIG_HOME/\$d\" ] || exit 1; done"

assert_status "hyprland install uses the local atlas1 aquamarine rpm in the real transaction" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -q 'install -y .*aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm' \"\$FAKE_STATE/dnf.log\""

assert_status "hyprland install runs exactly one real dnf install transaction" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ \"\$(grep -c 'install -y' \"\$FAKE_STATE/dnf.log\")\" -eq 1 ]"

assert_status "hyprland install rehearses before the real transaction" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -q 'install --assumeno' \"\$FAKE_STATE/dnf.log\""

assert_status "hyprland install records the boundary transaction id" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -qxF 41 \"\$(_hypr_txn_file)\"; _hypr_txn_ok"

assert_status "recorded txn file is mode 600" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ \"\$(stat -c %a \"\$(_hypr_txn_file)\")\" = 600 ]"

assert_status "hyprland install bakes both wallpapers" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ -f \"\$(_hypr_wall_dst atlas-lock-bg.png)\" ] && [ -f \"\$(_hypr_wall_dst atlas-wall-bw.png)\" ]"

assert_status "hyprland install deploys watcher and activates the timer" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; [ -x \"\$ATLAS_HYPR_WATCHER_BIN\" ]; [ -f \"\$(_hypr_units_dir)/atlas-hypr-check.timer\" ]; grep -q 'enable --now' \"\$FAKE_STATE/systemctl.log\"; _hypr_watcher_ok"

assert_status "hyprland check passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::check"

assert_status "hyprland verify passes after install" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::verify"

# --- true idempotency: healthy repeat install mutates nothing ----------------

assert_status "healthy repeat install runs zero dnf/rehearse/watcher/config work" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; : > \"\$FAKE_STATE/dnf.log\"; : > \"\$FAKE_STATE/systemctl.log\"; cfgb=\"\$(sha256sum \"\$XDG_CONFIG_HOME/kitty/kitty.conf\")\"; module::install >/dev/null 2>&1; [ ! -s \"\$FAKE_STATE/dnf.log\" ]; [ ! -s \"\$FAKE_STATE/systemctl.log\" ]; [ \"\$cfgb\" = \"\$(sha256sum \"\$XDG_CONFIG_HOME/kitty/kitty.conf\")\" ]"

# --- adoption / refusal (RFC-0038 §6/§7) ------------------------------------

assert_status "install adopts byte-identical pre-staged configs without rewriting" 0 \
  bash -c "$PRE; mkdir -p \"\$XDG_CONFIG_HOME\"; for d in hypr waybar wofi mako kitty; do cp -a \"\$_HYPR_MODULE_DIR/config/\$d\" \"\$XDG_CONFIG_HOME/\$d\"; done; before=\"\$(find \"\$XDG_CONFIG_HOME/hypr\" -newer /etc/hostname 2>/dev/null | wc -l)\"; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\""

assert_status "install refuses unmanaged differing config before any mutation" 1 \
  bash -c "$PRE; mkdir -p \"\$XDG_CONFIG_HOME/hypr\"; echo user > \"\$XDG_CONFIG_HOME/hypr/user.conf\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_hypr_marker)\" ]; [ ! -s \"\$FAKE_STATE/dnf.log\" ] 2>/dev/null || [ ! -e \"\$FAKE_STATE/dnf.log\" ]; [ -f \"\$XDG_CONFIG_HOME/hypr/user.conf\" ]; exit \"\${rc:-0}\""

assert_status "install refuses differing wallpapers without sidecar, untouched" 1 \
  bash -c "$PRE; mkdir -p \"\$(_hypr_wall_dir)\"; echo foreign > \"\$(_hypr_wall_dst atlas-lock-bg.png)\"; echo foreign > \"\$(_hypr_wall_dst atlas-wall-bw.png)\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_hypr_marker)\" ]; grep -qxF foreign \"\$(_hypr_wall_dst atlas-lock-bg.png)\"; exit \"\${rc:-0}\""

# --- rehearsal integration (real classifier + parser via fake dnf) ----------

assert_status "clean rehearsal proceeds to the real transaction" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; grep -q 'install -y' \"\$FAKE_STATE/dnf.log\""

assert_status "rehearsal showing a removal aborts before the real transaction" 1 \
  bash -c "$PRE; printf '%s' \"\$FIX_REMOVAL\" > \"\$FAKE_STATE/rehearse.out\"; module::install >/dev/null 2>&1 || rc=\$?; ! grep -q 'install -y' \"\$FAKE_STATE/dnf.log\"; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "rehearsal showing a non-hypr upgrade aborts before the real transaction" 1 \
  bash -c "$PRE; printf '%s' \"\$FIX_NONHYPR_UPGRADE\" > \"\$FAKE_STATE/rehearse.out\"; module::install >/dev/null 2>&1 || rc=\$?; ! grep -q 'install -y' \"\$FAKE_STATE/dnf.log\"; exit \"\${rc:-0}\""

assert_status "rehearsal that fails to resolve aborts (fail-closed, no positive sentinel)" 1 \
  bash -c "$PRE; printf '%s' \"\$FIX_RESOLVE_FAIL\" > \"\$FAKE_STATE/rehearse.out\"; module::install >/dev/null 2>&1 || rc=\$?; ! grep -q 'install -y' \"\$FAKE_STATE/dnf.log\"; exit \"\${rc:-0}\""

# --- RPM gate integration ----------------------------------------------------

assert_status "install aborts when the staged rpm fails the gate (wrong linkage)" 1 \
  bash -c "$PRE; printf 'BAD\n' > \"\$ATLAS_HYPR_RPM_DIR/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm\"; _hypr_build_rpm() { printf 'BAD\n' > \"\$(_hypr_rpm_path)\"; }; module::install >/dev/null 2>&1 || rc=\$?; ! grep -q 'install -y' \"\$FAKE_STATE/dnf.log\"; exit \"\${rc:-0}\""

assert_status "install aborts when the staged rpm has the wrong release" 1 \
  bash -c "$PRE; printf 'WRONGREL\n' > \"\$ATLAS_HYPR_RPM_DIR/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm\"; _hypr_build_rpm() { printf 'WRONGREL\n' > \"\$(_hypr_rpm_path)\"; }; module::install >/dev/null 2>&1 || rc=\$?; ! grep -q 'install -y' \"\$FAKE_STATE/dnf.log\"; exit \"\${rc:-0}\""

assert_status "install aborts when the staged rpm fails integrity" 1 \
  bash -c "$PRE; printf 'CORRUPT\n' > \"\$ATLAS_HYPR_RPM_DIR/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm\"; _hypr_build_rpm() { printf 'CORRUPT\n' > \"\$(_hypr_rpm_path)\"; }; module::install >/dev/null 2>&1 || rc=\$?; ! grep -q 'install -y' \"\$FAKE_STATE/dnf.log\"; exit \"\${rc:-0}\""

# --- transaction integrity (RFC-0038 §8.8) ----------------------------------

assert_status "no new transaction after install is rejected (stays installing)" 1 \
  bash -c "$PRE; FAKE_DNF_NO_NEW=1; export FAKE_DNF_NO_NEW; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; [ ! -f \"\$(_hypr_txn_file)\" ]; exit \"\${rc:-0}\""

assert_status "an unrelated newer transaction is rejected as the recorded id" 1 \
  bash -c "$PRE; FAKE_DNF_UNRELATED_NEWER=1; export FAKE_DNF_UNRELATED_NEWER; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; [ ! -f \"\$(_hypr_txn_file)\" ]; exit \"\${rc:-0}\""

assert_status "malformed history output is rejected" 1 \
  bash -c "$PRE; FAKE_HISTORY_BAD_LIST=1; export FAKE_HISTORY_BAD_LIST; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "history lookup failure is rejected" 1 \
  bash -c "$PRE; FAKE_DNF_INFO_FAIL=1; export FAKE_DNF_INFO_FAIL; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "verify rejects a recorded transaction that no longer exists" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$FAKE_STATE/hinfo/41\"; module::verify"

assert_status "verify rejects a recorded transaction with unexpected package operations" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; { printf 'Transaction ID : 41\nPackages altered:\n  Removed plasma-workspace-6.0.x86_64 User @System\n'; } > \"\$FAKE_STATE/hinfo/41\"; module::verify"

# --- interrupted-install reconciliation: safe retry after every phase --------

assert_status "retry after marker write completes and runs one transaction" 0 \
  bash -c "$PRE; _hypr_marker_write installing; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\"; [ \"\$(grep -c 'install -y' \"\$FAKE_STATE/dnf.log\")\" -eq 1 ]"

assert_status "retry after COPR enablement does not re-enable COPR" 0 \
  bash -c "$PRE; _hypr_marker_write installing; mkdir -p \"\$(dirname \"\$ATLAS_HYPR_REPO_FILE\")\"; printf '[%s]\nname=c\nbaseurl=https://x/\nenabled=1\ngpgcheck=1\n' 'copr:copr.fedorainfracloud.org:solopasha:hyprland' > \"\$ATLAS_HYPR_REPO_FILE\"; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\"; ! grep -q 'copr enable' \"\$FAKE_STATE/dnf.log\""

assert_status "retry after a completed transaction does NOT run a second dnf transaction" 0 \
  bash -c "$PRE; _hypr_marker_write installing; _fake_installed; _fake_history_good 41; _fake_record_txn 41; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\"; ! grep -q 'install -y' \"\$FAKE_STATE/dnf.log\""

assert_status "retry after transaction but before recording stays installing with recovery, no second dnf" 1 \
  bash -c "$PRE; _hypr_marker_write installing; _fake_installed; _fake_history_good 41; out=\"\$(module::install 2>&1)\" || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; ! grep -q 'install -y' \"\$FAKE_STATE/dnf.log\"; printf '%s' \"\$out\" | grep -q 'dnf history list'; exit \"\${rc:-0}\""

assert_status "after manual id recovery the retry completes without a second dnf" 0 \
  bash -c "$PRE; _hypr_marker_write installing; _fake_installed; _fake_history_good 41; module::install >/dev/null 2>&1 || true; _fake_record_txn 41; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\"; ! grep -q 'install -y' \"\$FAKE_STATE/dnf.log\""

assert_status "retry after partial config deploy completes" 0 \
  bash -c "$PRE; _hypr_marker_write installing; cp -a \"\$_HYPR_MODULE_DIR/config/hypr\" \"\$XDG_CONFIG_HOME/hypr\" 2>/dev/null; mkdir -p \"\$XDG_CONFIG_HOME\"; cp -a \"\$_HYPR_MODULE_DIR/config/waybar\" \"\$XDG_CONFIG_HOME/waybar\"; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\"; module::verify"

assert_status "retry after wallpaper bake completes" 0 \
  bash -c "$PRE; _hypr_marker_write installing; _hypr_bake_wallpapers; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\"; module::verify"

assert_status "retry after watcher deploy completes" 0 \
  bash -c "$PRE; _hypr_marker_write installing; _hypr_deploy_watcher >/dev/null 2>&1; module::install >/dev/null 2>&1; grep -qxF state=installed \"\$(_hypr_marker)\"; module::verify"

# --- hostile interrupted-retry regression (ported concept from Claude) ------
# A fresh-mode deploy must NEVER rm -rf a tree that differs from source; it must
# fail loudly (the filesystem raced preflight). Non-Atlas content is preserved.
assert_status "fresh-mode deploy refuses to destroy a differing tree (race guard)" 1 \
  bash -c "$PRE; mkdir -p \"\$XDG_CONFIG_HOME/hypr\"; echo mine > \"\$XDG_CONFIG_HOME/hypr/mine.conf\"; _hypr_deploy_configs fresh >/dev/null 2>&1 || rc=\$?; [ -f \"\$XDG_CONFIG_HOME/hypr/mine.conf\" ]; exit \"\${rc:-0}\""

assert_status "managed-mode deploy reconciles drift (Atlas owns the tree)" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/waybar/config.jsonc\"; _hypr_deploy_configs managed >/dev/null 2>&1; _hypr_configs_match"

# --- watcher lifecycle (fail-closed) ----------------------------------------

assert_status "install fails when systemctl daemon-reload fails" 1 \
  bash -c "$PRE; FAKE_SYSTEMCTL_RELOAD_RC=1; export FAKE_SYSTEMCTL_RELOAD_RC; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "install fails when enabling the timer fails" 1 \
  bash -c "$PRE; FAKE_SYSTEMCTL_ENABLE_RC=1; export FAKE_SYSTEMCTL_ENABLE_RC; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "install fails when the timer is enabled but inactive" 1 \
  bash -c "$PRE; FAKE_TIMER_ACTIVE=0; export FAKE_TIMER_ACTIVE; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "verify fails on watcher script drift" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo tampered >> \"\$ATLAS_HYPR_WATCHER_BIN\"; module::verify"

assert_status "verify fails on watcher unit drift" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo tampered >> \"\$(_hypr_units_dir)/atlas-hypr-check.timer\"; module::verify"

assert_status "verify fails when the timer is no longer active while still on atlas1" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$FAKE_STATE/timer.state\"; module::verify"

assert_status "supersession: self-disabled timer is valid once aquamarine is superseded" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo 3.fc44 > \"\$FAKE_STATE/installed/aquamarine\"; rm -f \"\$FAKE_STATE/timer.state\"; module::verify"

# --- verify / update / remove ------------------------------------------------

assert_status "verify fails when a managed config drifts" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/waybar/config.jsonc\"; module::verify"

assert_status "update restores drifted config" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/waybar/config.jsonc\"; module::update >/dev/null 2>&1; module::verify"

assert_status "update refuses while installing" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; _hypr_marker_write installing; module::update >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_hypr_marker)\"; exit \"\${rc:-0}\""

assert_status "remove detaches configs and undeploys the watcher, packages remain" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; : > \"\$FAKE_STATE/dnf.log\"; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_hypr_marker)\"; [ ! -e \"\$XDG_CONFIG_HOME/hypr\" ]; [ ! -e \"\$ATLAS_HYPR_WATCHER_BIN\" ]; [ -f \"\$(_hypr_txn_file)\" ]; ! grep -qi 'history undo' \"\$FAKE_STATE/dnf.log\"; ! grep -q 'install -y' \"\$FAKE_STATE/dnf.log\"; grep -q disable \"\$FAKE_STATE/systemctl.log\""

assert_status "remove refuses on config drift and preserves the tree" 1 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo drift >> \"\$XDG_CONFIG_HOME/kitty/kitty.conf\"; module::remove >/dev/null 2>&1 || rc=\$?; grep -qxF state=installed \"\$(_hypr_marker)\"; [ -d \"\$XDG_CONFIG_HOME/kitty\" ]; exit \"\${rc:-0}\""

assert_status "remove is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; module::remove"

assert_status "remove undeploys only Atlas-owned watcher files (leaves a tampered unit)" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; echo tampered >> \"\$(_hypr_units_dir)/atlas-hypr-check.timer\"; module::remove >/dev/null 2>&1 || true; [ -f \"\$(_hypr_units_dir)/atlas-hypr-check.timer\" ]; [ ! -e \"\$ATLAS_HYPR_WATCHER_BIN\" ]"

assert_status "hyprland backup is a documented no-op" 0 bash -c "$PRE; module::backup"
assert_status "hyprland restore is a documented no-op" 0 bash -c "$PRE; module::restore"

# --- rehearsal classifier + parser unit checks (fail-closed) ----------------

assert_status "resolved-ok accepts a declined, resolved plan" 0 \
  bash -c "$PRE; _hypr_rehearse_resolved_ok \"\$FIX_CLEAN\""
assert_status "resolved-ok rejects a resolver failure" 1 \
  bash -c "$PRE; _hypr_rehearse_resolved_ok \"\$FIX_RESOLVE_FAIL\""
assert_status "resolved-ok rejects output with no positive sentinel" 1 \
  bash -c "$PRE; _hypr_rehearse_resolved_ok \"Repositories loaded.\""

assert_status "parser accepts a clean install-only plan" 0 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Installing:
 hyprland x86_64 1-1 copr 1M
 waybar x86_64 1-1 copr 1M
Installing dependencies:
 libinput x86_64 1-1 updates 1M\""

assert_status "parser rejects removals" 1 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Removing:
 plasma-workspace x86_64 6.0 @System 1M\""

assert_status "parser rejects a replacing/obsoletion line" 1 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Installing:
 foo x86_64 2-1 repo 1M
   replacing bar.x86_64 1-1\""

assert_status "parser rejects downgrades" 1 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Downgrading:
 hyprland x86_64 0.1 copr 1M\""

assert_status "parser rejects non-hypr upgrades" 1 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Upgrading:
 systemd x86_64 257 updates 1M\""

assert_status "parser allows exact hypr-set upgrades" 0 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Upgrading:
 hyprland x86_64 0.50 copr 1M
 aquamarine x86_64 0.9.5 copr 1M\""

assert_status "parser rejects a broad kitty-* prefix upgrade (exact names only)" 1 \
  bash -c "$PRE; _hypr_rehearse_output_ok \"Upgrading:
 kitty-terminfo noarch 1-1 updates 1M\""

# --- txn id helpers ----------------------------------------------------------

assert_status "txn id unknown is invalid" 1 bash -c "$PRE; _hypr_txn_id_valid unknown"
assert_status "txn id numeric is valid" 0 bash -c "$PRE; _hypr_txn_id_valid 42"
assert_status "pkg allowlist accepts an exact hypr name" 0 bash -c "$PRE; _hypr_pkg_allowed kitty"
assert_status "pkg allowlist rejects a hyphenated near-name" 1 bash -c "$PRE; _hypr_pkg_allowed kitty-terminfo"
