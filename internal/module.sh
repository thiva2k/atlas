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

# --- dependency resolution -------------------------------------------------

# Print a module's declared dependencies (one per line), read in isolation.
module::deps_of() {
  local id="$1" p; p="$(module::path "$id")"
  [ -r "$p" ] || return 0
  ( set +u
    MODULE_DEPENDS=()
    # shellcheck source=/dev/null
    source "$p"
    local d
    for d in "${MODULE_DEPENDS[@]}"; do
      [ -n "$d" ] && printf '%s\n' "$d"
    done )
}

# Print ids + transitive deps in dependency-first order. Cycle => exit 3.
module::resolve_order() {
  local -a input=("$@")
  local -A _state=()          # unset | temp | done
  local -a _order=()

  _module_visit() {
    local id="$1" d
    if [ ! -r "$(module::path "$id")" ]; then
      die "$ATLAS_EXIT_DEPENDENCY" \
        "unknown module: $id" \
        "a requested module or a declared dependency does not exist" \
        "check the id (category/name) and any MODULE_DEPENDS entries"
    fi
    case "${_state[$id]:-}" in
      done) return 0 ;;
      temp) die "$ATLAS_EXIT_DEPENDENCY" \
              "dependency cycle detected at '$id'" \
              "two or more modules depend on each other in a loop" \
              "break the loop by editing a module's MODULE_DEPENDS" ;;
    esac
    _state[$id]=temp
    while IFS= read -r d; do
      [ -n "$d" ] && _module_visit "$d"
    done < <(module::deps_of "$id")
    _state[$id]=done
    _order+=("$id")
  }

  local id
  for id in "${input[@]}"; do _module_visit "$id"; done
  printf '%s\n' "${_order[@]}"
}
