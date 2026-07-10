#!/usr/bin/env bash
# development/github-cli — RFC-0003
#
# No test runs real `dnf`, real `gh`, or touches the real $HOME.
#   - HOME, GH_CONFIG_DIR, ATLAS_CONFIG_HOME → fresh mktemp -d
#   - os::dnf_install and os::has_cmd are mocked
#   - `gh` is mocked as a shell function (functions beat PATH), recording both
#     argv and stdin so tests can assert what was asked of it.
#
# The mock encodes the gh contract observed in RFC-0003 §6.1. In particular it
# creates config.yml on NOTHING — `gh --version` and `gh auth token` leave a
# fresh config dir empty — so a test asserting "no hook creates config.yml"
# is meaningful.
#
# Assertions run in the OUTER scope; the code under test runs in a child
# `bash -c`, per the harness rule (assert_* inside ( … ) loses its counters).

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
GH_CONFIG_DIR="$HOME/.config/gh"; export GH_CONFIG_DIR
ATLAS_CONFIG_HOME="$HOME/.config/atlas"; export ATLAS_CONFIG_HOME
ATLAS_STATE_DIR="$HOME/.state"; export ATLAS_STATE_DIR
mkdir -p "$GH_CONFIG_DIR" "$ATLAS_CONFIG_HOME"
unset GH_TOKEN GITHUB_TOKEN ATLAS_GH_TOKEN 2>/dev/null || true

GH_ARGV_LOG="$HOME/gh.argv"; export GH_ARGV_LOG
GH_STDIN_LOG="$HOME/gh.stdin"; export GH_STDIN_LOG
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
: > "$GH_ARGV_LOG"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/env.sh"
source "$ATLAS_ROOT/internal/os.sh"

# --- mocked engine primitives ---------------------------------------------
os::dnf_install() { printf "%s\n" "$*" >> "$DNF_LOG"; GH_PRESENT=1; }
os::has_cmd() {
  case "$1" in
    gh) [ "${GH_PRESENT:-0}" = 1 ] ;;
    *)  command -v "$1" >/dev/null 2>&1 ;;
  esac
}

# --- mocked gh -------------------------------------------------------------
# GH_PRESENT=1        gh is installed
# GH_STORED=1         a credential exists on disk (hosts.yml)
# GH_REJECT=1         `gh auth login --with-token` rejects the token
gh() {
  printf "%s\n" "$*" >> "$GH_ARGV_LOG"
  case "${1:-}" in
    --version) printf "gh version 2.94.0 (mock)\n"; return 0 ;;
    auth)
      case "${2:-}" in
        token)
          # gh prints the token on stdout when one exists. That is the hazard
          # this module must never capture; the mock reproduces it faithfully.
          if [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
            printf "%s\n" "${GH_TOKEN:-${GITHUB_TOKEN:-}}"; return 0
          fi
          [ "${GH_STORED:-0}" = 1 ] || return 1
          printf "gho_STORED_CREDENTIAL\n"; return 0
          ;;
        login)
          local piped; piped="$(cat)"
          printf "%s" "$piped" > "$GH_STDIN_LOG"
          if [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
            printf "The value of the GH_TOKEN environment variable is being used for authentication.\n" >&2
            return 1
          fi
          [ "${GH_REJECT:-0}" = 1 ] && { printf "error validating token\n" >&2; return 1; }
          GH_STORED=1
          printf "oauth_token: x\n" > "$GH_CONFIG_DIR/hosts.yml"
          return 0
          ;;
        setup-git) return 0 ;;
      esac
      return 0
      ;;
    config) return 0 ;;   # recorded; tests assert it is never reached
  esac
  return 0
}'
# NOTE: PRE deliberately ends on the closing brace, with no trailing newline, so
# that `bash -c "$PRE; …"` composes into `}; …` rather than a newline followed by
# a bare `;` — which is a syntax error.

MOD='source "$ATLAS_MODULES_DIR/development/github-cli/module.sh"'
SECRET='gho_ATLAS_SUPPLIED_TOKEN'

# ---------------------------------------------------------------------------
# check
# ---------------------------------------------------------------------------

