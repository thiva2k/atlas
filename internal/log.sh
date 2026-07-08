#!/usr/bin/env bash
[ -n "${ATLAS_LOG_SH:-}" ] && return 0; ATLAS_LOG_SH=1

: "${ATLAS_LOG_LEVEL:=info}"
: "${ATLAS_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/atlas}"

_log_level_num() {
  case "$1" in
    debug) echo 0 ;; info) echo 1 ;; warn) echo 2 ;; error) echo 3 ;; *) echo 1 ;;
  esac
}

_log_file() {
  local dir="$ATLAS_STATE_DIR/logs"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s/atlas-%s.log' "$dir" "$(date +%Y%m%d)"
}

_log_emit() { # <level> <color> <msg>
  local level="$1" color="$2" msg="$3"
  local ts scope line
  ts="$(date +%Y-%m-%dT%H:%M:%S)"
  scope="${ATLAS_LOG_SCOPE:-atlas}"
  line="$ts  $(printf '%s' "$level" | tr '[:lower:]' '[:upper:]')  [$scope]  $msg"
  printf '%s\n' "$line" >> "$(_log_file)" 2>/dev/null || true
  if [ "$(_log_level_num "$level")" -ge "$(_log_level_num "$ATLAS_LOG_LEVEL")" ]; then
    if [ -t 2 ] && [ -n "$color" ]; then
      printf '%b%s%b\n' "$color" "$line" '\033[0m' >&2
    else
      printf '%s\n' "$line" >&2
    fi
  fi
}

log::debug() { _log_emit debug '\033[2m'    "$*"; }
log::info()  { _log_emit info  ''           "$*"; }
log::warn()  { _log_emit warn  '\033[33m'   "$*"; }
log::error() { _log_emit error '\033[31m'   "$*"; }
log::step()  { _log_emit info  '\033[1;36m' "== $* =="; }
