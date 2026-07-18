#!/usr/bin/env bash
# desktop/hyprland build helper — syntax + guardrails only (no real mock run).
HELPER="$ATLAS_ROOT/modules/desktop/hyprland/build/build-aquamarine.sh"

assert_status "build helper is valid bash" 0 bash -n "$HELPER"
assert_status "build helper pins the exact release string" 0 \
  bash -c "grep -qF '2%{?dist}.atlas1' \"$HELPER\""
assert_status "build helper never bumps the aquamarine version" 1 \
  bash -c "grep -qE 'aquamarine-0\.(9\.[6-9]|1[0-9])' \"$HELPER\""
