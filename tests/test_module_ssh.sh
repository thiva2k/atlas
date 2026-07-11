#!/usr/bin/env bash
# core/ssh — RFC-0004
#
# No test runs real `dnf`, real `gh`, or touches the real $HOME.
#   - HOME, ATLAS_CONFIG_HOME, ATLAS_STATE_DIR, GNUPGHOME, GH_CONFIG_DIR → fresh mktemp -d
#   - os::dnf_install / os::has_cmd mocked; `gh` mocked as a shell function
#   - ssh-keygen, tar and gpg are REAL. They are hermetic and fast, and mocking
#     them would test the mock rather than the property we claim about the artifact.
#
# Hooks are invoked as the runner invokes them — `if ! module::x` — NOT bare under
# `set -e`. RFC-0004 §4.0: errexit is suspended inside a hook and all its callees,
# so a bare-under-`-e` test is stricter than production and would pass a hook that
# silently marches on in the field.
#
# Assertions run in the OUTER scope; code under test runs in a child `bash -c`.
# PRE must NOT end with a newline (`"$PRE; body"` would yield a bare `;`).

PRE='
set -uo pipefail
HOME="$(mktemp -d)"; export HOME
ATLAS_CONFIG_HOME="$HOME/.config/atlas"; export ATLAS_CONFIG_HOME
ATLAS_STATE_DIR="$HOME/.state"; export ATLAS_STATE_DIR
GH_CONFIG_DIR="$HOME/.config/gh"; export GH_CONFIG_DIR
GNUPGHOME="$HOME/.gnupg"; export GNUPGHOME
ATLAS_SSH_STAGING_DIR="$HOME/.staging"; export ATLAS_SSH_STAGING_DIR
mkdir -p "$ATLAS_SSH_STAGING_DIR"
mkdir -p "$ATLAS_CONFIG_HOME" "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
unset ATLAS_SSH_KEY_PASSPHRASE ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE ATLAS_SSH_IMPORT_KEY \
      ATLAS_BACKUP_PASSPHRASE GH_TOKEN GITHUB_TOKEN 2>/dev/null || true

GH_ARGV_LOG="$HOME/gh.argv"; export GH_ARGV_LOG
GH_STDIN_LOG="$HOME/gh.stdin"; export GH_STDIN_LOG
GH_KEYS="$HOME/gh.keys";      export GH_KEYS
DNF_LOG="$HOME/dnf.log";      export DNF_LOG
: > "$GH_ARGV_LOG"; : > "$GH_KEYS"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/env.sh"
source "$ATLAS_ROOT/internal/os.sh"

os::dnf_install() { printf "%s\n" "$*" >> "$DNF_LOG"; }
os::has_cmd() {
  case "$1" in
    gh) [ "${GH_PRESENT:-0}" = 1 ] ;;
    *)  command -v "$1" >/dev/null 2>&1 ;;
  esac
}

# --- mocked gh -------------------------------------------------------------
# GH_PRESENT=1  installed        GH_AUTHED=1  a credential exists on disk
# $GH_KEYS      one pubkey blob per line, as api user/keys would return
gh() {
  local -                       # real gh is a compiled binary; its internals never trace
  set +x
  printf "%s\n" "$*" >> "$GH_ARGV_LOG"
  case "${1:-}" in
    --version) printf "gh version 2.94.0 (mock)\n"; return 0 ;;
    auth)
      # `gh auth token` PRINTS the token. Atlas may only use it as a predicate.
      [ "${2:-}" = "token" ] || return 1
      [ "${GH_AUTHED:-0}" = 1 ] || return 1
      printf "gho_MOCKTOKEN\n"; return 0 ;;
    api)
      [ "${GH_AUTHED:-0}" = 1 ] || { printf "gh: not authenticated\n" >&2; return 1; }
      case "${2:-}" in user/keys) cut -d" " -f1,2 < "$GH_KEYS"; return 0 ;; esac
      return 1 ;;
    ssh-key)
      [ "${2:-}" = "add" ] || return 1
      [ "${GH_AUTHED:-0}" = 1 ] || { printf "gh: not authenticated\n" >&2; return 1; }
      [ "${GH_SCOPE_DENIED:-0}" = 1 ] && { printf "gh: missing admin:public_key\n" >&2; return 1; }
      cat >> "$GH_STDIN_LOG"          # `gh ssh-key add -` reads the pubkey from stdin
      cut -d" " -f1,2 < "$GH_STDIN_LOG" | tail -1 >> "$GH_KEYS"
      printf "Public key added to your account\n"; return 0 ;;
  esac
  return 1
}

MOD="$ATLAS_ROOT/modules/core/ssh/module.sh"
source "$MOD"

# helpers used by the test bodies -------------------------------------------
mkkey() { ssh-keygen -t ed25519 -f "$1" -N "${2:-}" -q -C "${3:-test}" </dev/null; }
manifest() { printf "%s\n" "$ATLAS_CONFIG_HOME/ssh/manifest"; }
artifact() { printf "%s\n" "$ATLAS_STATE_DIR/backup/core-ssh.tar.gpg"; }
backup_candidates() {
  local a dir base
  a="$(artifact)"; dir="$(dirname "$a")"; base="$(basename "$a")"
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name "$base.tmp.*" -print 2>/dev/null
}
candidate_count() { backup_candidates | wc -l | tr -d " "; }
setpass() { printf "%s=%s\n" "$1" "$2" >> "$ATLAS_CONFIG_HOME/atlas.env"; chmod 600 "$ATLAS_CONFIG_HOME/atlas.env"; }
run_hook() { if ! "module::$1"; then return 1; fi; return 0; }
require_hook() {
  if ! run_hook "$1"; then
    printf "fixture failed: module::%s\n" "$1" >&2
    exit 99
  fi
}
require_artifact() {
  local a; a="$(artifact)"
  if [ ! -s "$a" ]; then
    printf "fixture failed: backup artifact missing at %s\n" "$a" >&2
    exit 99
  fi
}'

# ---------------------------------------------------------------------------
# metadata & contract
# ---------------------------------------------------------------------------
out="$(bash -c "$PRE; printf '%s|%s|%s' \"\$MODULE_NAME\" \"\${#MODULE_DEPENDS[@]}\" \"\$(declare -F module::remove >/dev/null && echo yes || echo no)\"" 2>&1)"
assert_eq "ssh: name, no deps, no remove hook" "$out" "ssh|0|no"

for h in check install verify update backup restore; do
  out="$(bash -c "$PRE; declare -F module::$h >/dev/null && echo yes || echo no" 2>&1)"
  assert_eq "ssh: defines module::$h" "$out" "yes"
done

# ---------------------------------------------------------------------------
# check — the state table (RFC §4.15). No network, no mutation.
# ---------------------------------------------------------------------------
out="$(bash -c "$PRE; run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "check row 2: no key, no passphrase -> passes" "$out" "pass"

out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "check row 3: passphrase, no key -> fails (install generates)" "$out" "fail"

out="$(bash -c "$PRE; mkdir -p \"\$HOME/.ssh\"; mkkey \"\$HOME/.ssh/id_ed25519\" '' ext
setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "check row 9: external key at default path + passphrase -> passes (no overwrite)" "$out" "pass"

out="$(bash -c "$PRE; mkdir -p \"\$HOME/.ssh\"; mkkey \"\$HOME/.ssh/id_other\" '' ext
run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "check row 7: external key only -> passes (Atlas owns nothing)" "$out" "pass"

out="$(bash -c "$PRE; export ATLAS_SSH_IMPORT_KEY=\"\$HOME/.ssh/id_work\"
mkdir -p \"\$HOME/.ssh\"; mkkey \"\$HOME/.ssh/id_work\" '' w
run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "check row 8: pending import -> fails (install imports)" "$out" "fail"

out="$(bash -c "$PRE; run_hook check >/dev/null 2>&1; ls \"\$HOME/.ssh\" 2>/dev/null | wc -l" 2>&1 | tail -1)"
assert_eq "check mutates nothing" "$out" "0"

# ---------------------------------------------------------------------------
# install — generation is opt-in (Decision 2)
# ---------------------------------------------------------------------------
out="$(bash -c "$PRE; run_hook install >/dev/null 2>&1; echo \"rc=\$?\"; [ -e \"\$HOME/.ssh/id_ed25519\" ] && echo generated || echo none" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "install without a passphrase: exit 0, generates nothing" "$out" "rc=0 none "

out="$(bash -c "$PRE; run_hook install 2>&1 | grep -ci 'passphrase\|generate' || true" 2>&1 | tail -1)"
assert_contains "install without a passphrase warns about it" "$([ "${out:-0}" -gt 0 ] && echo warned || echo silent)" "warned"

