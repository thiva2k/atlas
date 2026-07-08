#!/usr/bin/env bash
[ -n "${ATLAS_RUNNER_SH:-}" ] && return 0; ATLAS_RUNNER_SH=1

# Ordered hook sequence for a verb (empty + return 1 => unknown verb).
_runner_hooks_for_verb() {
  case "$1" in
    install) echo "check install verify" ;;
    update)  echo "update"  ;;
    verify)  echo "verify"  ;;
    backup)  echo "backup"  ;;
    restore) echo "restore" ;;
    status)  echo "check"   ;;
    doctor)  echo "verify"  ;;
    *) return 1 ;;
  esac
}

# Run one module's part of a verb in an isolated subshell.
# stdout carries a control token (__SKIP__) only; logs go to stderr.
# Returns 0 on success/skip, non-zero on hook failure.
_runner_run_module() {
  local verb="$1" id="$2" hooks
  hooks="$(_runner_hooks_for_verb "$verb")" || return "$ATLAS_EXIT_USAGE"
  (
    set -euo pipefail
    ATLAS_LOG_SCOPE="$id"
    # shellcheck source=/dev/null
    source "$(module::path "$id")"
    local hook
    for hook in $hooks; do
      if [ "$verb" = "install" ] && [ "$hook" = "check" ]; then
        if module::has_hook check && module::check; then
          log::info "already satisfied — skipping"
          printf '__SKIP__'
          exit 0
        fi
        continue
      fi
      module::has_hook "$hook" || { log::debug "no $hook hook"; continue; }
      if ! "module::$hook"; then
        log::error "$hook failed"
        exit 1
      fi
    done
  )
}

# runner::run <verb> [id...]
runner::run() {
  local verb="${1:-}"; shift || true
  _runner_hooks_for_verb "$verb" >/dev/null 2>&1 || \
    die "$ATLAS_EXIT_USAGE" "unknown command: $verb" "" "run 'atlas --help'"

  local -a ids
  if [ "$#" -gt 0 ]; then ids=("$@"); else mapfile -t ids < <(module::discover); fi
  if [ "${#ids[@]}" -eq 0 ]; then log::warn "no modules found"; return 0; fi
  mapfile -t ids < <(module::resolve_order "${ids[@]}")

  log::step "atlas $verb (${#ids[@]} modules)"
  local id out rc ok=0 skip=0 fail=0
  for id in "${ids[@]}"; do
    out="$(_runner_run_module "$verb" "$id")"; rc=$?
    if [ "$rc" -ne 0 ]; then
      fail=$((fail + 1)); log::error "[$id] failed"
    elif [ "$out" = "__SKIP__" ]; then
      skip=$((skip + 1))
    else
      ok=$((ok + 1))
    fi
  done
  log::step "done: $ok ok, $skip skipped, $fail failed"
  [ "$fail" -eq 0 ] || return "$ATLAS_EXIT_MODULE"
  return 0
}
