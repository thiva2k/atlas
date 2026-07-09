#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/env.sh"

# sandbox a config home with an atlas.env
sandbox="$(mktemp -d)"
export ATLAS_CONFIG_HOME="$sandbox"
printf '# a comment\nATLAS_GIT_USER_NAME="Ada Lovelace"\nATLAS_GIT_USER_EMAIL=ada@example.com\n' > "$sandbox/atlas.env"

# value read from atlas.env (quotes stripped)
assert_eq "env::get reads a quoted value from atlas.env" \
  "$(unset ATLAS_GIT_USER_NAME; env::get ATLAS_GIT_USER_NAME)" "Ada Lovelace"
assert_eq "env::get reads an unquoted value from atlas.env" \
  "$(unset ATLAS_GIT_USER_EMAIL; env::get ATLAS_GIT_USER_EMAIL)" "ada@example.com"

# environment variable wins over the file
assert_eq "env var overrides atlas.env" \
  "$(ATLAS_GIT_USER_EMAIL='env@x' env::get ATLAS_GIT_USER_EMAIL)" "env@x"

# missing key -> non-zero, empty output
assert_status "missing key returns non-zero" 1 env::get ATLAS_DEFINITELY_MISSING_XYZ
assert_eq     "missing key prints nothing"   "$(env::get ATLAS_DEFINITELY_MISSING_XYZ 2>/dev/null)" ""

# comment lines are ignored (no key named '# a comment')
rm -rf "$sandbox"; unset ATLAS_CONFIG_HOME
