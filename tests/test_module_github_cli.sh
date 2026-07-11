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
  # Real gh is a compiled binary: its internals never appear in the shell trace.
  # `local -` scopes shell options to this function so `set +x` is undone on
  # return, keeping the mock from leaking what the real binary could not.
  local -
  set +x
  printf "%s\n" "$*" >> "$GH_ARGV_LOG"
  [ "${GH_PRESENT:-0}" = 1 ] || return 127
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

# …nor in the persistent Atlas log file, which is an Atlas-owned file.
out="$(bash -c "$PRE; GH_PRESENT=1 ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install >/dev/null 2>&1
grep -rlF '$SECRET' \"\$ATLAS_STATE_DIR\" 2>/dev/null | wc -l")"
assert_eq "token never reaches an Atlas-owned log file" "$out" "0"

# --- xtrace containment ----------------------------------------------------
# An operator debugging with `bash -x ./atlas install …` must not have the token
# written to their terminal or their redirected trace file. env::get_secret
# guards its own body, but the value would be traced the instant it crossed back
# into the caller's scope — as `+ token=ghp_…` on assignment, and again on every
# expansion. The module therefore never assigns it.
err="$(bash -c "$PRE; GH_PRESENT=1 ATLAS_GH_TOKEN='$SECRET'; $MOD
set -x
module::install
set +x" 2>&1 || true)"
case "$err" in
  *"$SECRET"*) _t_fail "install never leaks the token under set -x" ;;
  *) _t_ok "install never leaks the token under set -x" ;;
esac
assert_contains "the set -x run really did trace" "$err" "gh auth login --with-token"

# Same, for a token supplied via atlas.env rather than the environment.
err="$(bash -c "$PRE; GH_PRESENT=1
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$ATLAS_CONFIG_HOME/atlas.env\"
chmod 600 \"\$ATLAS_CONFIG_HOME/atlas.env\"
$MOD
set -x
module::install
set +x" 2>&1 || true)"
case "$err" in
  *"$SECRET"*) _t_fail "atlas.env token never leaks under set -x" ;;
  *) _t_ok "atlas.env token never leaks under set -x" ;;
esac

# check() resolves the secret too — it must not leak it either.
err="$(bash -c "$PRE; GH_PRESENT=1 ATLAS_GH_TOKEN='$SECRET'; $MOD
set -x
module::check || true
set +x" 2>&1 || true)"
case "$err" in
  *"$SECRET"*) _t_fail "check never leaks the token under set -x" ;;
  *) _t_ok "check never leaks the token under set -x" ;;
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

out="$(bash -c "$PRE; GH_PRESENT=1
printf 'ATLAS_GH_TOKEN=%s\n' '$SECRET' > \"\$ATLAS_CONFIG_HOME/atlas.env\"
chmod 640 \"\$ATLAS_CONFIG_HOME/atlas.env\"
$MOD
module::install" 2>&1)"
assert_contains "group-readable atlas.env: refusal warns" "$out" "group- or world-readable"
assert_contains "group-readable atlas.env: warning names the fix" "$out" "chmod 600"
assert_contains "group-readable atlas.env: reported as unusable" "$out" "no usable ATLAS_GH_TOKEN"
case "$out" in
  *"$SECRET"*) _t_fail "group-readable atlas.env: secret never printed" ;;
  *) _t_ok "group-readable atlas.env: secret never printed" ;;
esac

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
# Anchored on the first argument, not a substring: a future gh flag containing
# the word "config" must not silently satisfy this assertion.
assert_eq "no hook ever invokes 'gh config'" \
  "$(printf '%s\n' "$argv" | grep -c '^config\b' || true)" "0"
assert_eq "no hook ever invokes 'gh auth setup-git'" \
  "$(printf '%s\n' "$argv" | grep -c '^auth setup-git\b' || true)" "0"
# …and the only gh subcommands this module uses at all are these two.
assert_eq "gh is only ever invoked as --version, auth token, or auth login" \
  "$(printf '%s\n' "$argv" | grep -vc -e '^--version$' -e '^auth token$' -e '^auth login --with-token$' || true)" "0"

out="$(bash -c "$PRE; ATLAS_GH_TOKEN='$SECRET'; $MOD
module::install >/dev/null 2>&1 || true
module::verify >/dev/null 2>&1 || true
module::update >/dev/null 2>&1 || true
[ -e \"\$GH_CONFIG_DIR/config.yml\" ] && echo EXISTS || echo ABSENT")"
assert_eq "no hook creates config.yml" "$out" "ABSENT"

# RFC-0003 §6.1 assumption 4: `gh --version` and `gh auth token` create nothing.
# So on a box where only probes run — check and verify, no token, no login —
# Atlas leaves no trace whatsoever in gh's config dir. (The install path above
# writes hosts.yml, so it cannot prove this; only a probe-only path can.)
out="$(bash -c "$PRE; GH_PRESENT=1; $MOD
module::check  >/dev/null 2>&1 || true
module::verify >/dev/null 2>&1 || true
find \"\$GH_CONFIG_DIR\" -mindepth 1 | wc -l")"
assert_eq "probe-only hooks leave the gh config dir empty" "$out" "0"

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

bash -c "$PRE; $MOD; module::verify" >/dev/null 2>&1
assert_eq "verify passes when gh absent before install" "$?" "0"

bash -c "$PRE; $MOD; mkdir -p \"\$(dirname \"\$(_gh_install_marker)\")\"; : > \"\$(_gh_install_marker)\"; module::verify" >/dev/null 2>&1
assert_eq "verify fails when Atlas marker exists but gh is absent" "$?" "1"

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