bash -c "$PRE; $MOD; module::check" >/dev/null 2>&1
assert_eq "check fails when gh is absent" "$?" "1"

bash -c "$PRE; GH_PRESENT=1; $MOD; module::check" >/dev/null 2>&1
assert_eq "check passes: gh present, no token, unauthenticated" "$?" "0"

bash -c "$PRE; GH_PRESENT=1 GH_STORED=1; $MOD; module::check" >/dev/null 2>&1
assert_eq "check passes: gh present, authenticated" "$?" "0"

bash -c "$PRE; GH_PRESENT=1 ATLAS_GH_TOKEN='$SECRET'; $MOD; module::check" >/dev/null 2>&1
assert_eq "check fails: token resolvable but gh logged out" "$?" "1"

bash -c "$PRE; GH_PRESENT=1 GH_STORED=1 ATLAS_GH_TOKEN='$SECRET'; $MOD; module::check" >/dev/null 2>&1
assert_eq "check passes: token resolvable and already authenticated" "$?" "0"

bash -c "$PRE; GH_PRESENT=1; export GH_TOKEN='$SECRET'; $MOD; module::check" >/dev/null 2>&1
assert_eq "check passes: GH_TOKEN exported (ephemeral auth)" "$?" "0"

# ---------------------------------------------------------------------------
# install — package
# ---------------------------------------------------------------------------

out="$(bash -c "$PRE; $MOD; module::install; cat \"\$DNF_LOG\"" 2>/dev/null)"
assert_eq "install installs gh when absent" "$out" "gh"

out="$(bash -c "$PRE; GH_PRESENT=1; $MOD; module::install; cat \"\$DNF_LOG\" 2>/dev/null || true" 2>/dev/null)"
assert_eq "install does not reinstall a present gh" "$out" ""

# ---------------------------------------------------------------------------
# install — authentication
# ---------------------------------------------------------------------------

# Token supplied → reaches gh on stdin, never in argv.
out="$(bash -c "$PRE; GH_PRESENT=1 ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install >/dev/null 2>&1
cat \"\$GH_STDIN_LOG\"")"
assert_eq "token reaches gh on stdin" "$out" "$SECRET"

argv="$(bash -c "$PRE; GH_PRESENT=1 ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install >/dev/null 2>&1
cat \"\$GH_ARGV_LOG\"")"
case "$argv" in
  *"$SECRET"*) _t_fail "token never appears in gh argv" ;;
  *) _t_ok "token never appears in gh argv" ;;
esac
assert_contains "gh auth login --with-token is invoked" "$argv" "auth login --with-token"

# The token must never appear in any log line either.
logged="$(bash -c "$PRE; GH_PRESENT=1 ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install" 2>&1 || true)"
case "$logged" in
  *"$SECRET"*) _t_fail "token never appears in a log line" ;;
  *) _t_ok "token never appears in a log line" ;;
esac

# Token supplied from atlas.env (mode 600).
out="$(bash -c "$PRE; GH_PRESENT=1
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$ATLAS_CONFIG_HOME/atlas.env\"
chmod 600 \"\$ATLAS_CONFIG_HOME/atlas.env\"
$MOD
module::install >/dev/null 2>&1
cat \"\$GH_STDIN_LOG\"")"
assert_eq "token from atlas.env reaches gh on stdin" "$out" "$SECRET"

# atlas.env group-readable → secret not consumed, install still succeeds.
bash -c "$PRE; GH_PRESENT=1
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$ATLAS_CONFIG_HOME/atlas.env\"
chmod 640 \"\$ATLAS_CONFIG_HOME/atlas.env\"
$MOD
module::install" >/dev/null 2>&1
assert_eq "group-readable atlas.env: install still succeeds" "$?" "0"

argv="$(bash -c "$PRE; GH_PRESENT=1
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$ATLAS_CONFIG_HOME/atlas.env\"
chmod 640 \"\$ATLAS_CONFIG_HOME/atlas.env\"
$MOD
module::install >/dev/null 2>&1
cat \"\$GH_ARGV_LOG\"")"
case "$argv" in
  *"auth login"*) _t_fail "group-readable atlas.env: secret not consumed" ;;
  *) _t_ok "group-readable atlas.env: secret not consumed" ;;
