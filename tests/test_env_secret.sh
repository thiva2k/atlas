#!/usr/bin/env bash
# env::get_secret — RFC-0003 §4.5
#
# Never touches the real $HOME: HOME and ATLAS_CONFIG_HOME are sandboxed.
# Assertions run in the OUTER scope; the code under test runs in a child
# `bash -c` so a failing assertion cannot be swallowed by a subshell.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
ATLAS_CONFIG_HOME="$HOME/.config/atlas"; export ATLAS_CONFIG_HOME
ATLAS_STATE_DIR="$HOME/.state"; export ATLAS_STATE_DIR
mkdir -p "$ATLAS_CONFIG_HOME"
unset ATLAS_GH_TOKEN 2>/dev/null || true
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/env.sh"
envfile="$ATLAS_CONFIG_HOME/atlas.env"
'

SECRET='gho_SUPERSECRET_TOKEN_VALUE'

# --- resolution ------------------------------------------------------------

out="$(bash -c "$PRE
ATLAS_GH_TOKEN='$SECRET' env::get_secret ATLAS_GH_TOKEN" 2>/dev/null)"
assert_eq "env var resolves" "$out" "$SECRET"

out="$(bash -c "$PRE
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$envfile\"; chmod 600 \"\$envfile\"
env::get_secret ATLAS_GH_TOKEN" 2>/dev/null)"
assert_eq "atlas.env mode 600 resolves" "$out" "$SECRET"

out="$(bash -c "$PRE
printf 'ATLAS_GH_TOKEN=%s\n' 'file-value' > \"\$envfile\"; chmod 600 \"\$envfile\"
ATLAS_GH_TOKEN='$SECRET' env::get_secret ATLAS_GH_TOKEN" 2>/dev/null)"
assert_eq "env var beats atlas.env" "$out" "$SECRET"

bash -c "$PRE
env::get_secret ATLAS_GH_TOKEN" >/dev/null 2>&1
assert_eq "absent key returns 1" "$?" "1"

bash -c "$PRE
printf 'OTHER=x\n' > \"\$envfile\"; chmod 600 \"\$envfile\"
env::get_secret ATLAS_GH_TOKEN" >/dev/null 2>&1
assert_eq "key missing from atlas.env returns 1" "$?" "1"

# --- permission refusal ----------------------------------------------------

for mode in 640 604 644 660 666; do
  bash -c "$PRE
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$envfile\"; chmod $mode \"\$envfile\"
env::get_secret ATLAS_GH_TOKEN" >/dev/null 2>&1
  assert_eq "mode $mode refuses (rc 1)" "$?" "1"
done

out="$(bash -c "$PRE
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$envfile\"; chmod 640 \"\$envfile\"
env::get_secret ATLAS_GH_TOKEN" 2>&1 || true)"
assert_contains "refusal names the file" "$out" "atlas.env"
assert_contains "refusal names the fix" "$out" "chmod 600"
case "$out" in
  *"$SECRET"*) _t_fail "refusal never prints the secret" ;;
  *) _t_ok "refusal never prints the secret" ;;
esac

# A group-readable atlas.env must not make the secret usable on stdout.
out="$(bash -c "$PRE
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$envfile\"; chmod 640 \"\$envfile\"
env::get_secret ATLAS_GH_TOKEN" 2>/dev/null || true)"
assert_eq "refused secret is not emitted on stdout" "$out" ""

# Mode 600 on a *symlinked* atlas.env is judged by the target, not the link.
out="$(bash -c "$PRE
real=\"\$HOME/real.env\"
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$real\"; chmod 600 \"\$real\"
ln -s \"\$real\" \"\$envfile\"
env::get_secret ATLAS_GH_TOKEN" 2>/dev/null)"
assert_eq "symlink to a 600 target resolves" "$out" "$SECRET"

bash -c "$PRE
real=\"\$HOME/real.env\"
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$real\"; chmod 644 \"\$real\"
ln -s \"\$real\" \"\$envfile\"
env::get_secret ATLAS_GH_TOKEN" >/dev/null 2>&1
assert_eq "symlink to a 644 target refuses" "$?" "1"

# --- xtrace containment ----------------------------------------------------

# With `set -x` active, the secret must not reach stderr, and xtrace must be
# restored afterwards (proven by tracing a sentinel command after the call).
err="$(bash -c "$PRE
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$envfile\"; chmod 600 \"\$envfile\"
set -x
env::get_secret ATLAS_GH_TOKEN >/dev/null
: xtrace-sentinel" 2>&1 || true)"
case "$err" in
  *"$SECRET"*) _t_fail "xtrace never leaks the secret" ;;
  *) _t_ok "xtrace never leaks the secret" ;;
esac
assert_contains "xtrace restored after the call" "$err" "xtrace-sentinel"

# Without xtrace, the call must not turn it on.
err="$(bash -c "$PRE
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$envfile\"; chmod 600 \"\$envfile\"
env::get_secret ATLAS_GH_TOKEN >/dev/null
: no-xtrace-sentinel" 2>&1 || true)"
case "$err" in
  *"no-xtrace-sentinel"*) _t_fail "xtrace stays off when it started off" ;;
  *) _t_ok "xtrace stays off when it started off" ;;
esac

# --- env::get keeps its semantics, but must not leak a neighbouring secret ---

out="$(bash -c "$PRE
printf 'ATLAS_GIT_USER_NAME=Ada\n' > \"\$envfile\"; chmod 644 \"\$envfile\"
env::get ATLAS_GIT_USER_NAME" 2>/dev/null)"
assert_eq "env::get still reads a 644 atlas.env (not a secret)" "$out" "Ada"

# env::get walks EVERY line of atlas.env. A preference lookup by one module
# (core/git wanting an identity) must not trace another module's credential.
# This is the leak the end-to-end `bash -x ./atlas install` run actually found.
err="$(bash -c "$PRE
{ printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET'; printf 'ATLAS_GIT_USER_NAME=Ada\n'; } > \"\$envfile\"
chmod 600 \"\$envfile\"
set -x
env::get ATLAS_GIT_USER_NAME >/dev/null
: get-sentinel" 2>&1 || true)"
case "$err" in
  *"$SECRET"*) _t_fail "env::get never traces a secret it was not asked for" ;;
  *) _t_ok "env::get never traces a secret it was not asked for" ;;
esac
assert_contains "env::get restores xtrace" "$err" "get-sentinel"

# ...and env::get still returns the value it *was* asked for, alongside a secret.
out="$(bash -c "$PRE
{ printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET'; printf 'ATLAS_GIT_USER_NAME=Ada\n'; } > \"\$envfile\"
chmod 600 \"\$envfile\"
env::get ATLAS_GIT_USER_NAME" 2>/dev/null)"
assert_eq "env::get finds a key that follows a secret" "$out" "Ada"

bash -c "$PRE
env::get NOPE_NOT_SET" >/dev/null 2>&1
assert_eq "env::get returns 1 for an absent key" "$?" "1"

# env::get must not trip a caller's `set -e` when the key is absent and the
# caller tests its status.
bash -c "$PRE
set -e
if env::get NOPE_NOT_SET >/dev/null; then echo found; fi
: survived" >/dev/null 2>&1
assert_eq "env::get missing key is safe under set -e" "$?" "0"
