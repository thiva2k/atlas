#!/usr/bin/env bash
[ -n "${ATLAS_ERROR_SH:-}" ] && return 0; ATLAS_ERROR_SH=1

readonly ATLAS_EXIT_OK=0
readonly ATLAS_EXIT_GENERAL=1
readonly ATLAS_EXIT_USAGE=2
readonly ATLAS_EXIT_DEPENDENCY=3
readonly ATLAS_EXIT_MODULE=4
readonly ATLAS_EXIT_UNSUPPORTED=5

# die <code> <what> [why] [how] — every fatal error answers what/why/how.
die() {
  local code="$1" what="$2" why="${3:-}" how="${4:-}"
  log::error "$what"
  [ -n "$why" ] && log::error "  why: $why"
  [ -n "$how" ] && log::error "  fix: $how"
  exit "$code"
}