esac

# No token → warn, succeed.
out="$(bash -c "$PRE; GH_PRESENT=1; $MOD; module::install" 2>&1)"; rc=$?
assert_eq "no token: install succeeds" "$rc" "0"
assert_contains "no token: warns with the command to run" "$out" "gh auth login"

# Already authenticated on disk → auth untouched.
argv="$(bash -c "$PRE; GH_PRESENT=1 GH_STORED=1 ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install >/dev/null 2>&1
cat \"\$GH_ARGV_LOG\"")"
case "$argv" in
  *"auth login"*) _t_fail "already authenticated: no re-login" ;;
  *) _t_ok "already authenticated: no re-login" ;;
esac

# Exported GH_TOKEN → gh auth login is never invoked at all.
argv="$(bash -c "$PRE; GH_PRESENT=1; export GH_TOKEN='$SECRET'; $MOD
module::install >/dev/null 2>&1
cat \"\$GH_ARGV_LOG\"")"
case "$argv" in
  *"auth login"*) _t_fail "GH_TOKEN exported: no gh auth login" ;;
  *) _t_ok "GH_TOKEN exported: no gh auth login" ;;
esac

argv="$(bash -c "$PRE; GH_PRESENT=1; unset GH_TOKEN; export GITHUB_TOKEN='$SECRET'; $MOD
module::install >/dev/null 2>&1
cat \"\$GH_ARGV_LOG\"")"
case "$argv" in
  *"auth login"*) _t_fail "GITHUB_TOKEN exported: no gh auth login" ;;
  *) _t_ok "GITHUB_TOKEN exported: no gh auth login" ;;
esac

# Even with an ATLAS_GH_TOKEN available, an exported GH_TOKEN wins (gh refuses
# --with-token in that state, so attempting it would hard-fail the install).
bash -c "$PRE; GH_PRESENT=1; export GH_TOKEN='env-tok'; ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install" >/dev/null 2>&1
assert_eq "GH_TOKEN exported beats ATLAS_GH_TOKEN, install succeeds" "$?" "0"

# Rejected token (or unreachable network) → hard failure.
bash -c "$PRE; GH_PRESENT=1 GH_REJECT=1 ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install" >/dev/null 2>&1
assert_eq "rejected token fails install" "$?" "1"

out="$(bash -c "$PRE; GH_PRESENT=1 GH_REJECT=1 ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install" 2>&1 || true)"
case "$out" in
  *"$SECRET"*) _t_fail "rejected token is not echoed in the error" ;;
  *) _t_ok "rejected token is not echoed in the error" ;;
esac

# ---------------------------------------------------------------------------
# Atlas owns no gh configuration (RFC-0003 §4.6, §4.7)
# ---------------------------------------------------------------------------

argv="$(bash -c "$PRE; ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install >/dev/null 2>&1 || true
module::verify >/dev/null 2>&1 || true
module::update >/dev/null 2>&1 || true
module::backup >/dev/null 2>&1 || true
module::restore >/dev/null 2>&1 || true
module::check  >/dev/null 2>&1 || true
cat \"\$GH_ARGV_LOG\"")"
case "$argv" in
  *config*) _t_fail "no hook ever invokes 'gh config'" ;;
  *) _t_ok "no hook ever invokes 'gh config'" ;;
esac
case "$argv" in
  *setup-git*) _t_fail "no hook ever invokes 'gh auth setup-git'" ;;
  *) _t_ok "no hook ever invokes 'gh auth setup-git'" ;;
esac

out="$(bash -c "$PRE; ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install >/dev/null 2>&1 || true
module::verify >/dev/null 2>&1 || true
module::update >/dev/null 2>&1 || true
[ -e \"\$GH_CONFIG_DIR/config.yml\" ] && echo EXISTS || echo ABSENT")"
assert_eq "no hook creates config.yml" "$out" "ABSENT"

