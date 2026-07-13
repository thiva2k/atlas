#!/usr/bin/env bash
ATLAS="$ATLAS_ROOT/atlas"
# point the CLI at the fixture modules so it runs without real ones
export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"

assert_status "help exits 0"          0 bash "$ATLAS" --help
assert_status "version exits 0"       0 bash "$ATLAS" --version
assert_status "unknown verb exits 2"  2 bash "$ATLAS" frobnicate
assert_status "unknown option exits 2" 2 bash "$ATLAS" --nope
assert_status "install on fixtures 0" 0 bash "$ATLAS" install core/alpha apps/beta

out="$(bash "$ATLAS" --help 2>&1)"
assert_contains "help shows usage"    "$out" "Usage: atlas"
assert_contains "help lists install"  "$out" "install"

tmp="$(mktemp -d)"
ln -s "$ATLAS" "$tmp/atlasctl"
out="$(PATH="$tmp:$PATH" atlasctl --help 2>&1)"
assert_contains "help uses invoked launcher name" "$out" "Usage: atlasctl"

out="$(bash "$ATLAS" --version 2>&1)"
assert_contains "version prints a number" "$out" "0.1.0"
