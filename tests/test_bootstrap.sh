#!/usr/bin/env bash
BOOT="$ATLAS_ROOT/bootstrap.sh"

assert_status "bootstrap parses (bash -n)" 0 bash -n "$BOOT"
assert_status "bootstrap --help exits 0"   0 bash "$BOOT" --help

out="$(bash "$BOOT" --help 2>&1)"
assert_contains "help mentions atlas install" "$out" "atlas install"