# `gh auth token` is only ever used as a predicate: stdout discarded.
out="$(bash -c "$PRE; GH_PRESENT=1 GH_STORED=1; $MOD; module::verify" 2>&1)"
case "$out" in
  *gho_STORED_CREDENTIAL*) _t_fail "verify never captures 'gh auth token' stdout" ;;
  *) _t_ok "verify never captures 'gh auth token' stdout" ;;
esac

out="$(bash -c "$PRE; GH_PRESENT=1 GH_STORED=1 ATLAS_GH_TOKEN='$SECRET'; $MOD; module::check" 2>&1)"
case "$out" in
  *gho_STORED_CREDENTIAL*) _t_fail "check never captures 'gh auth token' stdout" ;;
  *) _t_ok "check never captures 'gh auth token' stdout" ;;
esac

# ---------------------------------------------------------------------------
# verify
# ---------------------------------------------------------------------------

bash -c "$PRE; GH_PRESENT=1 GH_STORED=1; $MOD; module::verify" >/dev/null 2>&1
assert_eq "verify passes when authenticated" "$?" "0"

out="$(bash -c "$PRE; GH_PRESENT=1; $MOD; module::verify" 2>&1)"; rc=$?
assert_eq "verify passes when unauthenticated" "$rc" "0"
assert_contains "verify warns when unauthenticated" "$out" "not authenticated"

out="$(bash -c "$PRE; GH_PRESENT=1; export GH_TOKEN='$SECRET'; $MOD; module::verify" 2>&1)"
assert_contains "verify reports ephemeral env auth" "$out" "GH_TOKEN"
case "$out" in
  *"$SECRET"*) _t_fail "verify never prints the env token's value" ;;
  *) _t_ok "verify never prints the env token's value" ;;
esac

# `gh --version` failing is a real failure.
bash -c "$PRE; GH_PRESENT=1; $MOD
gh() { return 1; }
module::verify" >/dev/null 2>&1
assert_eq "verify fails when gh --version fails" "$?" "1"

# ---------------------------------------------------------------------------
# update / backup / restore — no-ops that succeed
# ---------------------------------------------------------------------------

for hook in update backup restore; do
  bash -c "$PRE; GH_PRESENT=1; $MOD; module::$hook" >/dev/null 2>&1
  assert_eq "$hook is a no-op that succeeds" "$?" "0"
done

# No hook writes anything into the gh config dir.
out="$(bash -c "$PRE; GH_PRESENT=1; $MOD
module::update >/dev/null 2>&1; module::backup >/dev/null 2>&1; module::restore >/dev/null 2>&1
find \"\$GH_CONFIG_DIR\" -mindepth 1 | wc -l")"
assert_eq "update/backup/restore leave the gh config dir untouched" "$out" "0"

# `remove` is deliberately not defined (RFC-0003 §4.8).
bash -c "$PRE; $MOD; declare -F module::remove >/dev/null" >/dev/null 2>&1
assert_eq "no remove hook is defined" "$?" "1"

# ---------------------------------------------------------------------------
# metadata + dependency graph
# ---------------------------------------------------------------------------

out="$(bash -c "$PRE; $MOD; printf '%s\n' \"\$MODULE_NAME\"")"
assert_eq "MODULE_NAME" "$out" "github-cli"

out="$(bash -c "$PRE; $MOD; printf '%s\n' \"\${MODULE_DEPENDS[@]}\"")"
assert_eq "MODULE_DEPENDS is core/git" "$out" "core/git"

out="$(bash -c "$PRE
source \"\$ATLAS_ROOT/internal/module.sh\"
module::resolve_order development/github-cli" 2>/dev/null)"
assert_eq "resolve_order puts core/git first" "$out" "core/git
development/github-cli"

# ---------------------------------------------------------------------------
# through the runner (production flags: set -euo pipefail)
# ---------------------------------------------------------------------------

# `set +e; set -uo pipefail` is what the `atlas` entrypoint runs with (a fresh
# script has no `-e`; PRE turned it on, so it must be turned back off — `set -uo
# pipefail` alone does NOT clear it). This is load-bearing:
# runner::run tallies failures via `out="$(_runner_run_module …)"`;
# under a caller's `set -e` the shell dies on the first failing module and the
# tally never runs, so the process exits with the hook's own status instead of
# ATLAS_EXIT_MODULE. Hooks still get `set -euo pipefail` from the runner's own
# subshell, which is the seam these tests exist to exercise.
#
# Ends without a trailing newline, for the same reason PRE does.
RUNNER='
set +e; set -uo pipefail
source "$ATLAS_ROOT/internal/module.sh"
source "$ATLAS_ROOT/internal/runner.sh"'

