#!/usr/bin/env bash
ATLAS="$ATLAS_ROOT/atlas"

_self_test_home() {
  local d
  d="$(mktemp -d)" || return 1
  printf '%s\n' "$d"
}

_self_test_marker() {
  printf '%s\n' "$1/.local/state/atlas/installed/atlas-self"
}

_self_write_marker() {
  local home="$1" root="$2" executable="$3" remote_identity="${4:-github.com/thiva2k/atlas}" branch="${5:-main}"
  local marker dir
  marker="$(_self_test_marker "$home")"
  dir="$(dirname "$marker")"
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" || return 1
  {
    printf 'schema=1\n'
    printf 'state=installed\n'
    printf 'source=git\n'
    printf 'path=%s\n' "$root"
    printf 'remote=origin\n'
    printf 'remote_identity=%s\n' "$remote_identity"
    printf 'branch=%s\n' "$branch"
    printf 'ref=refs/heads/%s\n' "$branch"
    printf 'executable=%s\n' "$executable"
  } > "$marker" || return 1
  chmod 600 "$marker" || return 1
}

_self_fake_git() {
  local dir="$1" log="$2"
  local real_bash
  real_bash="$(command -v bash)" || return 1
  mkdir -p "$dir" || return 1
  cat > "$dir/git" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
log="${FAKE_GIT_LOG:?}"
root="${FAKE_GIT_ROOT:?}"
remote_url="${FAKE_GIT_REMOTE_URL:-https://github.com/thiva2k/atlas.git}"
branch="${FAKE_GIT_BRANCH:-main}"
status_out="${FAKE_GIT_STATUS:-}"
ff="${FAKE_GIT_FF:-yes}"
fetch_rc="${FAKE_GIT_FETCH_RC:-0}"
merge_rc="${FAKE_GIT_MERGE_RC:-0}"
if [ "${1:-}" = "-C" ]; then shift 2; fi
printf '%s\n' "$*" >> "$log"
case "${1:-}" in
  rev-parse)
    case "${2:-}" in
      --show-toplevel) printf '%s\n' "$root" ;;
      --verify) printf '%s\n' "refs/remotes/origin/main" ;;
      *) exit 1 ;;
    esac
    ;;
  remote)
    [ "${2:-}" = "get-url" ] && [ "${3:-}" = "origin" ] || exit 1
    printf '%s\n' "$remote_url"
    ;;
  symbolic-ref)
    [ "${2:-}" = "--short" ] && [ "${3:-}" = "HEAD" ] || exit 1
    [ "$branch" = "DETACHED" ] && exit 1
    printf '%s\n' "$branch"
    ;;
  status)
    [ -n "$status_out" ] && printf '%s\n' "$status_out"
    exit 0
    ;;
  fetch)
    exit "$fetch_rc"
    ;;
  merge-base)
    [ "$ff" = "yes" ] || exit 1
    ;;
  merge)
    [ "${2:-}" = "--ff-only" ] || exit 1
    exit "$merge_rc"
    ;;
  *)
    exit 1
    ;;
esac
EOF
  chmod +x "$dir/git" || return 1
  cat > "$dir/bash" <<EOF
#!$real_bash
set -uo pipefail
real_bash='$real_bash'
if [ "\$#" -eq 1 ] && [ "\$1" = "\${FAKE_GIT_ROOT:?}/tests/run.sh" ]; then
  printf '%s\n' "== 1 passed, 0 failed =="
  exit 0
fi
exec "\$real_bash" "\$@"
EOF
  chmod +x "$dir/bash" || return 1
  : > "$log" || return 1
}

_self_run() {
  local home="$1" fake_bin="$2"; shift 2
  HOME="$home" \
  ATLAS_STATE_DIR="$home/.local/state/atlas" \
  ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules_satisfied" \
  FAKE_GIT_ROOT="$ATLAS_ROOT" \
  FAKE_GIT_LOG="$home/git.log" \
  PATH="$fake_bin:$PATH" \
  atlas "$@"
}

out="$(bash "$ATLAS" --help 2>&1)"
assert_contains "help lists self-update" "$out" "self-update"

out="$(bash "$ATLAS" self-update --help 2>&1)"
assert_contains "self-update help shows usage" "$out" "Usage: atlas self-update"

home="$(_self_test_home)"
bin="$home/bin"
mkdir -p "$bin"
ln -s "$ATLAS" "$bin/atlas"
_self_fake_git "$bin" "$home/git.log"
out="$(_self_run "$home" "$bin" self-update 2>&1)"; rc=$?
assert_eq "self-update refuses unmanaged checkout" "$rc" "1"
assert_contains "self-update unmanaged refusal is explicit" "$out" "Refusing self-update."
assert_contains "self-update unmanaged refusal names managed state" "$out" "Repository is not in managed state."
assert_eq "self-update unmanaged checkout does not fetch" "$(grep -c '^fetch' "$home/git.log")" "0"

