#!/usr/bin/env bash
# Atlas bootstrap — the only thing you run on a truly fresh machine.
# Ensures Git, fetches Atlas, and hands off to `atlasctl install`.
set -uo pipefail

ATLAS_REPO="${ATLAS_REPO:-https://github.com/thiva2k/atlas.git}"
ATLAS_HOME="${ATLAS_HOME:-$HOME/atlas}"
ATLAS_REMOTE_IDENTITY="github.com/thiva2k/atlas"

usage() {
  cat <<EOF
Atlas bootstrap

Prepares a fresh machine, then hands off to Atlas:
  1. ensure Git is installed
  2. clone Atlas into $ATLAS_HOME (if not already there)
  3. run:  cd $ATLAS_HOME && ./atlas install
     or:   atlasctl install

Usage: bootstrap.sh [--help]
EOF
}

remote_identity_from_url() {
  local url="$1" rest host path
  url="${url%.git}"
  case "$url" in
    git@*:*)
      host="${url#git@}"
      host="${host%%:*}"
      path="${url#*:}"
      printf '%s/%s\n' "$host" "$path"
      ;;
    ssh://*|https://*|http://*)
      rest="${url#*://}"
      rest="${rest#*@}"
      host="${rest%%/*}"
      path="${rest#*/}"
      printf '%s/%s\n' "$host" "$path"
      ;;
    *)
      printf '%s\n' "$url"
      ;;
  esac
}

canonical_path() {
  local p="$1" dir base resolved
  if [ -d "$p" ]; then
    ( cd -P "$p" >/dev/null 2>&1 && pwd ) || return 1
    return 0
  fi
  dir="$(dirname "$p")"
  base="$(basename "$p")"
  dir="$(cd -P "$dir" >/dev/null 2>&1 && pwd)" || return 1
  if command -v readlink >/dev/null 2>&1; then
    resolved="$(readlink -f "$dir/$base" 2>/dev/null)" && [ -n "$resolved" ] && {
      printf '%s\n' "$resolved"
      return 0
    }
  fi
  [ -e "$dir/$base" ] || return 1
  printf '%s/%s\n' "$dir" "$base"
}

install_self_launcher() {
  local target launcher_dir launcher target_c launcher_c
  target="$ATLAS_HOME/atlasctl"
  launcher_dir="$HOME/.local/bin"
  launcher="$launcher_dir/atlasctl"

  [ -x "$target" ] || {
    echo "Atlas executable is not runnable at $target — not recording self-management marker." >&2
    return 1
  }

  mkdir -p "$launcher_dir" || {
    echo "cannot create Atlas launcher directory: $launcher_dir" >&2
    return 1
  }

  if [ -e "$launcher" ] || [ -L "$launcher" ]; then
    target_c="$(canonical_path "$target")" || return 1
    launcher_c="$(canonical_path "$launcher")" || {
      echo "atlasctl launcher already exists at $launcher — not recording self-management marker." >&2
      return 1
    }
    [ "$launcher_c" = "$target_c" ] || {
      echo "atlasctl launcher already exists at $launcher — not recording self-management marker." >&2
      return 1
    }
    printf '%s\n' "$launcher"
    return 0
  fi

  ln -s "$target" "$launcher" || {
    echo "cannot create Atlas launcher at $launcher" >&2
    return 1
  }
  printf '%s\n' "$launcher"
}

record_self_management_marker() {
  local identity state_dir marker dir tmp branch launcher
  identity="$(remote_identity_from_url "$ATLAS_REPO")"
  [ "$identity" = "$ATLAS_REMOTE_IDENTITY" ] || {
    echo "custom Atlas repository detected — not recording self-management marker."
    return 0
  }
  branch="$(git -C "$ATLAS_HOME" symbolic-ref --short HEAD 2>/dev/null)" || {
    echo "cannot determine Atlas branch — not recording self-management marker." >&2
    return 0
  }
  [ "$branch" = "main" ] || {
    echo "Atlas branch is not main — not recording self-management marker."
    return 0
  }
  launcher="$(install_self_launcher)" || return 0
  state_dir="${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}"
  marker="$state_dir/installed/atlas-self"
  dir="$(dirname "$marker")"
  mkdir -p "$dir" || {
    echo "cannot create Atlas self-management marker directory: $dir" >&2
    return 0
  }
  chmod 700 "$dir" || {
    echo "cannot secure Atlas self-management marker directory: $dir" >&2
    return 0
  }
  tmp="$(mktemp "$dir/.atlas-self.XXXXXX")" || {
    echo "cannot create Atlas self-management marker temp file" >&2
    return 0
  }
  {
    printf 'schema=1\n'
    printf 'state=installed\n'
    printf 'source=git\n'
    printf 'path=%s\n' "$ATLAS_HOME"
    printf 'remote=origin\n'
    printf 'remote_identity=%s\n' "$ATLAS_REMOTE_IDENTITY"
    printf 'branch=main\n'
    printf 'ref=refs/heads/main\n'
    printf 'launcher=%s\n' "$launcher"
    printf 'executable=%s/atlasctl\n' "$ATLAS_HOME"
  } > "$tmp" || {
    rm -f "$tmp"
    echo "cannot write Atlas self-management marker" >&2
    return 0
  }
  chmod 600 "$tmp" || {
    rm -f "$tmp"
    echo "cannot secure Atlas self-management marker" >&2
    return 0
  }
  mv -f "$tmp" "$marker" || {
    rm -f "$tmp"
    echo "cannot record Atlas self-management marker" >&2
    return 0
  }
}

main() {
  case "${1:-}" in -h|--help) usage; return 0 ;; esac

  if ! command -v git >/dev/null 2>&1; then
    echo "git not found — installing (requires sudo)…"
    if command -v dnf >/dev/null 2>&1; then
      if ! sudo dnf install -y git; then
        echo "failed to install git via dnf; install it manually and re-run" >&2
        return 1
      fi
    else
      echo "no dnf available; install git manually and re-run" >&2
      return 1
    fi
  fi

  if [ ! -d "$ATLAS_HOME/.git" ]; then
    echo "cloning Atlas into $ATLAS_HOME…"
    if ! git clone "$ATLAS_REPO" "$ATLAS_HOME"; then
      echo "failed to clone Atlas from $ATLAS_REPO into $ATLAS_HOME" >&2
      return 1
    fi
    record_self_management_marker
  else
    echo "Atlas already present at $ATLAS_HOME — leaving it as is."
  fi

  echo
  echo "Bootstrap complete. Next:"
  echo "  cd $ATLAS_HOME && ./atlas install"
  echo
  echo "If $HOME/.local/bin is on PATH, you can also run:"
  echo "  atlasctl install"
}

main "$@"
