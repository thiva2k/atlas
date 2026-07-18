#!/usr/bin/env bash
# Atlas — Hyprland aquamarine supersession watcher (RFC-0038 §9).
#
# After desktop/hyprland installs the local aquamarine-*.atlas1 rebuild, this
# watcher no longer polls COPR availability. It watches the *installed*
# aquamarine RPM %{RELEASE}:
#   - ends with .atlas1 → still on Atlas local build; stay quiet
#   - aquamarine absent → nothing to watch; disable timer
#   - anything else → official rebuild superseded us; notify once and disable
#
# No sudo. Driven by atlas-hypr-check.timer (user systemd).
set -uo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/atlas"
mkdir -p "$STATE" 2>/dev/null || true
LOG="$STATE/hypr-watch.log"
stamp() { date '+%Y-%m-%dT%H:%M:%S'; }

_disable() {
  systemctl --user disable --now atlas-hypr-check.timer >/dev/null 2>&1 || true
}

release="$(rpm -q --qf '%{RELEASE}' aquamarine 2>/dev/null || true)"

if [ -z "$release" ] || [ "$release" = "(none)" ]; then
  # Not installed, or query failed with empty — stand down.
  # Before module install, hyprland may also be absent; keep the pre-install
  # COPR availability path only when hyprland is not present either.
  if ! rpm -q hyprland >/dev/null 2>&1 && ! command -v Hyprland >/dev/null 2>&1; then
    COPR="https://download.copr.fedorainfracloud.org/results/solopasha/hyprland/fedora-44-x86_64/"
    req="$(dnf repoquery --repofrompath "atlaswatch,$COPR" \
            --setopt=atlaswatch.gpgcheck=0 --repoid=atlaswatch --refresh \
            --requires aquamarine 2>/dev/null || true)"
    if [ -z "$req" ]; then
      echo "$(stamp) could not query COPR (offline?); will retry" >>"$LOG"
      exit 0
    fi
    if printf '%s\n' "$req" | grep -q 'libdisplay-info.so.2'; then
      echo "$(stamp) still blocked: aquamarine needs libdisplay-info.so.2" >>"$LOG"
      exit 0
    fi
    echo "$(stamp) READY: aquamarine rebuilt upstream; Hyprland is installable" >>"$LOG"
    notify-send -u critical -a "Atlas" "Atlas · Hyprland is ready to install" \
      "The aquamarine rebuild has landed. Run atlasctl install desktop/hyprland — then pick Hyprland at the login screen." 2>/dev/null || true
    touch "$STATE/hypr-ready" 2>/dev/null || true
    _disable
    exit 0
  fi
  echo "$(stamp) aquamarine not installed; nothing to watch — disabling" >>"$LOG"
  _disable
  exit 0
fi

case "$release" in
  *.atlas1|*.atlas1.*)
    echo "$(stamp) still on local aquamarine release=$release (atlas1)" >>"$LOG"
    exit 0
    ;;
esac

# Official (or other) release replaced our .atlas1 build.
echo "$(stamp) SUPERSEDED: aquamarine release=$release (no longer .atlas1)" >>"$LOG"
notify-send -u normal -a "Atlas" "Atlas · aquamarine local rebuild superseded" \
  "Official aquamarine ($release) replaced the Atlas .atlas1 build. Local rebuild ownership can stand down." 2>/dev/null || true
touch "$STATE/hypr-superseded" 2>/dev/null || true
_disable
exit 0
