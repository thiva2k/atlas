#!/usr/bin/env bash
# Atlas — Hyprland renderer supersession watcher.
# The Atlas Hyprland desktop is installed from a locally-rebuilt aquamarine
# (0.9.5-2.fc44.atlas1, linked against libdisplay-info.so.3). When the COPR ships
# an official rebuild, `dnf upgrade` replaces it and the `.atlas1` release
# disappears — that is the "all clear, superseded" signal. No sudo; read-only
# rpm query. Driven by a daily user systemd timer; self-disables once superseded
# or if aquamarine is not installed.
set -uo pipefail

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/atlas"
mkdir -p "$STATE" 2>/dev/null || true
LOG="$STATE/hypr-watch.log"
stamp() { date '+%Y-%m-%dT%H:%M:%S'; }

# Not installed yet (or removed) -> nothing to watch; stand down.
if ! rpm -q aquamarine >/dev/null 2>&1; then
    echo "$(stamp) aquamarine not installed; nothing to watch" >>"$LOG"
    systemctl --user disable --now atlas-hypr-check.timer >/dev/null 2>&1 || true
    exit 0
fi

installed_rel="$(rpm -q --qf '%{RELEASE}' aquamarine 2>/dev/null)"
case "$installed_rel" in
  *.atlas1)
    # still on our local rebuild; keep watching
    echo "$(stamp) still on the Atlas local rebuild ($installed_rel)" >>"$LOG"
    ;;
  *)
    # release no longer carries our marker -> the official rebuild landed
    echo "$(stamp) SUPERSEDED: official aquamarine ($installed_rel) is in place" >>"$LOG"
    notify-send -a "Atlas" "Atlas · Hyprland renderer superseded" \
      "The official aquamarine rebuild ($installed_rel) has replaced the Atlas local build. No action needed." 2>/dev/null || true
    systemctl --user disable --now atlas-hypr-check.timer >/dev/null 2>&1 || true
    ;;
esac
