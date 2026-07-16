#!/usr/bin/env bash
# Atlas — Hyprland availability watcher.
# Checks whether the solopasha COPR's `aquamarine` has been rebuilt against
# Fedora 44's libdisplay-info 0.3 (the one thing blocking the Hyprland install).
# Notifies once it's installable, then disables itself. No sudo; the query is
# read-only against the COPR results dir. Driven by a daily user systemd timer.
set -uo pipefail

COPR="https://download.copr.fedorainfracloud.org/results/solopasha/hyprland/fedora-44-x86_64/"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/atlas"
mkdir -p "$STATE" 2>/dev/null || true
LOG="$STATE/hypr-watch.log"
stamp() { date '+%Y-%m-%dT%H:%M:%S'; }

# Already installed? Nothing to watch — stand down.
if rpm -q hyprland >/dev/null 2>&1 || command -v Hyprland >/dev/null 2>&1; then
    echo "$(stamp) hyprland already installed; disabling watcher" >>"$LOG"
    systemctl --user disable --now atlas-hypr-check.timer >/dev/null 2>&1 || true
    exit 0
fi

req="$(dnf repoquery --repofrompath "atlaswatch,$COPR" \
        --setopt=atlaswatch.gpgcheck=0 --repoid=atlaswatch --refresh \
        --requires aquamarine 2>/dev/null)"

if [ -z "$req" ]; then
    echo "$(stamp) could not query COPR (offline?); will retry" >>"$LOG"
    exit 0
fi

if printf '%s\n' "$req" | grep -q 'libdisplay-info.so.2'; then
    echo "$(stamp) still blocked: aquamarine needs libdisplay-info.so.2" >>"$LOG"
    exit 0
fi

# aquamarine no longer requires the old soname -> it's been rebuilt.
echo "$(stamp) READY: aquamarine rebuilt; Hyprland is installable" >>"$LOG"
notify-send -u critical -a "Atlas" "Atlas · Hyprland is ready to install" \
    "The aquamarine rebuild has landed. Run the Atlas Hyprland install to go live — then pick Hyprland at the login screen." 2>/dev/null || true
touch "$STATE/hypr-ready" 2>/dev/null || true
# Stop checking now that it's ready.
systemctl --user disable --now atlas-hypr-check.timer >/dev/null 2>&1 || true