# `atlas install development/github-cli` installs core/git first. Tests that
# exercise a verb *after* provisioning must do the same.
DEPS='runner::run install core/git development/github-cli >/dev/null 2>&1'

bash -c "$PRE; $RUNNER; GH_PRESENT=1 GH_STORED=1
runner::run install development/github-cli" >/dev/null 2>&1
assert_eq "runner: install on a satisfied box exits 0" "$?" "0"

out="$(bash -c "$PRE; $RUNNER; GH_PRESENT=1 GH_STORED=1
runner::run install development/github-cli" 2>&1)"
assert_contains "runner: satisfied box is skipped" "$out" "already satisfied"

# gh absent → check fails → install runs → dnf invoked.
out="$(bash -c "$PRE; $RUNNER
runner::run install development/github-cli >/dev/null 2>&1
cat \"\$DNF_LOG\"")"
assert_eq "runner: install runs dnf when gh is absent" "$out" "gh"

# Token resolvable + logged out → check fails → install authenticates.
out="$(bash -c "$PRE; $RUNNER; GH_PRESENT=1; export ATLAS_GH_TOKEN='$SECRET'
runner::run install development/github-cli >/dev/null 2>&1
cat \"\$GH_STDIN_LOG\"")"
assert_eq "runner: install authenticates from a supplied token" "$out" "$SECRET"

# Rejected token → the runner tallies a module failure and returns exit 4.
# (A hook that `return 1`s, not one that `die`s — so this really does prove the
# tally converts a hook failure into ATLAS_EXIT_MODULE.)
bash -c "$PRE; $RUNNER; GH_PRESENT=1 GH_REJECT=1; export ATLAS_GH_TOKEN='$SECRET'
runner::run install development/github-cli" >/dev/null 2>&1
assert_eq "runner: rejected token exits 4 (module failure)" "$?" "4"

out="$(bash -c "$PRE; $RUNNER; GH_PRESENT=1 GH_REJECT=1; export ATLAS_GH_TOKEN='$SECRET'
runner::run install development/github-cli" 2>&1)"
assert_contains "runner: the dependency still succeeded" "$out" "1 ok, 0 skipped, 1 failed"

bash -c "$PRE; $RUNNER; GH_PRESENT=1
$DEPS
runner::run verify development/github-cli" >/dev/null 2>&1
assert_eq "runner: verify on an unauthenticated box exits 0" "$?" "0"

bash -c "$PRE; $RUNNER; GH_PRESENT=1
$DEPS
runner::run doctor development/github-cli" >/dev/null 2>&1
assert_eq "runner: doctor on an unauthenticated box exits 0" "$?" "0"

for verb in update backup restore; do
  bash -c "$PRE; $RUNNER; GH_PRESENT=1
runner::run $verb development/github-cli" >/dev/null 2>&1
  assert_eq "runner: $verb exits 0" "$?" "0"
done

out="$(bash -c "$PRE; $RUNNER; GH_PRESENT=1 GH_STORED=1
runner::run status development/github-cli" 2>&1)"
assert_contains "runner: status reports installed" "$out" "installed"

out="$(bash -c "$PRE; $RUNNER
runner::run status development/github-cli" 2>&1)"
assert_contains "runner: status reports not installed" "$out" "not installed"

# The real $HOME was never a target: prove the module reads GH_CONFIG_DIR.
out="$(bash -c "$PRE; $RUNNER; GH_PRESENT=1; export ATLAS_GH_TOKEN='$SECRET'
runner::run install development/github-cli >/dev/null 2>&1
[ -f \"\$GH_CONFIG_DIR/hosts.yml\" ] && echo SANDBOXED || echo LEAKED")"
assert_eq "credentials land in the sandboxed GH_CONFIG_DIR" "$out" "SANDBOXED"
