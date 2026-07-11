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

# ---------------------------------------------------------------------------
# RFC-0004 additions. Each rule below was learned by probing, and each is
# verified further down to fire on a planted violation.
# ---------------------------------------------------------------------------

# 7. A process substitution runs in a subshell that INHERITS xtrace. So
#    `3< <(printf '%s' "$pass")` traces `++ printf '%s' hunter2`, while
#    `3< <(env::get_secret KEY)` does not — the guard lives inside the resolver.
#    Therefore the producer feeding a secret file descriptor must be
#    env::get_secret and nothing else.
hits="$(_sources | xargs grep -nE '[0-9]<[[:space:]]*<\(' 2>/dev/null | _code_only \
  | grep -v '<(env::get_secret' || true)"
assert_eq "a secret fd is only ever fed by env::get_secret" "$hits" ""

# 8. gpg must take the passphrase on a file descriptor. `--passphrase` puts it in
#    argv (world-readable in /proc); `--passphrase-file` puts it on disk.
hits="$(_sources | xargs grep -nE 'gpg[^|]*--passphrase(-file)?[[:space:]]' 2>/dev/null \
  | _code_only || true)"
assert_eq "gpg never takes a passphrase in argv or from a file" "$hits" ""

# 9. `ssh-keygen -N` places the passphrase in argv. It is admissible ONLY as the
#    documented empty-passphrase form, `-N ''` / `-N ""`.
hits="$(_sources | xargs grep -nE "ssh-keygen[^|]*-N[[:space:]]+" 2>/dev/null | _code_only \
  | grep -vE "\-N[[:space:]]+(''|\"\")" || true)"
assert_eq "ssh-keygen -N appears only as the empty-passphrase form" "$hits" ""

# 10. `mktemp` must never be used unchecked: `set -e` is suspended inside hooks
#     (RFC-0004 §4.0), so a failed `d=$(mktemp -d)` yields an empty string and a
#     later `rm -rf "$d"/` becomes `rm -rf /`. Every mktemp must be followed by a
#     `||` on the same line, or be the subject of an `if !`.
hits="$(_sources | xargs grep -nE '\$\(mktemp' 2>/dev/null | _code_only \
  | grep -vE '\|\||^[^:]+:[0-9]+:[[:space:]]*if[[:space:]]+!' || true)"
assert_eq "every mktemp is failure-checked (set -e is off inside hooks)" "$hits" ""

# --- the rules must FIRE, not merely exist -------------------------------
# A static rule nobody has seen fail is a rule nobody knows works. Plant each
# violation in a scratch tree and assert the corresponding grep catches it.
_plant() { # <filename> <line> -> echoes the rule's hit count
  local f="$1" line="$2" d
  d="$(mktemp -d)"; mkdir -p "$d/modules/x/y" "$d/internal"
  printf '#!/usr/bin/env bash\n%s\n' "$line" > "$d/modules/x/y/module.sh"
  printf '%s' "$d"
}

d="$(_plant m 'gpg --symmetric --passphrase-fd 3 -o out.gpg 3< <(printf "%s" "$pass")')"
hits="$(find "$d" -name '*.sh' | xargs grep -nE '[0-9]<[[:space:]]*<\(' 2>/dev/null | _code_only \
  | grep -v '<(env::get_secret' || true)"
assert_contains "rule 7 fires on a planted printf-fed secret fd" "$hits" 'printf'
rm -rf "$d"

d="$(_plant m 'gpg --batch --symmetric --passphrase "$pass" -o out.gpg in.tar')"
hits="$(find "$d" -name '*.sh' | xargs grep -nE 'gpg[^|]*--passphrase(-file)?[[:space:]]' 2>/dev/null | _code_only || true)"
assert_contains "rule 8 fires on a planted gpg --passphrase" "$hits" '--passphrase'
rm -rf "$d"

d="$(_plant m 'ssh-keygen -t ed25519 -f "$k" -N "$pass" -q')"
hits="$(find "$d" -name '*.sh' | xargs grep -nE "ssh-keygen[^|]*-N[[:space:]]+" 2>/dev/null | _code_only \
  | grep -vE "\-N[[:space:]]+(''|\"\")" || true)"
assert_contains "rule 9 fires on a planted ssh-keygen -N \$pass" "$hits" 'ssh-keygen'
rm -rf "$d"

d="$(_plant m 'staging="$(mktemp -d)"')"
hits="$(find "$d" -name '*.sh' | xargs grep -nE '\$\(mktemp' 2>/dev/null | _code_only \
  | grep -vE '\|\||^[^:]+:[0-9]+:[[:space:]]*if[[:space:]]+!' || true)"
assert_contains "rule 10 fires on a planted unchecked mktemp" "$hits" 'mktemp'
rm -rf "$d"

# …and rule 9 must NOT fire on the legitimate empty-passphrase form.
d="$(_plant m "ssh-keygen -t ed25519 -f \"\$k\" -N '' -q")"
hits="$(find "$d" -name '*.sh' | xargs grep -nE "ssh-keygen[^|]*-N[[:space:]]+" 2>/dev/null | _code_only \
  | grep -vE "\-N[[:space:]]+(''|\"\")" || true)"
assert_eq "rule 9 does not fire on the documented -N '' form" "$hits" ""
rm -rf "$d"

# 11. The backup passphrase is platform-wide (RFC-0004 Decision 5). No module may
#     invent its own — one secret, one verb.
hits="$(_modules | xargs grep -nE 'ATLAS_[A-Z]+_BACKUP_PASSPHRASE' 2>/dev/null | _code_only || true)"
assert_eq "no module invents a per-module backup passphrase" "$hits" ""
