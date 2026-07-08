#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"

assert_status "has_cmd true for bash"      0 os::has_cmd bash
assert_status "has_cmd false for nonesuch" 1 os::has_cmd this_command_does_not_exist_xyz
assert_status "require_cmd dies on missing" 5 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"; os::require_cmd nope_xyz'

out="$(os::dnf_install git curl 2>&1 || true)"
assert_contains "dnf_install logs intent" "$out" "git curl"
