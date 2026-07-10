#!/usr/bin/env bash
# Repo-wide enforcement of the secret-handling convention (docs/conventions.md,
# RFC-0003 §4.5). These rules were learned the hard way: a module that captured
# env::get_secret's output into a variable leaked the token under `bash -x`,
# because the resolver can only guard its own body.
#
# This is a static check over the source. It exists so the next credentialed
# module (core/ssh, Docker, Claude Code, Codex) cannot reintroduce the bug
# without a red test — the module-level xtrace tests only cover github-cli.

_modules() { find "$ATLAS_ROOT/modules" -name '*.sh' -type f; }
_sources() { find "$ATLAS_ROOT/modules" "$ATLAS_ROOT/internal" -name '*.sh' -type f; }

# Drop `file:line:` hits whose source line is a comment, so the rules police code
# rather than the comments that explain them.
_code_only() { grep -vE '^[^:]+:[0-9]+:[[:space:]]*#'; }

# 1. No source may capture a secret into a variable or command substitution.
#    `internal/env.sh` is exempt: its own `val="$(env::get …)"` runs inside the
#    guard, and resolving is precisely its job.
hits="$(_sources | grep -v '/internal/env\.sh$' \
  | xargs grep -nE '(=|\$\()[[:space:]]*"?\$\(env::get_secret' 2>/dev/null | _code_only || true)"
assert_eq "no source captures env::get_secret into a variable" "$hits" ""

# 2. A secret must never be interpolated into a log or error line.
hits="$(_sources | xargs grep -nE 'log::[a-z]+.*env::get_secret|die .*env::get_secret' 2>/dev/null \
  | _code_only || true)"
assert_eq "no source logs the result of env::get_secret" "$hits" ""

# 3. No MODULE may enable xtrace. Tracing expands arguments, so a secret would go
#    straight to stderr. (The resolvers in internal/env.sh legitimately *restore*
#    xtrace they themselves disabled; modules have no such business.)
hits="$(_modules | xargs grep -nE '\bset[[:space:]]+-[a-z]*x\b|set[[:space:]]+-o[[:space:]]+xtrace' \
  2>/dev/null | _code_only || true)"
assert_eq "no module enables xtrace" "$hits" ""

# 4. `gh auth token` prints the token. It may only ever appear as a discarded
#    predicate — never captured, never in a pipeline whose output is read.
hits="$(_sources | xargs grep -n 'gh auth token' 2>/dev/null | _code_only \
  | grep -v '>/dev/null 2>&1' || true)"
assert_eq "gh auth token is only ever a discarded predicate" "$hits" ""

# 5. Both resolvers must carry the xtrace guard: `atlas.env` holds secrets beside
#    preferences, and env::get walks every line of it to find one key.
for fn in 'env::get()' 'env::get_secret()'; do
  body="$(awk -v f="$fn" 'index($0, f) { on = 1 } on { print } on && /^}/ { exit }' \
    "$ATLAS_ROOT/internal/env.sh")"
  assert_contains "${fn%()} disables xtrace" "$body" 'set +x'
  assert_contains "${fn%()} restores xtrace" "$body" 'set -x'
done

# The guard must actually work, not merely be present. Prove it on the real
# functions: a secret in atlas.env must not reach the trace of EITHER resolver.
CANARY='ghp_DISCIPLINE_CANARY_0001'
for fn in env::get env::get_secret; do
  err="$(bash -c '
    set -euo pipefail
    HOME="$(mktemp -d)"; export HOME
    ATLAS_CONFIG_HOME="$HOME/c"; export ATLAS_CONFIG_HOME
    ATLAS_STATE_DIR="$HOME/s"; export ATLAS_STATE_DIR
    mkdir -p "$ATLAS_CONFIG_HOME"
    source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/log.sh"
    source "$ATLAS_ROOT/internal/env.sh"
    { printf "ATLAS_SECRET=%s\n" "'"$CANARY"'"; printf "ATLAS_PLAIN=ok\n"; } > "$ATLAS_CONFIG_HOME/atlas.env"
    chmod 600 "$ATLAS_CONFIG_HOME/atlas.env"
    set -x
    '"$fn"' ATLAS_PLAIN >/dev/null
    : trace-sentinel
  ' 2>&1 || true)"
  case "$err" in
    *"$CANARY"*) _t_fail "$fn does not trace a neighbouring secret" ;;
    *) _t_ok "$fn does not trace a neighbouring secret" ;;
  esac
  assert_contains "$fn leaves xtrace on afterwards" "$err" "trace-sentinel"
done

# 6. atlas.env must really be gitignored — RFC-0003 §4.4 and conventions.md both
#    assert it, and for a while nothing enforced it.
( cd "$ATLAS_ROOT" && git check-ignore -q atlas.env ) 2>/dev/null
assert_eq "atlas.env is gitignored at the repo root" "$?" "0"
( cd "$ATLAS_ROOT" && git check-ignore -q some/nested/dir/atlas.env ) 2>/dev/null
assert_eq "atlas.env is gitignored in a subdirectory" "$?" "0"

# …and the new ignore patterns must not shadow a file the repo actually tracks.
shadowed="$( cd "$ATLAS_ROOT" && git ls-files | while IFS= read -r f; do
  git check-ignore -q "$f" && printf '%s\n' "$f"
done )"
assert_eq "no tracked file is shadowed by .gitignore" "$shadowed" ""