# generated key must ACTUALLY require its passphrase (RFC §4.5: -N-less keygen is silently unencrypted)
out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE 'corr3ct h0rse'
run_hook install >/dev/null 2>&1 || echo INSTALL_FAILED
k=\"\$HOME/.ssh/id_ed25519\"
[ -f \"\$k\" ] || { echo NOKEY; exit 0; }
ssh-keygen -y -f \"\$k\" -P '' >/dev/null 2>&1 && echo UNENCRYPTED || echo encrypted
ssh-keygen -y -f \"\$k\" -P 'corr3ct h0rse' >/dev/null 2>&1 && echo passphrase-works || echo passphrase-wrong
stat -c '%a' \"\$k\"" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "install generates an ENCRYPTED ed25519 key, mode 600" "$out" "encrypted passphrase-works 600 "

out="$(bash -c "$PRE; export ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE=1
run_hook install >/dev/null 2>&1
k=\"\$HOME/.ssh/id_ed25519\"
ssh-keygen -y -f \"\$k\" -P '' >/dev/null 2>&1 && echo unencrypted || echo encrypted" 2>&1 | tail -1)"
assert_eq "ALLOW_EMPTY_PASSPHRASE=1 generates an unencrypted key" "$out" "unencrypted"

out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; export ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE=1
run_hook install >/dev/null 2>&1; echo \"rc=\$?\"" 2>&1 | tail -1)"
assert_eq "passphrase AND allow-empty together are refused, not resolved" "$out" "rc=1"

# ~/.ssh created 700 when absent
out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1; stat -c '%a' \"\$HOME/.ssh\"" 2>&1 | tail -1)"
assert_eq "install creates ~/.ssh with mode 700" "$out" "700"

# manifest recorded, mode 600
out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
m=\$(manifest); [ -f \"\$m\" ] || { echo nomanifest; exit 0; }
printf '%s %s\n' \"\$(stat -c '%a' \"\$m\")\" \"\$(grep -c '^key generated .ssh/id_ed25519 ' \"\$m\")\"" 2>&1 | tail -1)"
assert_eq "install records the generated key in a mode-600 manifest" "$out" "600 1"