home="$(_self_test_home)"
bin="$home/bin"
mkdir -p "$bin"
ln -s "$ATLAS" "$bin/atlas"
_self_fake_git "$bin" "$home/git.log"
_self_write_marker "$home" "$ATLAS_ROOT" "$home/bin/not-atlas"
out="$(_self_run "$home" "$bin" self-update 2>&1)"; rc=$?
assert_eq "self-update refuses executable mismatch" "$rc" "1"
assert_contains "self-update executable mismatch is explicit" "$out" "Current Atlas executable does not match the managed installation."
assert_eq "self-update executable mismatch does not fetch" "$(grep -c '^fetch' "$home/git.log")" "0"

home="$(_self_test_home)"
bin="$home/bin"
mkdir -p "$bin"
ln -s "$ATLAS" "$bin/atlas"
_self_fake_git "$bin" "$home/git.log"
_self_write_marker "$home" "$ATLAS_ROOT" "$ATLAS"
out="$(FAKE_GIT_STATUS=" M atlas" _self_run "$home" "$bin" self-update 2>&1)"; rc=$?
assert_eq "self-update refuses dirty checkout" "$rc" "1"
assert_eq "self-update dirty checkout does not fetch" "$(grep -c '^fetch' "$home/git.log")" "0"

home="$(_self_test_home)"
bin="$home/bin"
mkdir -p "$bin"
ln -s "$ATLAS" "$bin/atlas"
_self_fake_git "$bin" "$home/git.log"
_self_write_marker "$home" "$ATLAS_ROOT" "$ATLAS" "github.com/thiva2k/not-atlas"
out="$(_self_run "$home" "$bin" self-update 2>&1)"; rc=$?
assert_eq "self-update refuses mismatched recorded remote identity" "$rc" "1"
assert_eq "self-update mismatched remote does not fetch" "$(grep -c '^fetch' "$home/git.log")" "0"

home="$(_self_test_home)"
bin="$home/bin"
mkdir -p "$bin"
ln -s "$ATLAS" "$bin/atlas"
_self_fake_git "$bin" "$home/git.log"
_self_write_marker "$home" "$ATLAS_ROOT" "$ATLAS"
out="$(FAKE_GIT_BRANCH="DETACHED" _self_run "$home" "$bin" self-update 2>&1)"; rc=$?
assert_eq "self-update refuses detached HEAD" "$rc" "1"
assert_eq "self-update detached HEAD does not fetch" "$(grep -c '^fetch' "$home/git.log")" "0"

home="$(_self_test_home)"
bin="$home/bin"
mkdir -p "$bin"
ln -s "$ATLAS" "$bin/atlas"
_self_fake_git "$bin" "$home/git.log"
_self_write_marker "$home" "$ATLAS_ROOT" "$ATLAS"
out="$(FAKE_GIT_FF="no" _self_run "$home" "$bin" self-update 2>&1)"; rc=$?
assert_eq "self-update refuses non-fast-forward" "$rc" "1"
assert_eq "self-update non-fast-forward fetches before refusal" "$(grep -c '^fetch origin' "$home/git.log")" "1"
assert_eq "self-update non-fast-forward does not merge" "$(grep -c '^merge --ff-only' "$home/git.log")" "0"

home="$(_self_test_home)"
bin="$home/bin"
mkdir -p "$bin"
ln -s "$ATLAS" "$bin/atlas"
_self_fake_git "$bin" "$home/git.log"
_self_write_marker "$home" "$ATLAS_ROOT" "$ATLAS"
out="$(_self_run "$home" "$bin" self-update 2>&1)"; rc=$?
assert_eq "self-update fast-forwards managed checkout" "$rc" "0"
assert_eq "self-update fetches recorded remote" "$(grep -c '^fetch origin' "$home/git.log")" "1"
assert_eq "self-update applies fast-forward only" "$(grep -c '^merge --ff-only origin/main' "$home/git.log")" "1"
assert_contains "self-update runs post-update status" "$out" "atlas status"

home="$(_self_test_home)"
bin="$home/bin"
mkdir -p "$bin"
ln -s "$ATLAS" "$bin/atlas"
_self_fake_git "$bin" "$home/git.log"
_self_write_marker "$home" "$ATLAS_ROOT" "$ATLAS"
out="$(_self_run "$home" "$bin" self-update --verify 2>&1)"; rc=$?
assert_eq "self-update --verify succeeds" "$rc" "0"
assert_contains "self-update --verify runs full suite" "$out" "passed, 0 failed"

home="$(_self_test_home)"
bin="$home/bin"
mkdir -p "$bin"
ln -s "$ATLAS" "$bin/atlas"
_self_fake_git "$bin" "$home/git.log"
_self_write_marker "$home" "$ATLAS_ROOT" "$ATLAS"
out="$(FAKE_GIT_REMOTE_URL="https://user:secret-token@evil.example/thiva2k/atlas.git" _self_run "$home" "$bin" self-update 2>&1)"; rc=$?
assert_eq "self-update refuses credentialed wrong remote" "$rc" "1"
case "$out" in
  *secret-token*) _t_fail "self-update redacts remote credentials" ;;
  *) _t_ok "self-update redacts remote credentials" ;;
esac

assert_status "atlas update atlas is not a self-update alias" 3 \
  bash -c 'ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules" bash "$ATLAS_ROOT/atlas" update atlas'
