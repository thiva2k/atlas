#!/usr/bin/env bash
# Atlas — Hyprland aquamarine supersession watcher (RFC-0038 §9).
#
# This watcher only runs after desktop/hyprland has installed the local
# aquamarine-*.atlas1 rebuild. Its single job is to notice when an official
# COPR rebuild supersedes that local build (via a routine `dnf upgrade`) so
# Atlas can stop asserting ownership of a package it no longer built. It does
# NOT poll COPR availability — that pre-install question is already answered
# once this module has run.
#
# It keys off the *installed* aquamarine RPM %{RELEASE}:
#   - ends with .atlas1 → still on the Atlas local build; stay quiet.
#   - aquamarine absent → nothing to watch; disable the timer.
#   - anything else     → an official rebuild superseded us; notify once and
#                         disable the timer. This is an all-clear, not an error.
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
  echo "$(stamp) aquamarine not installed; nothing to watch — disabling" >>"$LOG"
  _disable
  exit 0
fi

case "$release" in
  *.atlas*)
    echo "$(stamp) still on local aquamarine release=$release (atlas*)" >>"$LOG"
    exit 0
    ;;
esac

# Official (or other) release replaced our .atlas* build.
echo "$(stamp) SUPERSEDED: aquamarine release=$release (no longer .atlas*)" >>"$LOG"
notify-send -u normal -a "Atlas" "Atlas · aquamarine local rebuild superseded" \
  "Official aquamarine ($release) replaced the Atlas .atlas* build. Local rebuild ownership can stand down." 2>/dev/null || true
touch "$STATE/hypr-superseded" 2>/dev/null || true
_disable
exit 0