# ---------------------------------------------------------------------------
# Atlas never touches a key it does not own
# ---------------------------------------------------------------------------
out="$(bash -c "$PRE; mkdir -p \"\$HOME/.ssh\"; mkkey \"\$HOME/.ssh/id_ed25519\" '' ext
before=\$(sha256sum \"\$HOME/.ssh/id_ed25519\")
setpass ATLAS_SSH_KEY_PASSPHRASE pw
run_hook install >/dev/null 2>&1
after=\$(sha256sum \"\$HOME/.ssh/id_ed25519\")
[ \"\$before\" = \"\$after\" ] && echo identical || echo MODIFIED
m=\$(manifest); [ -s \"\$m\" ] && grep -q '^key' \"\$m\" && echo CLAIMED || echo unclaimed" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "external key at the default path: byte-identical, never claimed" "$out" "identical unclaimed "

# ---------------------------------------------------------------------------
# import (§4.6)
# ---------------------------------------------------------------------------
out="$(bash -c "$PRE; mkdir -p \"\$HOME/.ssh\"; mkkey \"\$HOME/.ssh/id_work\" '' w
chmod 600 \"\$HOME/.ssh/id_work\"
before=\$(sha256sum \"\$HOME/.ssh/id_work\" | cut -d' ' -f1)
export ATLAS_SSH_IMPORT_KEY=\"\$HOME/.ssh/id_work\"
run_hook install >/dev/null 2>&1; echo \"rc=\$?\"
after=\$(sha256sum \"\$HOME/.ssh/id_work\" | cut -d' ' -f1)
[ \"\$before\" = \"\$after\" ] && echo unchanged || echo MODIFIED
grep -c '^key imported .ssh/id_work ' \"\$(manifest)\"" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "import records the key and does not modify it" "$out" "rc=0 unchanged 1 "

out="$(bash -c "$PRE; mkdir -p \"\$HOME/.ssh\"; mkkey \"\$HOME/.ssh/id_work\" '' w
export ATLAS_SSH_IMPORT_KEY=\"\$HOME/.ssh/id_work\"
run_hook install >/dev/null 2>&1; run_hook install >/dev/null 2>&1; echo \"rc=\$?\"
grep -c '^key imported' \"\$(manifest)\"" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "import is idempotent (no duplicate record)" "$out" "rc=0 1 "

out="$(bash -c "$PRE; mkdir -p \"\$HOME/.ssh\"; ln -s /etc/hostname \"\$HOME/.ssh/id_link\"
touch \"\$HOME/.ssh/id_link.pub\"
export ATLAS_SSH_IMPORT_KEY=\"\$HOME/.ssh/id_link\"
run_hook install >/dev/null 2>&1; echo \"rc=\$?\"" 2>&1 | tail -1)"
assert_eq "import refuses a symlinked path" "$out" "rc=1"

out="$(bash -c "$PRE; export ATLAS_SSH_IMPORT_KEY=/etc/hostname
run_hook install >/dev/null 2>&1; echo \"rc=\$?\"" 2>&1 | tail -1)"
assert_eq "import refuses a path outside \$HOME" "$out" "rc=1"

# ---------------------------------------------------------------------------
# divergence (§4.14) — the swapped-private-half attack
# ---------------------------------------------------------------------------
DIVERGE="$PRE"'
setpass ATLAS_SSH_KEY_PASSPHRASE pw
run_hook install >/dev/null 2>&1
mkkey "$HOME/other" "" other
cp "$HOME/other" "$HOME/.ssh/id_ed25519"      # swap the PRIVATE half; .pub untouched
swapped=$(sha256sum "$HOME/.ssh/id_ed25519" | cut -d" " -f1)'

out="$(bash -c "$DIVERGE; run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "divergent (private half swapped): check FAILS" "$out" "fail"

out="$(bash -c "$DIVERGE; run_hook install >/dev/null 2>&1; echo \"rc=\$?\"
now=\$(sha256sum \"\$HOME/.ssh/id_ed25519\" | cut -d' ' -f1)
[ \"\$now\" = \"\$swapped\" ] && echo untouched || echo MODIFIED" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "divergent: install fails and does not touch the key" "$out" "rc=1 untouched "

out="$(bash -c "$DIVERGE; run_hook verify >/dev/null 2>&1; echo \"rc=\$?\"" 2>&1 | tail -1)"
assert_eq "divergent: verify FAILS" "$out" "rc=1"

out="$(bash -c "$DIVERGE; setpass ATLAS_BACKUP_PASSPHRASE bp
run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"; [ -e \"\$(artifact)\" ] && echo ARTIFACT || echo none" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "divergent: backup refuses, writes no artifact" "$out" "rc=1 none "

out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
mv \"\$HOME/.ssh/id_ed25519\" \"\$HOME/moved\"; ln -s \"\$HOME/moved\" \"\$HOME/.ssh/id_ed25519\"
run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "divergent: an owned path that became a symlink" "$out" "fail"

out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
rm -f \"\$HOME/.ssh/id_ed25519\"
run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "divergent: owned key deleted from disk" "$out" "fail"

# manifest is a trust boundary (§4.4)
out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
printf 'garbage record here\n' >> \"\$(manifest)\"
run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "manifest with an unknown record type fails closed" "$out" "fail"

out="$(bash -c "$PRE; mkdir -p \"\$ATLAS_CONFIG_HOME/ssh\"
printf 'no header here\n' > \"\$(manifest)\"; chmod 600 \"\$(manifest)\"
run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "manifest with a missing version header fails closed" "$out" "fail"

out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
sed -i 's/\$/\r/' \"\$(manifest)\"                       # rewrite with CRLF
run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "manifest with CRLF line endings still parses (\r stripped)" "$out" "pass"

# ---------------------------------------------------------------------------
# verify — reports, never repairs (§4.9)
# ---------------------------------------------------------------------------
out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
chmod 755 \"\$HOME/.ssh\"
run_hook verify >/dev/null 2>&1; echo \"rc=\$?\"; stat -c '%a' \"\$HOME/.ssh\"" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "verify fails on a 755 ~/.ssh and does NOT chmod it" "$out" "rc=1 755 "

out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
chmod 644 \"\$HOME/.ssh/id_ed25519\"
run_hook verify >/dev/null 2>&1; echo \"rc=\$?\"; stat -c '%a' \"\$HOME/.ssh/id_ed25519\"" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "verify fails on a 644 private key and does NOT chmod it" "$out" "rc=1 644 "

out="$(bash -c "$PRE; run_hook verify >/dev/null 2>&1; echo \"rc=\$?\"" 2>&1 | tail -1)"
assert_eq "verify passes (with a warning) when Atlas owns no key" "$out" "rc=0"

# ---------------------------------------------------------------------------
# GitHub registration (§4.8)
# ---------------------------------------------------------------------------
out="$(bash -c "$PRE; export GH_PRESENT=1 GH_AUTHED=1
setpass ATLAS_SSH_KEY_PASSPHRASE pw
run_hook install >/dev/null 2>&1
grep -c 'ssh-key add' \"\$GH_ARGV_LOG\"
head -c 11 \"\$GH_STDIN_LOG\"
echo
grep -c '^github SHA256:' \"\$(manifest)\"" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "gh authed: key uploaded on stdin and recorded in the manifest" "$out" "1 ssh-ed25519 1 "

out="$(bash -c "$PRE; export GH_PRESENT=1 GH_AUTHED=0
setpass ATLAS_SSH_KEY_PASSPHRASE pw
run_hook install >/dev/null 2>&1; echo \"rc=\$?\"
grep -c 'ssh-key add' \"\$GH_ARGV_LOG\" || true" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "gh logged out: install still succeeds, uploads nothing" "$out" "rc=0 0 "

out="$(bash -c "$PRE; export GH_PRESENT=1 GH_AUTHED=1 GH_SCOPE_DENIED=1
setpass ATLAS_SSH_KEY_PASSPHRASE pw
run_hook install >/dev/null 2>&1; echo \"rc=\$?\"" 2>&1 | tail -1)"
assert_eq "gh lacks admin:public_key: warning, not an install failure" "$out" "rc=0"

# row 6: key already on GitHub, not in the manifest -> record it, do not re-add
out="$(bash -c "$PRE; export GH_PRESENT=1 GH_AUTHED=1
setpass ATLAS_SSH_KEY_PASSPHRASE pw
run_hook install >/dev/null 2>&1                       # uploads + records
sed -i '/^github /d' \"\$(manifest)\"                   # forget only the record
: > \"\$GH_ARGV_LOG\"
run_hook install >/dev/null 2>&1                       # must find it, not re-add
grep -c 'ssh-key add' \"\$GH_ARGV_LOG\" || true
grep -c '^github SHA256:' \"\$(manifest)\"
run_hook check && echo pass || echo fail" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "row 6: key already on GitHub is recorded, not re-uploaded; check then passes" "$out" "0 1 pass "

out="$(bash -c "$PRE; export GH_PRESENT=1 GH_AUTHED=1
setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
grep -c 'auth token' \"\$GH_ARGV_LOG\"; grep -c 'gho_MOCKTOKEN' \"\$GH_ARGV_LOG\" || true" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "gh auth token used as a predicate; its output never captured" "$out" "1 0 "

# ---------------------------------------------------------------------------
# backup (§4.11)
# ---------------------------------------------------------------------------
OWNED="$PRE"'
setpass ATLAS_SSH_KEY_PASSPHRASE keypw
require_hook install >/dev/null 2>&1'

out="$(bash -c "$PRE; run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"; [ -e \"\$(artifact)\" ] && echo ARTIFACT || echo none" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "backup with no owned state: exit 0, no artifact" "$out" "rc=0 none "

out="$(bash -c "$OWNED; run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"; [ -e \"\$(artifact)\" ] && echo ARTIFACT || echo none" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "backup with owned state but no passphrase: exit 1, no artifact" "$out" "rc=1 none "

out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE 'b@ckup pass'
run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"
a=\$(artifact); [ -f \"\$a\" ] && stat -c '%a' \"\$a\" || echo noartifact
stat -c '%a' \"\$(dirname \"\$a\")\"" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "backup writes a mode-600 artifact in a mode-700 dir" "$out" "rc=0 600 700 "

# The restricted Fedora test environment exposed GnuPG 2.4.9 emitting valid
# ciphertext, then exiting 2 because its agent could not bind a socket. Force the
# behavior portably: status is advisory only after complete read-back validation.
out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
REAL_GPG=\$(type -P gpg)
gpg() {
  local arg candidate encrypt=0 rc
  for arg in \"\$@\"; do [ \"\$arg\" = --symmetric ] && encrypt=1; done
  \"\$REAL_GPG\" \"\$@\"; rc=\$?
  candidate=\$(backup_candidates | head -1)
  if [ \"\$encrypt\" -eq 1 ] && [ -n \"\$candidate\" ] && [ -s \"\$candidate\" ]; then
    printf '2\n' > \"\$HOME/encrypt.rc\"
    return 2
  fi
  return \"\$rc\"
}
run_hook backup >\"\$HOME/backup.log\" 2>&1; rc=\$?
grep -q 'gpg exited 2' \"\$HOME/backup.log\" && warning=warned || warning=silent
if \"\$REAL_GPG\" --batch -q --pinentry-mode loopback --passphrase-fd 3 \
     -d \"\$(artifact)\" 3< <(printf 'bp\n') 2>/dev/null | tar -tf - >/dev/null 2>&1; then
  valid=readable
else
  valid=unreadable
fi
printf 'forced=%s rc=%s %s %s\n' \"\$(cat \"\$HOME/encrypt.rc\" 2>/dev/null || echo missing)\" \"\$rc\" \"\$valid\" \"\$warning\"" 2>&1 | tail -1)"
assert_eq "backup accepts gpg rc=2 only after validation and warns" "$out" "forced=2 rc=0 readable warned"

# Concurrent backups must never share a candidate pathname. Each run validates
# and promotes its own inode; last-writer-wins is safe because both artifacts
# passed the complete contract.
out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
REAL_GPG=\$(type -P gpg); : > \"\$HOME/candidates.log\"
gpg() {
  local arg encrypt=0 out='' previous=''
  for arg in \"\$@\"; do
    [ \"\$previous\" = -o ] && out=\"\$arg\"
    [ \"\$arg\" = --symmetric ] && encrypt=1
    previous=\"\$arg\"
  done
  [ \"\$encrypt\" -eq 1 ] && printf '%s\n' \"\$out\" >> \"\$HOME/candidates.log\"
  \"\$REAL_GPG\" \"\$@\"
}
run_hook backup >/dev/null 2>&1 & p1=\$!
run_hook backup >/dev/null 2>&1 & p2=\$!
wait \"\$p1\"; rc1=\$?; wait \"\$p2\"; rc2=\$?
names=\$(sort -u \"\$HOME/candidates.log\" | wc -l | tr -d ' ')
if \"\$REAL_GPG\" --batch -q --pinentry-mode loopback --passphrase-fd 3 \
     -d \"\$(artifact)\" 3< <(printf 'bp\n') 2>/dev/null | tar -tf - >/dev/null 2>&1; then
  valid=readable
else
  valid=unreadable
fi
printf 'rc=%s/%s names=%s %s remaining=%s\n' \
  \"\$rc1\" \"\$rc2\" \"\$names\" \"\$valid\" \"\$(candidate_count)\"" 2>&1 | tail -1)"
assert_eq "concurrent backups validate distinct candidates" "$out" "rc=0/0 names=2 readable remaining=0"

# A complete-looking candidate is insufficient if tar reported a read failure.
# The wrapper writes the entire archive and then reports failure, proving Atlas
# checks tar's PIPESTATUS independently of gpg and the candidate's size.
out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
REAL_TAR=\$(type -P tar)
tar() {
  local arg create=0 rc
  for arg in \"\$@\"; do [ \"\$arg\" = -cf ] && create=1; done
  \"\$REAL_TAR\" \"\$@\"; rc=\$?
  [ \"\$create\" -eq 1 ] && return 2
  return \"\$rc\"
}
run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"
[ -e \"\$(artifact)\" ] && echo ARTIFACT || echo none
[ \"\$(candidate_count)\" -eq 0 ] && echo no-tmp || echo TMP-LEFT" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "backup rejects a candidate when tar fails" "$out" "rc=1 none no-tmp "

out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
require_hook backup >/dev/null 2>&1; require_artifact
gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d \"\$(artifact)\" 3< <(printf 'bp\n') 2>/dev/null \
  | tar -t | grep -vE '/\$' | sort | tr '\n' ' '" 2>&1 | tail -1)"
assert_eq "artifact contains exactly the owned files" "$out" "./config/ssh/known_hosts ./config/ssh/manifest ./home/.ssh/id_ed25519 ./home/.ssh/id_ed25519.pub "

out="$(bash -c "$PRE; mkdir -p \"\$HOME/.ssh\"; mkkey \"\$HOME/.ssh/id_other\" '' ext
setpass ATLAS_SSH_KEY_PASSPHRASE keypw; require_hook install >/dev/null 2>&1
setpass ATLAS_BACKUP_PASSPHRASE bp; require_hook backup >/dev/null 2>&1; require_artifact
gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d \"\$(artifact)\" 3< <(printf 'bp\n') 2>/dev/null \
  | tar -t | grep -c id_other || true" 2>&1 | tail -1)"
assert_eq "backup excludes external keys entirely" "$out" "0"

# the artifact must NOT decrypt with an empty passphrase (§4.11, closes B7 at runtime)
out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
require_hook backup >/dev/null 2>&1; require_artifact
gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d \"\$(artifact)\" 3< /dev/null >/dev/null 2>&1 \
  && echo DECRYPTS_EMPTY || echo refuses-empty" 2>&1 | tail -1)"
assert_eq "artifact does not decrypt with an empty passphrase" "$out" "refuses-empty"

# determinism: same tar, different ciphertext
out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
require_hook backup >/dev/null 2>&1; require_artifact; cp \"\$(artifact)\" \"\$HOME/a1\"
require_hook backup >/dev/null 2>&1; require_artifact; cp \"\$(artifact)\" \"\$HOME/a2\"
cmp -s \"\$HOME/a1\" \"\$HOME/a2\" && echo same-ciphertext || echo ciphertext-differs
for f in a1 a2; do gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d \"\$HOME/\$f\" 3< <(printf 'bp\n') 2>/dev/null > \"\$HOME/\$f.tar\"; done
cmp -s \"\$HOME/a1.tar\" \"\$HOME/a2.tar\" && echo same-tar || echo TAR-DIFFERS" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "backup: deterministic tar, non-deterministic ciphertext" "$out" "ciphertext-differs same-tar "

# a failed re-backup must not destroy the previous good artifact (§4.10 item 3)
out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
require_hook backup >/dev/null 2>&1; require_artifact
good=\$(sha256sum \"\$(artifact)\" | cut -d' ' -f1)
rm -f \"\$HOME/.ssh/id_ed25519\"                      # now divergent -> backup must refuse
run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"
now=\$(sha256sum \"\$(artifact)\" | cut -d' ' -f1)
[ \"\$good\" = \"\$now\" ] && echo previous-intact || echo PREVIOUS-DESTROYED
[ \"\$(candidate_count)\" -eq 0 ] && echo no-tmp || echo TMP-LEFT" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "a failed backup leaves the previous artifact byte-identical" "$out" "rc=1 previous-intact no-tmp "

# An interrupted run may leave a valid unique candidate. A later gpg failure
# that writes nothing must ignore those stale bytes and remove only its own file.
out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
require_hook backup >/dev/null 2>&1; require_artifact
a=\$(artifact); before=\$(sha256sum \"\$a\" | cut -d' ' -f1)
stale=\"\$a.tmp.stale\"; cp \"\$a\" \"\$stale\"
stale_before=\$(sha256sum \"\$stale\" | cut -d' ' -f1)
REAL_GPG=\$(type -P gpg)
gpg() {
  local arg encrypt=0
  for arg in \"\$@\"; do [ \"\$arg\" = --symmetric ] && encrypt=1; done
  if [ \"\$encrypt\" -eq 1 ]; then cat >/dev/null; return 2; fi
  \"\$REAL_GPG\" \"\$@\"
}
run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"
now=\$(sha256sum \"\$a\" | cut -d' ' -f1)
[ \"\$before\" = \"\$now\" ] && echo previous-intact || echo PREVIOUS-DESTROYED
stale_now=\$(sha256sum \"\$stale\" | cut -d' ' -f1)
[ \"\$stale_before\" = \"\$stale_now\" ] && echo stale-ignored || echo STALE-MODIFIED
[ \"\$(candidate_count)\" -eq 1 ] && echo own-candidate-clean || echo CANDIDATE-LEAK" 2>&1 | tail -4 | tr '\n' ' ')"
assert_eq "backup ignores stale candidates and cleans only its own" "$out" "rc=1 previous-intact stale-ignored own-candidate-clean "

# two owned keys, one divergent -> refuse both
out="$(bash -c "$PRE; mkdir -p \"\$HOME/.ssh\"; mkkey \"\$HOME/.ssh/id_work\" '' w
export ATLAS_SSH_IMPORT_KEY=\"\$HOME/.ssh/id_work\"
setpass ATLAS_SSH_KEY_PASSPHRASE keypw; run_hook install >/dev/null 2>&1
unset ATLAS_SSH_IMPORT_KEY
rm -f \"\$HOME/.ssh/id_work\"                          # one of two owned keys is now gone
setpass ATLAS_BACKUP_PASSPHRASE bp
run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"; [ -e \"\$(artifact)\" ] && echo ARTIFACT || echo none" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "two owned keys, one divergent: backup refuses both" "$out" "rc=1 none "

# ---------------------------------------------------------------------------
# restore (§4.12)
# ---------------------------------------------------------------------------
BACKED="$OWNED"'
setpass ATLAS_BACKUP_PASSPHRASE bp
require_hook backup >/dev/null 2>&1
require_artifact
keyhash=$(sha256sum "$HOME/.ssh/id_ed25519" | cut -d" " -f1)'

out="$(bash -c "$BACKED; rm -rf \"\$HOME/.ssh\" \"\$ATLAS_CONFIG_HOME/ssh\"
run_hook restore >/dev/null 2>&1; echo \"rc=\$?\"
[ -f \"\$HOME/.ssh/id_ed25519\" ] && echo restored || echo MISSING
stat -c '%a' \"\$HOME/.ssh\" \"\$HOME/.ssh/id_ed25519\" \"\$HOME/.ssh/id_ed25519.pub\" | tr '\n' ' '
echo
[ \"\$(sha256sum \"\$HOME/.ssh/id_ed25519\" | cut -d' ' -f1)\" = \"\$keyhash\" ] && echo bytes-match || echo BYTES-DIFFER" 2>&1 | tail -4 | tr '\n' ' ')"
assert_eq "restore into an empty HOME recreates files and modes" "$out" "rc=0 restored 700 600 644  bytes-match "

out="$(bash -c "$BACKED; rm -rf \"\$HOME/.ssh\" \"\$ATLAS_CONFIG_HOME/ssh\"
run_hook restore >/dev/null 2>&1
run_hook restore >/dev/null 2>&1; echo \"rc=\$?\"" 2>&1 | tail -1)"
assert_eq "restore is idempotent (second run skips everything)" "$out" "rc=0"

out="$(bash -c "$BACKED; printf 'MINE\n' > \"\$HOME/.ssh/id_ed25519\"
run_hook restore >/dev/null 2>&1; echo \"rc=\$?\"
cat \"\$HOME/.ssh/id_ed25519\"" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "restore over a differing target: exit 1, target unchanged" "$out" "rc=1 MINE "

out="$(bash -c "$BACKED; rm -rf \"\$HOME/.ssh\"; mkdir -p \"\$HOME/.ssh\"; chmod 700 \"\$HOME/.ssh\"
printf 'MINE\n' > \"\$HOME/.ssh/id_ed25519\"          # conflict
run_hook restore >/dev/null 2>&1
[ -e \"\$HOME/.ssh/id_ed25519.pub\" ] && echo WROTE-OTHERS || echo wrote-nothing" 2>&1 | tail -1)"
assert_eq "restore conflict: nothing else is written either" "$out" "wrote-nothing"

out="$(bash -c "$BACKED; rm -f \"\$HOME/.ssh/id_ed25519\"; ln -s /etc/hostname \"\$HOME/.ssh/id_ed25519\"
run_hook restore >/dev/null 2>&1; echo \"rc=\$?\"
[ -L \"\$HOME/.ssh/id_ed25519\" ] && echo still-symlink || echo REPLACED
[ \"\$(cat /etc/hostname)\" = \"\$(cat \"\$HOME/.ssh/id_ed25519\")\" ] && echo target-intact || echo TARGET-WRITTEN" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "restore never writes through a symlinked target" "$out" "rc=1 still-symlink target-intact "

out="$(bash -c "$PRE; run_hook restore >/dev/null 2>&1; echo \"rc=\$?\"" 2>&1 | tail -1)"
assert_eq "restore with no artifact: exit 1" "$out" "rc=1"

# a hostile archive must be rejected BEFORE extraction
out="$(bash -c "$BACKED; rm -rf \"\$HOME/.ssh\"
evil=\$(mktemp -d); mkdir -p \"\$evil/home/.ssh\"
ln -s /etc/passwd \"\$evil/home/.ssh/id_ed25519\"
tar -cf - -C \"\$evil\" . | gpg --batch --yes -q --pinentry-mode loopback --passphrase-fd 3 \
    --symmetric --cipher-algo AES256 -o \"\$(artifact)\" 3< <(printf 'bp\n')
run_hook restore >/dev/null 2>&1; echo \"rc=\$?\"
[ -e \"\$HOME/.ssh/id_ed25519\" ] && echo EXTRACTED || echo refused" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "restore rejects an archive containing a symlink member" "$out" "rc=1 refused "

out="$(bash -c "$BACKED; rm -rf \"\$HOME/.ssh\"
evil=\$(mktemp -d); mkdir -p \"\$evil/home\"; printf 'pwn\n' > \"\$evil/home/x\"
tar -cf - -C \"\$evil\" --transform 's|home/x|../../../../tmp/atlas-pwn|' home/x \
  | gpg --batch --yes -q --pinentry-mode loopback --passphrase-fd 3 \
        --symmetric --cipher-algo AES256 -o \"\$(artifact)\" 3< <(printf 'bp\n')
run_hook restore >/dev/null 2>&1; echo \"rc=\$?\"
[ -e /tmp/atlas-pwn ] && echo ESCAPED || echo contained" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "restore rejects an archive member escaping via ../" "$out" "rc=1 contained "

# ---------------------------------------------------------------------------
# update, and the pinned known_hosts (§4.7)
# ---------------------------------------------------------------------------
out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
kh=\"\$ATLAS_CONFIG_HOME/ssh/known_hosts\"
grep -c '^github.com ssh-ed25519 ' \"\$kh\"
printf 'corrupted\n' > \"\$kh\"
run_hook update >/dev/null 2>&1; echo \"rc=\$?\"
grep -c '^github.com ssh-ed25519 ' \"\$kh\"" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "install pins known_hosts; update refreshes it" "$out" "1 rc=0 1 "

out="$(bash -c "$PRE; mkdir -p \"\$HOME/.ssh\"; printf 'user line\n' > \"\$HOME/.ssh/known_hosts\"
setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
cat \"\$HOME/.ssh/known_hosts\"" 2>&1 | tail -1)"
assert_eq "Atlas never writes to the user's ~/.ssh/known_hosts" "$out" "user line"

# the pinned key must match GitHub's published fingerprint (guards a bad rotation)
out="$(bash -c "$PRE; ssh-keygen -lf \"\$ATLAS_ROOT/modules/core/ssh/config/known_hosts\" | awk '{print \$2}'" 2>&1 | tail -1)"
assert_eq "pinned github.com key matches GitHub's published SHA256_ED25519" "$out" "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"

# ---------------------------------------------------------------------------
# trap discipline (§5.1) — a hook that makes a temp dir and succeeds must return 0
# ---------------------------------------------------------------------------
out="$(bash -c "$PRE
( set -euo pipefail
  setpass ATLAS_SSH_KEY_PASSPHRASE pw
  for h in check install verify; do
    if ! \"module::\$h\"; then :; fi
  done ) >/dev/null 2>&1
echo \"subshell rc=\$?\"" 2>&1 | tail -1)"
assert_eq "hooks in one runner subshell: no trap flips a healthy run to rc=1" "$out" "subshell rc=0"

# ---------------------------------------------------------------------------
# secret discipline — neither passphrase may appear in a bash -x trace
# ---------------------------------------------------------------------------
out="$(bash -c "$PRE
setpass ATLAS_SSH_KEY_PASSPHRASE 'k3y-p@ssphrase-canary'
setpass ATLAS_BACKUP_PASSPHRASE  'b@ckup-canary-9f2c'
{ set -x
  run_hook install
  run_hook backup
  set +x
} >/dev/null 2>\"\$HOME/trace\"
leaks=0
grep -q 'k3y-p@ssphrase-canary' \"\$HOME/trace\" && leaks=\$((leaks+1))
grep -q 'b@ckup-canary-9f2c'    \"\$HOME/trace\" && leaks=\$((leaks+1))
echo \"leaks=\$leaks\"" 2>&1 | tail -1)"
assert_eq "no passphrase appears in a bash -x trace of install+backup" "$out" "leaks=0"

out="$(bash -c "$PRE
setpass ATLAS_SSH_KEY_PASSPHRASE 'k3y-canary-7a1b'
setpass ATLAS_BACKUP_PASSPHRASE  'b@ck-canary-4d8e'
run_hook install >\"\$HOME/o\" 2>&1; run_hook backup >>\"\$HOME/o\" 2>&1
grep -qE 'k3y-canary-7a1b|b@ck-canary-4d8e' \"\$HOME/o\" && echo LEAKED || echo clean
grep -rqE 'k3y-canary-7a1b|b@ck-canary-4d8e' \"\$ATLAS_STATE_DIR\" 2>/dev/null && echo LEAKED-STATE || echo clean-state" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "no passphrase in module output or in Atlas's state dir" "$out" "clean clean-state "

# ===========================================================================
# Guards that survived mutation testing until these tests existed.
#
# Each test below was written because deleting the guard it covers left the
# suite green. A guard no test can kill is indistinguishable from dead code.
# ===========================================================================

# --- the public half is a target too --------------------------------------
# Swapping the .pub is the MORE dangerous attack: `privhash` never notices, and
# `_ssh_register` would upload the attacker's public key to the user's GitHub
# account. Only the pubfp check sees it.
out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw
run_hook install >/dev/null 2>&1
mkkey \"\$HOME/other\" '' other
cp \"\$HOME/other.pub\" \"\$HOME/.ssh/id_ed25519.pub\"   # swap the PUBLIC half only
run_hook check && echo pass || echo fail
run_hook verify >/dev/null 2>&1; echo \"verify=\$?\"" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "divergent: swapped PUBLIC half is detected" "$out" "fail verify=1 "

out="$(bash -c "$PRE; export GH_PRESENT=1 GH_AUTHED=1
setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
mkkey \"\$HOME/other\" '' attacker
cp \"\$HOME/other.pub\" \"\$HOME/.ssh/id_ed25519.pub\"
sed -i '/^github /d' \"\$(manifest)\"; : > \"\$GH_ARGV_LOG\"
run_hook install >/dev/null 2>&1
grep -c 'ssh-key add' \"\$GH_ARGV_LOG\" || true" 2>&1 | tail -1)"
assert_eq "a swapped public half is never uploaded to GitHub" "$out" "0"

# --- restore must not write through a DANGLING symlink ---------------------
# A symlink to an existing file is caught by the byte-compare. A symlink to a
# NON-existent target passes `[ -e ]` and `cp` would create the target, writing
# a private key outside ~/.ssh. Only the `[ -L ]` check sees this.
# GNU cp refuses to write through a dangling symlink on its own. The [ -L ] guard
# is what makes the conflict surface in the SCAN — so that restore writes NOTHING,
# rather than failing halfway with other files already in place.
out="$(bash -c "$BACKED; rm -rf \"\$ATLAS_CONFIG_HOME/ssh\"   # must be rewritten by restore
rm -f \"\$HOME/.ssh/id_ed25519\"
ln -s \"\$HOME/pwned\" \"\$HOME/.ssh/id_ed25519\"     # dangling
run_hook restore >/dev/null 2>&1; echo \"rc=\$?\"
[ -e \"\$HOME/pwned\" ] && echo WROTE-THROUGH || echo contained
[ -e \"\$ATLAS_CONFIG_HOME/ssh/known_hosts\" ] && echo PARTIAL-RESTORE || echo nothing-written" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "restore aborts on a dangling symlink BEFORE writing anything" "$out" "rc=1 contained nothing-written "

# --- the archived manifest must match the archived bytes -------------------
out="$(bash -c "$BACKED; rm -rf \"\$HOME/.ssh\"
w=\$(mktemp -d)
gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d \"\$(artifact)\" 3< <(printf 'bp\n') 2>/dev/null | tar -x -C \"\$w\"
mkkey \"\$w/imposter\" '' imposter
cp \"\$w/imposter\" \"\$w/home/.ssh/id_ed25519\"      # tamper: different key, same manifest
tar -cf - -C \"\$w\" ./home ./config | gpg --batch --yes -q --pinentry-mode loopback \
   --passphrase-fd 3 --symmetric --cipher-algo AES256 -o \"\$(artifact)\" 3< <(printf 'bp\n')
run_hook restore >/dev/null 2>&1; echo \"rc=\$?\"
[ -e \"\$HOME/.ssh/id_ed25519\" ] && echo RESTORED || echo refused" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "restore refuses an artifact whose key does not match its manifest" "$out" "rc=1 refused "

# --- member-type validation, on an otherwise VALID archive -----------------
# The earlier symlink-member test also fails for a lesser reason (no manifest).
# This one is a complete, well-formed archive that merely hides a symlink.
out="$(bash -c "$BACKED; rm -rf \"\$HOME/.ssh\"
w=\$(mktemp -d)
gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d \"\$(artifact)\" 3< <(printf 'bp\n') 2>/dev/null | tar -x -C \"\$w\"
rm -f \"\$w/home/.ssh/id_ed25519\"
ln -s /etc/passwd \"\$w/home/.ssh/id_ed25519\"       # valid archive + one symlink member
tar -cf - -C \"\$w\" ./home ./config | gpg --batch --yes -q --pinentry-mode loopback \
   --passphrase-fd 3 --symmetric --cipher-algo AES256 -o \"\$(artifact)\" 3< <(printf 'bp\n')
run_hook restore >\"\$HOME/o\" 2>&1
grep -qi 'not plain files or directories' \"\$HOME/o\" && echo type-rejected || echo NOT-REJECTED
[ -e \"\$HOME/.ssh/id_ed25519\" ] && echo EXTRACTED || echo contained" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "restore rejects a symlink member in an otherwise valid archive" "$out" "type-rejected contained "

# --- manifest parser: the trailing header check and duplicate paths --------
out="$(bash -c "$PRE; mkdir -p \"\$ATLAS_CONFIG_HOME/ssh\"
printf '# just a comment\n# and another\n' > \"\$(manifest)\"; chmod 600 \"\$(manifest)\"
run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "manifest of comments only (no version header) fails closed" "$out" "fail"

out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
grep '^key ' \"\$(manifest)\" > \"\$HOME/dup\"
cat \"\$HOME/dup\" >> \"\$(manifest)\"                # duplicate the key record
run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "manifest with a duplicate path fails closed" "$out" "fail"

out="$(bash -c "$PRE; setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
printf 'github SHA256:nosuchkeyanywhere\n' >> \"\$(manifest)\"
run_hook check && echo pass || echo fail" 2>&1 | tail -1)"
assert_eq "manifest with an orphan github record fails closed" "$out" "fail"

# --- an ssh-keygen that IGNORES SSH_ASKPASS (RFC §6.1 assumption 2) --------
# `ssh-keygen` is invoked through `env`, so only a PATH shim can simulate this.
# If OpenSSH ever declines askpass, it silently emits an UNENCRYPTED key and
# exits 0. Atlas must refuse to keep it — the exit code proves nothing.
out="$(bash -c "$PRE
mkdir -p \"\$HOME/bin\"
cat > \"\$HOME/bin/ssh-keygen\" <<'SHIM'
#!/usr/bin/env bash
real=/usr/bin/ssh-keygen
for a in \"\$@\"; do case \"\$a\" in -y|-lf|-l) exec \"\$real\" \"\$@\" ;; esac; done
f=\"\"; p=\"\"
while [ \$# -gt 0 ]; do case \"\$1\" in -f) f=\"\$2\"; shift ;; esac; shift; done
exec \"\$real\" -t ed25519 -f \"\$f\" -N '' -q -C ignored-askpass </dev/null
SHIM
chmod 755 \"\$HOME/bin/ssh-keygen\"; PATH=\"\$HOME/bin:\$PATH\"
setpass ATLAS_SSH_KEY_PASSPHRASE pw
run_hook install >/dev/null 2>&1; echo \"rc=\$?\"
[ -e \"\$HOME/.ssh/id_ed25519\" ] && echo KEY-KEPT || echo key-deleted
[ -f \"\$(manifest)\" ] && grep -qc '^key ' \"\$(manifest)\" && echo RECORDED || echo not-recorded" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "an ssh-keygen that ignores SSH_ASKPASS: refuse, delete, do not record" "$out" "rc=1 key-deleted not-recorded "

# --- a PERMISSIVE gpg that accepts an empty passphrase --------------------
# Real gpg refuses one (probed). This asserts what Atlas does if a future gpg
# does not — the residual hole the discard-probe alone cannot close.
PERMISSIVE_GPG='
# A hypothetical gpg that accepts an EMPTY passphrase. Real gpg refuses one
# (probed: exit 2, no artifact), so this is the only way to exercise Atlas'"'"'s
# guard against a future gpg that does not. Flags taking a VALUE must consume it
# — `--pinentry-mode loopback` otherwise leaves "loopback" as the filename.
gpg() {
  local -; set +x
  local mode="" out=""; local -a rest=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --symmetric) mode=enc ;;
      -d) mode=dec ;;
      -o) out="$2"; shift ;;
      --passphrase-fd|--pinentry-mode|--cipher-algo) shift ;;
      -*) ;;
      *) rest+=("$1") ;;
    esac; shift
  done
  case "$mode" in
    enc) cat > "$out" ;;                       # accepts ANY passphrase, incl. none
    dec) cat "${rest[0]:-/dev/null}" ;;        # opens with ANY passphrase, incl. none
    *) return 1 ;;
  esac
}'

out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
$PERMISSIVE_GPG
run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"
[ -e \"\$(artifact)\" ] && echo KEPT || echo discarded
[ \"\$(candidate_count)\" -eq 0 ] && echo no-tmp || echo TMP-LEFT" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "a gpg that accepts an empty passphrase: artifact refused and discarded" "$out" "rc=1 discarded no-tmp "

# --- a gpg whose read-back fails: the previous artifact must survive -------
FAILING_READBACK='
gpg() {
  local -; set +x
  local mode="" out=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --symmetric) mode=enc ;; -d) mode=dec ;; -o) out="$2"; shift ;;
      --passphrase-fd|--pinentry-mode|--cipher-algo) shift ;;
    esac; shift
  done
  case "$mode" in
    enc) cat > "$out"; return 2 ;;              # nonempty candidate, nonzero encrypt status
    dec) return 2 ;;                            # encryption works; verification does not
  esac
}'

out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
require_hook backup >/dev/null 2>&1; require_artifact  # a real, good artifact
good=\$(sha256sum \"\$(artifact)\" | cut -d' ' -f1)
$FAILING_READBACK
run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"
now=\$(sha256sum \"\$(artifact)\" | cut -d' ' -f1)
[ \"\$good\" = \"\$now\" ] && echo previous-intact || echo PREVIOUS-DESTROYED
[ \"\$(candidate_count)\" -eq 0 ] && echo no-tmp || echo TMP-LEFT" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "read-back failure: previous artifact intact, tmp removed" "$out" "rc=1 previous-intact no-tmp "

# --- the discard-probe earns its place by naming the cause -----------------
out="$(bash -c "$OWNED; run_hook backup >\"\$HOME/o\" 2>&1
grep -qi 'ATLAS_BACKUP_PASSPHRASE' \"\$HOME/o\" && echo names-the-secret || echo generic-error" 2>&1 | tail -1)"
assert_eq "backup without a passphrase names the missing secret, not a pipeline error" "$out" "names-the-secret"

# --- staging must never outlive a hook -------------------------------------
# The restore staging dir holds PLAINTEXT private keys. Cleanup must happen the
# moment the hook returns, on EVERY path including failure — not merely when the
# module's subshell exits (the trap is only the backstop). The check runs INSIDE
# each sandbox, before its process exits, because $ATLAS_SSH_STAGING_DIR is
# per-sandbox (a fresh $HOME per test), so an outer-scope count cannot see it.
# `count()` reports how many staging dirs remain right after the hook returned.
_STAGE='count() { find "$ATLAS_SSH_STAGING_DIR" -maxdepth 1 -name '"'"'atlas-ssh.*'"'"' 2>/dev/null | wc -l; }'

out="$(bash -c "$BACKED; $_STAGE; echo remaining=\$(count)" 2>&1 | tail -1)"
assert_eq "install+backup leave no staging dir behind" "$out" "remaining=0"

out="$(bash -c "$BACKED; $_STAGE
rm -rf \"\$HOME/.ssh\" \"\$ATLAS_CONFIG_HOME/ssh\"
run_hook restore >/dev/null 2>&1
echo remaining=\$(count)" 2>&1 | tail -1)"
assert_eq "a successful restore leaves no staging dir behind" "$out" "remaining=0"

out="$(bash -c "$BACKED; $_STAGE
printf 'MINE\n' > \"\$HOME/.ssh/id_ed25519\"
run_hook restore >/dev/null 2>&1
echo remaining=\$(count)" 2>&1 | tail -1)"
assert_eq "a FAILED restore leaves no staging dir behind" "$out" "remaining=0"

out="$(bash -c "$BACKED
rm -rf \"\$HOME/.ssh\" \"\$ATLAS_CONFIG_HOME/ssh\"
run_hook restore >/dev/null 2>&1
grep -rlqs 'BEGIN OPENSSH PRIVATE KEY' \"\$ATLAS_SSH_STAGING_DIR\" 2>/dev/null && echo KEY-LEFT || echo clean" 2>&1 | tail -1)"
assert_eq "no decrypted private key is left in staging after restore" "$out" "clean"

# The one hook that runs three times in a single runner subshell must still
# return 0 — a trap that names a dead `local` would flip it to 1 (§5.1).
out="$(bash -c "$PRE
setpass ATLAS_SSH_KEY_PASSPHRASE pw; setpass ATLAS_BACKUP_PASSPHRASE bp
( set -euo pipefail
  for h in check install verify; do if ! \"module::\$h\"; then :; fi; done ) >/dev/null 2>&1
echo \"rc=\$?\"" 2>&1 | tail -1)"
assert_eq "check+install+verify in one subshell: cleanup does not flip rc to 1" "$out" "rc=0"

# ===========================================================================
# Regressions for findings from the implementation + security reviews.
# ===========================================================================

# --- F/impl-1: an import path with `..` escapes $HOME ------------------------
# It was accepted, install succeeded, check/verify passed — while backup was
# permanently broken. Now the import is refused up front.
out="$(bash -c "$PRE
mkdir -p \"\$HOME/.ssh\" \"\$HOME/outside\"
mkkey \"\$HOME/outside/id_key\" '' out
export ATLAS_SSH_IMPORT_KEY=\"\$HOME/../$(basename \"\$HOME\")/outside/id_key\"
run_hook install >/dev/null 2>&1; echo \"rc=\$?\"
[ -s \"\$(manifest)\" ] && grep -q '\\.\\.' \"\$(manifest)\" && echo ESCAPED-INTO-MANIFEST || echo clean-manifest" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "import of a \$HOME/../ path is refused, never recorded" "$out" "rc=1 clean-manifest "

out="$(bash -c "$PRE
run_hook install >/dev/null 2>&1     # baseline: define funcs
source \"\$MOD\"
_ssh_path_ownable \"\$HOME/../etc/passwd\" 2>/dev/null && echo ACCEPTED || echo refused" 2>&1 | tail -1)"
assert_eq "_ssh_path_ownable refuses a .. component" "$out" "refused"

# --- F/impl-2: glob metacharacter in a manifest path ------------------------
# `set -- $line` used to pathname-expand the field. The parser must now be
# CWD-independent, and an ownable path must not contain a glob char at all.
out="$(bash -c "$PRE
source \"\$MOD\"
_ssh_path_ownable \"\$HOME/.ssh/id_[work]\" 2>/dev/null && echo ACCEPTED || echo refused" 2>&1 | tail -1)"
assert_eq "_ssh_path_ownable refuses a glob metacharacter" "$out" "refused"

# The parser gives the SAME answer regardless of \$CWD, even with a decoy present.
out="$(bash -c "$PRE
setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
# hand-craft a manifest whose path is a glob, plus a decoy the glob could match
mkkey \"\$HOME/.ssh/id_decoy\" '' decoy
fp=\$(grep '^key ' \"\$(manifest)\" | cut -d' ' -f4)
h=\$(grep '^key ' \"\$(manifest)\" | cut -d' ' -f5)
printf '# atlas-ssh-manifest v1\nkey generated .ssh/id_* %s %s 600\n' \"\$fp\" \"\$h\" > \"\$(manifest)\"
chmod 600 \"\$(manifest)\"
a=\$(cd \"\$HOME\"      && run_hook check >/dev/null 2>&1; echo \$?)
b=\$(cd /             && run_hook check >/dev/null 2>&1; echo \$?)
[ \"\$a\" = \"\$b\" ] && echo cwd-independent || echo CWD-DEPENDENT:\$a/\$b" 2>&1 | tail -1)"
assert_eq "the manifest parser gives the same answer from any \$CWD" "$out" "cwd-independent"

# --- F/impl-3: a short key record in the ARCHIVED manifest -------------------
# Under the runner's set -u this used to crash the subshell with `$3: unbound`.
# It must now be a clean rejection, and nothing may be written.
out="$(bash -c "$BACKED; rm -rf \"\$HOME/.ssh\"
w=\$(mktemp -d)
gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d \"\$(artifact)\" 3< <(printf 'bp\n') 2>/dev/null | tar -x -C \"\$w\"
printf '# atlas-ssh-manifest v1\nkey generated\n' > \"\$w/config/ssh/manifest\"   # 2 fields
tar -cf - -C \"\$w\" ./home ./config | gpg --batch --yes -q --pinentry-mode loopback \
   --passphrase-fd 3 --symmetric --cipher-algo AES256 -o \"\$(artifact)\" 3< <(printf 'bp\n')
run_hook restore >\"\$HOME/o\" 2>&1; echo \"rc=\$?\"
grep -qi 'unbound variable' \"\$HOME/o\" && echo CRASHED || echo clean-rejection
[ -e \"\$HOME/.ssh/id_ed25519\" ] && echo WROTE || echo nothing-written" 2>&1 | tail -3 | tr '\n' ' ')"
assert_eq "restore rejects a short key record without crashing, writing nothing" "$out" "rc=1 clean-rejection nothing-written "

# --- F/security: an artifact whose manifest names a path outside .ssh --------
# `dst=$HOME/$rel`; a crafted (passphrase-protected) artifact could name
# ../ or an absolute rel. Even a plain `home/`-rooted member combined with a
# manifest `rel` of `.bashrc` would drop a file into $HOME. Refuse unsafe rel.
out="$(bash -c "$BACKED; rm -rf \"\$HOME/.ssh\"
w=\$(mktemp -d)
gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d \"\$(artifact)\" 3< <(printf 'bp\n') 2>/dev/null | tar -x -C \"\$w\"
# rename the archived key to a traversal path and point the manifest at it
fp=\$(grep '^key ' \"\$w/config/ssh/manifest\" | cut -d' ' -f4)
h=\$(grep '^key ' \"\$w/config/ssh/manifest\" | cut -d' ' -f5)
printf '# atlas-ssh-manifest v1\nkey generated ../evil %s %s 600\n' \"\$fp\" \"\$h\" > \"\$w/config/ssh/manifest\"
tar -cf - -C \"\$w\" ./home ./config | gpg --batch --yes -q --pinentry-mode loopback \
   --passphrase-fd 3 --symmetric --cipher-algo AES256 -o \"\$(artifact)\" 3< <(printf 'bp\n')
run_hook restore >/dev/null 2>&1; echo \"rc=\$?\"
[ -e \"\$HOME/../evil\" ] && { echo ESCAPED; rm -f \"\$HOME/../evil\"; } || echo contained" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "restore refuses a manifest rel that escapes with .." "$out" "rc=1 contained "

# --- F/rfc-compliance: no decrypted key lingers in staging on FAILURE --------
# The wrapper removes staging on every return; the trap is only the backstop.
# Run a FAILING restore and confirm the decrypted key is gone immediately after
# the hook returns (not merely after the process exits).
out="$(bash -c "$BACKED
printf 'MINE\n' > \"\$HOME/.ssh/id_ed25519\"          # forces a conflict AFTER decryption
run_hook restore >/dev/null 2>&1
# still inside the SAME shell — the trap has NOT fired yet
found=\$(find \"\$ATLAS_SSH_STAGING_DIR\" -maxdepth 3 -name 'archive.tar' 2>/dev/null | wc -l)
leaked=\$(grep -rlqs 'BEGIN OPENSSH PRIVATE KEY' \"\$ATLAS_SSH_STAGING_DIR\"/atlas-ssh.* 2>/dev/null && echo yes || echo no)
echo \"staging=\$found key-in-staging=\$leaked\"" 2>&1 | tail -1)"
assert_eq "a failed restore removes its decrypted staging immediately" "$out" "staging=0 key-in-staging=no"

# --- suggestion: the backup .tmp is never world-readable, even mid-write -----
out="$(bash -c "$OWNED; setpass ATLAS_BACKUP_PASSPHRASE bp
run_hook backup >/dev/null 2>&1
stat -c '%a' \"\$(artifact)\"" 2>&1 | tail -1)"
assert_eq "the finished artifact is mode 600" "$out" "600"

# --- suggestion: gh registration prints nothing to the hook's stdout ---------
out="$(bash -c "$PRE; export GH_PRESENT=1 GH_AUTHED=1
setpass ATLAS_SSH_KEY_PASSPHRASE pw
module::install >\"\$HOME/stdout\" 2>/dev/null || true
# the only thing a hook may print to stdout is the __SKIP__ token (never here)
grep -qi 'public key added' \"\$HOME/stdout\" && echo LEAKED-TO-STDOUT || echo clean-stdout" 2>&1 | tail -1)"
assert_eq "gh registration chatter does not reach the hook's stdout" "$out" "clean-stdout"

# ===========================================================================
# Coverage the RFC-compliance review found missing (the non-network branches).
# ===========================================================================

# --- verify reports an external key by fingerprint AND path (RFC §4.15) ------
out="$(bash -c "$PRE
setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1   # an owned key
mkkey \"\$HOME/.ssh/id_stranger\" '' stranger                            # plus an external one
fp=\$(ssh-keygen -lf \"\$HOME/.ssh/id_stranger.pub\" | awk '{print \$2}')
run_hook verify 2>&1 | grep 'external key' | grep -q \"\$fp\" && echo reports-fp || echo NO-FP" 2>&1 | tail -1)"
assert_eq "verify reports an external key by its fingerprint" "$out" "reports-fp"

out="$(bash -c "$PRE
mkkey \"\$HOME/.ssh/id_owned_check\" >/dev/null 2>&1 || true
setpass ATLAS_SSH_KEY_PASSPHRASE pw; run_hook install >/dev/null 2>&1
mkkey \"\$HOME/.ssh/id_stranger\" '' stranger
run_hook verify 2>&1 | grep 'external key' | grep -q 'id_stranger' && echo reports-path || echo NO-PATH" 2>&1 | tail -1)"
assert_eq "verify reports an external key by its path too" "$out" "reports-path"

# --- verify row-9 warning (passphrase set, default path holds an unowned key) -
out="$(bash -c "$PRE
mkdir -p \"\$HOME/.ssh\"; chmod 700 \"\$HOME/.ssh\"
mkkey \"\$HOME/.ssh/id_ed25519\" '' ext
setpass ATLAS_SSH_KEY_PASSPHRASE pw
run_hook install >/dev/null 2>&1
v=\$(run_hook verify 2>&1)
grep -qi 'does not own it' <<<\"\$v\" && echo warns || echo SILENT" 2>&1 | tail -1)"
assert_eq "verify warns when a passphrase is set but the default key is unowned (row 9)" "$out" "warns"

# --- ATLAS_SSH_NO_NETWORK skips the connectivity probe -----------------------
# With an unencrypted owned key, verify would otherwise try `ssh -T`. The flag
# must short-circuit that and say so.
out="$(bash -c "$PRE
export ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE=1; run_hook install >/dev/null 2>&1
ATLAS_SSH_NO_NETWORK=1 run_hook verify 2>&1 | grep -qi 'ATLAS_SSH_NO_NETWORK' && echo skipped || echo NOT-SKIPPED" 2>&1 | tail -1)"
assert_eq "verify honours ATLAS_SSH_NO_NETWORK and skips the network probe" "$out" "skipped"

# --- update fails cleanly when ssh is absent ---------------------------------
out="$(bash -c "$PRE
os::has_cmd() { case \"\$1\" in ssh|ssh-keygen) return 1 ;; *) command -v \"\$1\" >/dev/null 2>&1 ;; esac; }
run_hook update >/dev/null 2>&1; echo \"rc=\$?\"" 2>&1 | tail -1)"
assert_eq "update fails when ssh is not installed" "$out" "rc=1"

# --- staging on a real disk WARNS (the D2 gap) -------------------------------
# The sandbox already points ATLAS_SSH_STAGING_DIR at a disk-backed dir in WSL,
# but assert the filesystem-type warning fires when staging is not tmpfs.
out="$(bash -c "$PRE
export ATLAS_SSH_STAGING_DIR=\"\$HOME/disk-staging\"; mkdir -p \"\$ATLAS_SSH_STAGING_DIR\"
fstype=\$(stat -f -c '%T' \"\$ATLAS_SSH_STAGING_DIR\" 2>/dev/null)
case \"\$fstype\" in tmpfs|ramfs) echo SKIP-tmpfs-host; exit 0 ;; esac
setpass ATLAS_SSH_KEY_PASSPHRASE pw
out2=\$(run_hook install 2>&1)
printf '%s' \"\$out2\" | grep -qi 'touches the disk' && echo warns || echo SILENT" 2>&1 | tail -1)"
case "$out" in
  SKIP-tmpfs-host) _t_ok "staging-on-disk warning (host filesystem is tmpfs; test skipped)" ;;
  *) assert_eq "staging on a non-tmpfs directory warns that it touches the disk" "$out" "warns" ;;
esac

# --- SIGPIPE regression: backup read-back must not false-fail on a large listing -
# `printf "$listing" | grep -q` used to SIGPIPE the producer and, under pipefail,
# misreport a present member as missing. Import several keys so the listing is long.
out="$(bash -c "$PRE
mkdir -p \"\$HOME/.ssh\"
for k in a b c d e f g h; do
  mkkey \"\$HOME/.ssh/id_\$k\" '' \"key\$k\"
  ATLAS_SSH_IMPORT_KEY=\"\$HOME/.ssh/id_\$k\" run_hook install >/dev/null 2>&1
done
setpass ATLAS_BACKUP_PASSPHRASE bp
run_hook backup >/dev/null 2>&1; echo \"rc=\$?\"
gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d \"\$(artifact)\" 3< <(printf bp) 2>/dev/null | tar -t | grep -c id_ | tr -d ' '" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "backup of many keys succeeds and archives them all (SIGPIPE-safe read-back)" "$out" "rc=0 16 "

# --- SECURITY: a portable artifact must not name a key outside ~/.ssh ---------
# In disaster recovery (clean $HOME, no live manifest) a tampered, passphrase-
# protected artifact whose manifest names `.bashrc` would otherwise write
# arbitrary bytes to $HOME/.bashrc — RCE on the next shell. Owned keys live in
# ~/.ssh; restore refuses anything else. (Self-run security audit finding.)
out="$(bash -c "$BACKED
w=\$(mktemp -d)
gpg --batch -q --pinentry-mode loopback --passphrase-fd 3 -d \"\$(artifact)\" 3< <(printf bp) 2>/dev/null | tar -x -C \"\$w\"
fp=\$(awk '/^key /{print \$4}' \"\$w/config/ssh/manifest\")
h=\$(awk '/^key /{print \$5}' \"\$w/config/ssh/manifest\")
mv \"\$w/home/.ssh/id_ed25519\" \"\$w/home/.bashrc\"
mv \"\$w/home/.ssh/id_ed25519.pub\" \"\$w/home/.bashrc.pub\"
rmdir \"\$w/home/.ssh\" 2>/dev/null
printf '# atlas-ssh-manifest v1\nkey generated .bashrc %s %s 600\n' \"\$fp\" \"\$h\" > \"\$w/config/ssh/manifest\"
tar -cf - -C \"\$w\" . | gpg --batch --yes -q --pinentry-mode loopback --passphrase-fd 3 --symmetric --cipher-algo AES256 -o \"\$(artifact)\" 3< <(printf bp)
rm -rf \"\$HOME/.ssh\" \"\$ATLAS_CONFIG_HOME/ssh\"
run_hook restore >/dev/null 2>&1; echo rc=\$?
[ -f \"\$HOME/.bashrc\" ] && echo WROTE-BASHRC || echo contained" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "restore refuses an artifact naming a key outside ~/.ssh (write-under-HOME)" "$out" "rc=1 contained "

# import of a key outside ~/.ssh is refused (same constraint, at import time)
out="$(bash -c "$PRE
mkdir -p \"\$HOME/keys\"; mkkey \"\$HOME/keys/id_x\" '' kx
export ATLAS_SSH_IMPORT_KEY=\"\$HOME/keys/id_x\"
run_hook install >/dev/null 2>&1; echo rc=\$?
{ [ -s \"\$(manifest)\" ] && grep -q keys/id_x \"\$(manifest)\"; } && echo RECORDED || echo not-recorded" 2>&1 | tail -2 | tr '\n' ' ')"
assert_eq "import refuses a key outside ~/.ssh" "$out" "rc=1 not-recorded "
