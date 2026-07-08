#!/usr/bin/env bash
# Atlas bootstrap — the only thing you run on a truly fresh machine.
# Ensures Git, fetches Atlas, and hands off to `atlas install`.
set -uo pipefail

ATLAS_REPO="${ATLAS_REPO:-https://github.com/thiva2k/atlas.git}"
ATLAS_HOME="${ATLAS_HOME:-$HOME/atlas}"

usage() {
  cat <<EOF
Atlas bootstrap

Prepares a fresh machine, then hands off to Atlas:
  1. ensure Git is installed
  2. clone Atlas into $ATLAS_HOME (if not already there)
  3. run:  cd $ATLAS_HOME && ./atlas install

Usage: bootstrap.sh [--help]
EOF
}

main() {
  case "${1:-}" in -h|--help) usage; return 0 ;; esac

  if ! command -v git >/dev/null 2>&1; then
    echo "git not found — installing (requires sudo)…"
    if command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y git
    else
      echo "no dnf available; install git manually and re-run" >&2
      return 1
    fi
  fi

  if [ ! -d "$ATLAS_HOME/.git" ]; then
    echo "cloning Atlas into $ATLAS_HOME…"
    git clone "$ATLAS_REPO" "$ATLAS_HOME"
  else
    echo "Atlas already present at $ATLAS_HOME — leaving it as is."
  fi

  echo
  echo "Bootstrap complete. Next:"
  echo "  cd $ATLAS_HOME && ./atlas install"
}

main "$@"
