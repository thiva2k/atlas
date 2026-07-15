#!/usr/bin/env bash
# earlier tests export ATLAS_MODULES_DIR to point at fixtures, and internal/module.sh
# guards itself against being sourced twice (so a bare unset won't restore its
# default here) since tests/run.sh sources every test file in one shell. Pin it
# back to the real modules dir explicitly.
export ATLAS_MODULES_DIR="$ATLAS_ROOT/modules"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/module.sh"   # uses real ATLAS_MODULES_DIR ($ATLAS_ROOT/modules)

expected="apps/brave core/git core/ssh desktop/cursor desktop/fastfetch desktop/fonts desktop/icons desktop/kde desktop/kde-profile desktop/lockscreen desktop/notifications desktop/plymouth desktop/power desktop/sddm desktop/theme desktop/utilities desktop/wallpapers development/claude development/codex development/docker development/fish development/ghostty development/github-cli development/node development/pnpm development/python development/starship development/uv"
got="$(module::discover | tr '\n' ' ' | sed 's/ *$//')"
assert_eq "all twenty-eight modules discovered" "$got" "$expected"

# every module satisfies the contract: metadata + three required hooks + README
fail=0
while IFS= read -r id; do
  p="$(module::path "$id")"
  ( source "$p"
    [ -n "${MODULE_NAME:-}" ]        || exit 1
    [ -n "${MODULE_DESCRIPTION:-}" ] || exit 1
    declare -F module::check   >/dev/null || exit 1
    declare -F module::install >/dev/null || exit 1
    declare -F module::verify  >/dev/null || exit 1 ) || { fail=1; printf 'contract miss: %s\n' "$id"; }
  [ -r "${p%/module.sh}/README.md" ] || { fail=1; printf 'missing README: %s\n' "$id"; }
done < <(module::discover)
assert_eq "every module satisfies the contract + has a README" "$fail" "0"
