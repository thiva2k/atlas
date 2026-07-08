#!/usr/bin/env bash
# Tiny pure-Bash assertion library. No external framework.
# Each test file increments ATLAS_TESTS_PASS / ATLAS_TESTS_FAIL via these.

_t_ok()   { ATLAS_TESTS_PASS=$((ATLAS_TESTS_PASS + 1)); printf '  ok   %s\n' "$1"; }
_t_fail() { ATLAS_TESTS_FAIL=$((ATLAS_TESTS_FAIL + 1)); printf '  FAIL %s\n' "$1"; }

assert_eq() { # <name> <actual> <expected>
  if [ "$2" = "$3" ]; then _t_ok "$1"
  else _t_fail "$1"; printf '       expected [%s] got [%s]\n' "$3" "$2"; fi
}

assert_contains() { # <name> <haystack> <needle>
  case "$2" in
    *"$3"*) _t_ok "$1" ;;
    *) _t_fail "$1"; printf '       [%s] does not contain [%s]\n' "$2" "$3" ;;
  esac
}

assert_status() { # <name> <expected_code> <cmd...>
  local name="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then _t_ok "$name"
  else _t_fail "$name"; printf '       exit %s, wanted %s\n' "$got" "$want"; fi
}
