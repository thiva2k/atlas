#!/usr/bin/env bash
[ -n "${ATLAS_MODULE_SH:-}" ] && return 0; ATLAS_MODULE_SH=1

: "${ATLAS_MODULES_DIR:=${ATLAS_ROOT:-.}/modules}"

# Placeholder-hook helper, available to modules once this file is sourced.
not_implemented() { log::warn "not yet implemented: $*"; return 0; }

# Print every module id ("category/name"), one per line, sorted.
module::discover() {
  local f id
  for f in "$ATLAS_MODULES_DIR"/*/*/module.sh; do
    [ -e "$f" ] || continue
    id="${f#"$ATLAS_MODULES_DIR"/}"
    id="${id%/module.sh}"
    printf '%s\n' "$id"
  done | sort
}

module::path() { printf '%s\n' "$ATLAS_MODULES_DIR/$1/module.sh"; }

module::has_hook() { declare -F "module::$1" >/dev/null 2>&1; }

# Dependency ordering (module::deps_of, module::resolve_order) is added in Task 6.
