#!/usr/bin/env bash
# os::dnf_install is tested by shadowing `dnf` and `sudo` with shell FUNCTIONS
# (functions take precedence over PATH, so no real package manager is touched —
# safe on Fedora and non-Fedora alike). Each case runs in a child bash so the
# stubs never leak into the suite shell.

# success: dnf install is invoked with the packages, returns 0
out="$(bash -c '
  source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"
  dnf()  { printf "dnf-called: %s\n" "$*"; return 0; }
  sudo() { "$@"; }
  os::dnf_install git curl
' 2>/dev/null)"; rc=$?
assert_eq       "dnf_install returns 0 on success"      "$rc" "0"
assert_contains "dnf_install runs dnf install for pkgs" "$out" "dnf-called: install -y git curl"

# failure: dnf exits non-zero -> os::dnf_install returns non-zero
assert_status "dnf_install propagates dnf failure" 1 bash -c '
  source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"
  dnf()  { return 1; }
  sudo() { "$@"; }
  os::dnf_install git
'

# no args is a harmless no-op (exit 0)
assert_status "dnf_install no-op on empty args" 0 bash -c '
  source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"
  os::dnf_install
'
