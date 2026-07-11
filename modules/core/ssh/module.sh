#!/usr/bin/env bash
# core/ssh — RFC-0004. Manages an Atlas-owned workstation identity.
#
# Atlas owns only what it created or the user explicitly imported. Ownership is
# recorded in a manifest and bound to the bytes on disk by TWO values, because one
# is not enough: `ssh-keygen -lf <private>` silently reads the sibling `.pub`, so a
# fingerprint alone never sees the private half (RFC-0004 §4.4).
#
# `set -e` is SUSPENDED inside every hook — the runner calls them as
# `if ! module::x` (RFC-0004 §4.0). Every fallible command below is checked
# explicitly. Nothing here may rely on errexit.
MODULE_NAME="ssh"
MODULE_DESCRIPTION="OpenSSH client: manages an Atlas-owned workstation identity, with encrypted local backup."
MODULE_DEPENDS=()

_SSH_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Manifest records, populated by _ssh_manifest_load. Declared at module scope so
# every hook can measure them with ${#…[@]} even before a load — that form takes
# no `:-` default, and `set -u` is live inside hooks even though `set -e` is not.
_SSH_K_ORIGIN=(); _SSH_K_PATH=(); _SSH_K_FP=(); _SSH_K_HASH=(); _SSH_K_MODE=(); _SSH_GH_FP=()

# --- cleanup: exactly one trap, over a module-scope global (RFC-0004 §5.1) ----
# A trap set inside a hook is subshell-global and a later one REPLACES it; and a
# trap body naming a hook `local` errors under `set -u` after the local dies,
# flipping a successful module to rc=1. Both were observed. Hence: one array, one
# idempotent trap, and a body that touches only globals.
_SSH_CLEANUP=()
_ssh_cleanup() {
  local p
  for p in "${_SSH_CLEANUP[@]:-}"; do
    [ -n "$p" ] && rm -rf -- "$p"
  done
  return 0
}
_ssh_track() {
  [ -n "${_SSH_TRAP_SET:-}" ] || { trap _ssh_cleanup EXIT; _SSH_TRAP_SET=1; }
  _SSH_CLEANUP+=("$1")
}

# Sets $_SSH_TMP to a fresh 700 dir for key material. Prefers tmpfs (/dev/shm) so
# the plaintext never touches the disk. NEVER call in $( … ): the tracking would
# happen in a subshell and the dir would leak.
#
# $ATLAS_SSH_STAGING_DIR overrides the base directory — for an operator whose
# /dev/shm is too small for a large backup, and for the test suite (a per-sandbox
# dir, so tests never share the global /dev/shm).
#
# Whatever base is chosen, if it is NOT on a tmpfs the key material touches the
# disk, and Atlas says so. The warning is keyed on the filesystem *type*, not on
# how the base was selected — an override to a disk directory warns exactly like
# the involuntary $TMPDIR fallback. That closes the gap where an explicit override
# would silently decrypt private keys to disk.
_ssh_mktemp_dir() {
  local base
  if [ -n "${ATLAS_SSH_STAGING_DIR:-}" ]; then
    base="$ATLAS_SSH_STAGING_DIR"
    [ -d "$base" ] && [ -w "$base" ] || {
      log::error "ATLAS_SSH_STAGING_DIR is not a writable directory: $base"; return 1; }
  elif [ -d /dev/shm ] && [ -w /dev/shm ]; then
    base=/dev/shm
  else
    base="${TMPDIR:-/tmp}"
  fi
  # stat -f reports the filesystem type; tmpfs (and ramfs) keep plaintext off disk.
  local fstype; fstype="$(stat -f -c '%T' "$base" 2>/dev/null || true)"
  case "$fstype" in
    tmpfs|ramfs) ;;
    *) log::warn "staging key material under $base — a $fstype filesystem, so it touches the disk" ;;
  esac
  _SSH_TMP="$(mktemp -d "$base/atlas-ssh.XXXXXX")" || {
    log::error "cannot create a temporary directory under $base"; return 1; }
  chmod 700 "$_SSH_TMP" || { log::error "cannot secure $_SSH_TMP"; return 1; }
  _ssh_track "$_SSH_TMP"
}

# --- paths -------------------------------------------------------------------
_ssh_cfg_dir()     { printf '%s\n' "${ATLAS_CONFIG_HOME}/ssh"; }
_ssh_manifest()    { printf '%s\n' "$(_ssh_cfg_dir)/manifest"; }
_ssh_known_hosts() { printf '%s\n' "$(_ssh_cfg_dir)/known_hosts"; }
_ssh_default_key() { printf '%s\n' "$HOME/.ssh/id_ed25519"; }
_ssh_artifact()    { printf '%s\n' "${ATLAS_STATE_DIR}/backup/core-ssh.tar.gpg"; }
_ssh_abs()         { printf '%s\n' "$HOME/$1"; }          # manifest path -> absolute
_ssh_rel()         { printf '%s\n' "${1#"$HOME"/}"; }     # absolute -> manifest path

_ssh_comment() { printf '%s@%s (atlas)\n' "${USER:-$(id -un)}" "${HOSTNAME:-$(uname -n)}"; }

# --- primitives --------------------------------------------------------------
_ssh_fp_of_pub() { ssh-keygen -lf "$1" 2>/dev/null | awk '{print $2}'; }
_ssh_hash_of()   { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

# A path Atlas may own: under $HOME, no whitespace / newline / control character.
# Refused, never escaped — it keeps the manifest a line-oriented file that a
# crafted filename cannot spoof.
_ssh_path_ownable() {
  local p="$1"
  case "$p" in
    "$HOME"/*) ;;
    *) log::error "$p is not under \$HOME"; return 1 ;;
  esac
  case "$p" in
    *[[:space:]]*|*[[:cntrl:]]*)
      log::error "refusing a path containing whitespace or control characters"; return 1 ;;
    *'*'*|*'?'*|*'['*|*']'*)
      # A glob metacharacter would make `set -- $line` expand the field (and the
      # parser is guarded against that too), but a path Atlas *owns* has no
      # business containing one. Refuse rather than escape.
      log::error "refusing a path containing a glob metacharacter (* ? [ ])"; return 1 ;;
  esac
  # A `..` component escapes $HOME even though the prefix test above passed
  # ("$HOME"/* matches "$HOME/../etc"). Reject it explicitly.
  case "/$p/" in
    */../*) log::error "refusing a path containing '..': $p"; return 1 ;;
  esac
  # An owned key lives directly in ~/.ssh. Requiring that is not cosmetic: the
  # backup artifact is portable (designed to be copied off-box), and restore
  # writes each owned key to its recorded path. Without this, a tampered artifact
  # whose manifest names `.bashrc` (no `..`, not absolute) would drop arbitrary
  # bytes at ~/.bashrc — a write-anything-under-$HOME vector on restore. SSH keys
  # belong in ~/.ssh; constrain ownership to there. (Security hardening, §12.)
  case "$p" in
    "$HOME"/.ssh/*/*) log::error "an owned key must be directly in ~/.ssh, not a subdirectory: $p"; return 1 ;;
    "$HOME"/.ssh/?*) ;;
    *) log::error "Atlas only manages keys in ~/.ssh; refusing $p"; return 1 ;;
  esac
  return 0
}

# --- manifest ----------------------------------------------------------------
# The manifest is user-editable (§4.14), so its parser is a trust boundary.
# It rejects — never repairs, never ignores. Populates the _SSH_K_* arrays.
_ssh_manifest_load() {
  # `set -f` for the whole function: the field split below is `set -- $line`,
  # which performs PATHNAME EXPANSION. A path field with a glob would otherwise
  # be rewritten against $CWD, so the same manifest would parse differently
  # depending on where `atlas` was run. This parser is a trust boundary; its
  # result must depend only on the file. `local -` restores globbing on return,
  # and this function has no legitimate glob of its own.
  local -; set -f
  _SSH_K_ORIGIN=(); _SSH_K_PATH=(); _SSH_K_FP=(); _SSH_K_HASH=(); _SSH_K_MODE=(); _SSH_GH_FP=()
  local m; m="$(_ssh_manifest)"
  [ -e "$m" ] || return 0
  if [ -L "$m" ] || [ ! -f "$m" ]; then
    log::error "manifest is not a regular file: $m"; return 1
  fi

  local line n=0 hdr=0 i
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"                       # a manifest edited on Windows must still parse
    n=$((n + 1))
    [ -z "$line" ] && continue
    if [ "$line" = "# atlas-ssh-manifest v1" ]; then hdr=1; continue; fi
    case "$line" in \#*) continue ;; esac
    if [ "$hdr" -ne 1 ]; then
      log::error "manifest line $n: records before the '# atlas-ssh-manifest v1' header"; return 1
    fi
    # Split without globbing (set -f, above) and without word-splitting surprises:
    # ownable paths contain no whitespace, and glob metacharacters are refused.
    # shellcheck disable=SC2086
    set -- $line
    case "${1:-}" in
      key)
        if [ "$#" -ne 6 ]; then log::error "manifest line $n: 'key' needs 6 fields, got $#"; return 1; fi
        case "$2" in generated|imported) ;; *) log::error "manifest line $n: bad origin '$2'"; return 1 ;; esac
        case "$4" in SHA256:?*) ;; *) log::error "manifest line $n: bad fingerprint"; return 1 ;; esac
        case "$5" in *[!0-9a-f]*|"") log::error "manifest line $n: bad private-key hash"; return 1 ;; esac
        case "$6" in [0-7][0-7][0-7]) ;; *) log::error "manifest line $n: bad mode '$6'"; return 1 ;; esac
        for i in "${_SSH_K_PATH[@]:-}"; do
          if [ "$i" = "$3" ]; then log::error "manifest line $n: duplicate path '$3'"; return 1; fi
        done
        _SSH_K_ORIGIN+=("$2"); _SSH_K_PATH+=("$3"); _SSH_K_FP+=("$4"); _SSH_K_HASH+=("$5"); _SSH_K_MODE+=("$6")
        ;;
      github)
        if [ "$#" -ne 2 ]; then log::error "manifest line $n: 'github' needs 2 fields"; return 1; fi
        for i in "${_SSH_GH_FP[@]:-}"; do
          if [ "$i" = "$2" ]; then log::error "manifest line $n: duplicate github record"; return 1; fi
        done
        _SSH_GH_FP+=("$2")
        ;;
      *) log::error "manifest line $n: unknown record type '${1:-}'"; return 1 ;;
    esac
  done < "$m"

  if [ "$hdr" -ne 1 ]; then log::error "manifest: missing '# atlas-ssh-manifest v1' header"; return 1; fi

  # An orphan `github` record names a key no `key` record claims.
  local g found
  for g in "${_SSH_GH_FP[@]:-}"; do
    [ -n "$g" ] || continue
    found=0
    for i in "${_SSH_K_FP[@]:-}"; do [ "$i" = "$g" ] && found=1; done
    if [ "$found" -ne 1 ]; then log::error "manifest: github record for an unknown key ($g)"; return 1; fi
  done
  return 0
}

_ssh_manifest_append() {
  local m d tmp; m="$(_ssh_manifest)"; d="$(_ssh_cfg_dir)"
  mkdir -p "$d" || { log::error "cannot create $d"; return 1; }
  chmod 700 "$d" || { log::error "cannot secure $d"; return 1; }
  tmp="$(mktemp "$d/.manifest.XXXXXX")" || { log::error "cannot create a temp file in $d"; return 1; }
  if [ -f "$m" ]; then
    cat "$m" > "$tmp" || { rm -f "$tmp"; log::error "cannot read $m"; return 1; }
  else
    printf '# atlas-ssh-manifest v1\n' > "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  printf '%s\n' "$1" >> "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$m" || { rm -f "$tmp"; log::error "cannot write $m"; return 1; }
}

# Is owned key $1 (index) intact? Prints nothing; returns 0 when intact.
_ssh_key_intact() {
  local i="$1" abs; abs="$(_ssh_abs "${_SSH_K_PATH[$i]}")"
  [ -L "$abs" ] && return 1
  [ -f "$abs" ] && [ -r "$abs" ] || return 1
  [ -f "$abs.pub" ] && [ -r "$abs.pub" ] || return 1
  [ "$(_ssh_fp_of_pub "$abs.pub")" = "${_SSH_K_FP[$i]}" ] || return 1
  [ "$(_ssh_hash_of "$abs")" = "${_SSH_K_HASH[$i]}" ] || return 1
  return 0
}

# 0 (true) when ANY owned key diverges. One bad key poisons the module (§4.15).
_ssh_any_divergent() {
  local i n="${#_SSH_K_PATH[@]}"
  for ((i = 0; i < n; i++)); do
    if ! _ssh_key_intact "$i"; then return 0; fi
  done
  return 1
}

_ssh_report_divergence() {
  local i n="${#_SSH_K_PATH[@]}" abs
  for ((i = 0; i < n; i++)); do
    _ssh_key_intact "$i" && continue
    abs="$(_ssh_abs "${_SSH_K_PATH[$i]}")"
    log::error "the key Atlas recorded is not the key on disk: $abs"
    if [ -L "$abs" ]; then      log::error "  why: it is now a symlink"
    elif [ ! -e "$abs" ]; then  log::error "  why: it no longer exists"
    elif [ ! -f "$abs" ]; then  log::error "  why: it is not a regular file"
    elif [ ! -r "$abs" ]; then  log::error "  why: it is not readable"
    elif [ ! -r "$abs.pub" ]; then log::error "  why: its public half is missing"
    else log::error "  why: its contents changed (a swapped key, or a rotated passphrase)"
    fi
  done
  log::error "  fix: delete that key's line from $(_ssh_manifest) to disown it,"
  log::error "       then re-run; to re-adopt it, also set ATLAS_SSH_IMPORT_KEY=<path>"
}

# --- generation --------------------------------------------------------------
# Prints: pass | empty | none | conflict.  Never prints or assigns the secret.
_ssh_gen_mode() {
  local have=0
  env::get_secret ATLAS_SSH_KEY_PASSPHRASE >/dev/null 2>&1 && have=1
  if [ "${ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE:-}" = "1" ]; then
    [ "$have" -eq 1 ] && { printf 'conflict\n'; return 0; }
    printf 'empty\n'; return 0
  fi
  [ "$have" -eq 1 ] && { printf 'pass\n'; return 0; }
  printf 'none\n'
}

_ssh_ensure_dot_ssh() {
  if [ ! -e "$HOME/.ssh" ]; then
    mkdir -p "$HOME/.ssh" || { log::error "cannot create $HOME/.ssh"; return 1; }
    chmod 700 "$HOME/.ssh" || { log::error "cannot secure $HOME/.ssh"; return 1; }
    log::info "created $HOME/.ssh (mode 700)"
  fi
  # An EXISTING ~/.ssh is user state. Never chmod it; verify reports a bad mode.
  [ -d "$HOME/.ssh" ] || { log::error "$HOME/.ssh is not a directory"; return 1; }
}

_ssh_generate() {
  local key="$1" mode="$2" rc=0
  _ssh_ensure_dot_ssh || return 1

  if [ "$mode" = "empty" ]; then
    log::warn "generating an UNENCRYPTED private key: ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE=1"
    log::warn "  anyone who reads $key becomes you. This is your explicit choice."
    ssh-keygen -t ed25519 -f "$key" -N '' -C "$(_ssh_comment)" -q </dev/null \
      || { log::error "ssh-keygen failed"; return 1; }
    log::info "generated $key (unencrypted)"
    return 0
  fi

  # Encrypted. `ssh-keygen -N <pass>` would put the secret in argv (world-readable
  # in /proc), so the passphrase is delivered on the askpass helper's STDOUT.
  # The helper holds no secret: it execs the resolver.
  _ssh_mktemp_dir || return 1
  local helper="$_SSH_TMP/askpass"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -uo pipefail\n'
    printf 'source "$ATLAS_ROOT/internal/log.sh"\n'
    printf 'source "$ATLAS_ROOT/internal/env.sh"\n'
    printf 'env::get_secret ATLAS_SSH_KEY_PASSPHRASE\n'
  } > "$helper" || { log::error "cannot write the askpass helper"; return 1; }
  chmod 700 "$helper" || return 1

  # `export NAME` (no value) marks it for the child without ever expanding it —
  # `[ -n "$NAME" ]` would trace the value under `set -x`.
  export ATLAS_SSH_KEY_PASSPHRASE 2>/dev/null || true

  log::info "generating an ed25519 key at $key"
  env -u DISPLAY \
      ATLAS_ROOT="$ATLAS_ROOT" ATLAS_CONFIG_HOME="$ATLAS_CONFIG_HOME" \
      SSH_ASKPASS="$helper" SSH_ASKPASS_REQUIRE=force \
      ssh-keygen -t ed25519 -f "$key" -C "$(_ssh_comment)" -q </dev/null || rc=1

  # The helper is finished with — remove it now, not at subshell exit. It holds no
  # secret, but leaving temp dirs around during a long run is untidy (§5.1: the
  # trap is a backstop, explicit cleanup is the rule).
  rm -rf -- "$_SSH_TMP"

  if [ "$rc" -ne 0 ]; then
    log::error "ssh-keygen failed"
    log::error "  why: it may have declined SSH_ASKPASS, or the passphrase was unreadable"
    rm -f "$key" "$key.pub"
    return 1
  fi

  # §4.5: `ssh-keygen` without -N and without a working askpass produces an
  # UNENCRYPTED key and exits 0. Never trust its exit code — assert the property.
  if ssh-keygen -y -f "$key" -P '' >/dev/null 2>&1; then
    log::error "refusing to keep the key: it has no passphrase"
    log::error "  why: ssh-keygen ignored SSH_ASKPASS, so the key was generated unencrypted"
    rm -f "$key" "$key.pub"
    return 1
  fi
  log::info "generated $key (encrypted)"
}

_ssh_record_key() {              # <origin> <abs-path>
  local origin="$1" abs="$2" fp hash mode
  fp="$(_ssh_fp_of_pub "$abs.pub")"
  hash="$(_ssh_hash_of "$abs")"
  mode="$(stat -c '%a' "$abs" 2>/dev/null)"
  if [ -z "$fp" ] || [ -z "$hash" ] || [ -z "$mode" ]; then
    log::error "cannot fingerprint $abs"; return 1
  fi
  _ssh_manifest_append "key $origin $(_ssh_rel "$abs") $fp $hash $mode"
}

# --- import ------------------------------------------------------------------
_ssh_import() {
  local abs="$1" i rel fp
  [ -L "$abs" ] && { log::error "refusing to import a symlink: $abs"; return 1; }
  [ -f "$abs" ] || { log::error "not a regular file: $abs"; return 1; }
  _ssh_path_ownable "$abs" || return 1
  [ -r "$abs.pub" ] || { log::error "no public half beside $abs (expected $abs.pub)"; return 1; }

  rel="$(_ssh_rel "$abs")"; fp="$(_ssh_fp_of_pub "$abs.pub")"
  [ -n "$fp" ] || { log::error "cannot fingerprint $abs.pub"; return 1; }

  for ((i = 0; i < ${#_SSH_K_PATH[@]}; i++)); do
    if [ "${_SSH_K_PATH[$i]}" = "$rel" ]; then
      if _ssh_key_intact "$i"; then log::info "already imported: $abs"; return 0; fi
      log::error "$abs is recorded but its bytes changed since"; return 1
    fi
  done
  _ssh_record_key imported "$abs" || return 1
  log::info "imported $abs (Atlas will back it up; it will never modify it)"
}

# --- GitHub ------------------------------------------------------------------
# `gh auth token` PRINTS the token. Predicate only; never capture (RFC-0003).
_ssh_gh_authed() {
  os::has_cmd gh || return 1
  gh auth token >/dev/null 2>&1
}

_ssh_gh_has_key() {              # <abs> — is this pubkey already on the account?
  local blob keys
  blob="$(cut -d' ' -f1,2 < "$1.pub")"
  # Capture, then match with a here-string. `gh … | grep -q` would let grep close
  # the pipe on its first match, `gh` would take SIGPIPE (141), and under `pipefail`
  # the pipeline would report failure even though the key WAS found — a false
  # "not present" that re-uploads a key already on the account.
  keys="$(gh api user/keys 2>/dev/null)" || return 1
  grep -qxF "$blob" <<<"$keys"
}

_ssh_register() {
  local i n="${#_SSH_K_PATH[@]}" abs fp g known
  _ssh_gh_authed || {
    if [ "$n" -gt 0 ]; then
      log::warn "gh is not authenticated — not registering your key with GitHub"
      log::warn "  fix: run 'gh auth login', then re-run 'atlas install core/ssh'"
    fi
    return 0
  }
  for ((i = 0; i < n; i++)); do
    _ssh_key_intact "$i" || continue
    fp="${_SSH_K_FP[$i]}"; abs="$(_ssh_abs "${_SSH_K_PATH[$i]}")"
    known=0
    for g in "${_SSH_GH_FP[@]:-}"; do [ "$g" = "$fp" ] && known=1; done
    [ "$known" -eq 1 ] && continue

    if _ssh_gh_has_key "$abs"; then
      log::info "this key is already on your GitHub account — recording that"
    else
      log::info "registering $abs.pub with GitHub"
      # `gh` prints a success line to stdout; the runner reads a hook's stdout for
      # the `__SKIP__` control token, so send gh's chatter to the log's channel.
      if ! gh ssh-key add - --title "$(_ssh_comment)" < "$abs.pub" >/dev/null; then
        log::warn "could not add the key to GitHub — leaving it unregistered"
        log::warn "  why: gh may lack the 'admin:public_key' scope, or GitHub was unreachable"
        log::warn "  fix: gh auth refresh -h github.com -s admin:public_key"
        continue
      fi
    fi
    _ssh_manifest_append "github $fp" || return 1
    _SSH_GH_FP+=("$fp")
  done
  return 0
}

# --- connectivity (reported, never fatal) ------------------------------------
_ssh_report_connectivity() {
  local abs="$1" out
  if [ "${ATLAS_SSH_NO_NETWORK:-}" = "1" ]; then
    log::info "skipping the GitHub connectivity check (ATLAS_SSH_NO_NETWORK=1)"; return 0
  fi
  if ! ssh-keygen -y -f "$abs" -P '' >/dev/null 2>&1; then
    log::info "cannot test connectivity: $abs is encrypted (Atlas will not decrypt it)"; return 0
  fi
  # `ssh -T git@github.com` exits 1 ON SUCCESS. Never read its exit code.
  out="$(ssh -o UserKnownHostsFile="$(_ssh_known_hosts)" -o StrictHostKeyChecking=yes \
            -o BatchMode=yes -o ConnectTimeout=10 -o IdentitiesOnly=yes -i "$abs" \
            -T git@github.com 2>&1)" || true
  case "$out" in
    *"successfully authenticated"*) log::info "GitHub SSH connectivity: OK" ;;
    *"Permission denied"*)          log::warn "GitHub rejected this key — is it registered?" ;;
    *)                              log::warn "could not reach GitHub over SSH (offline?) — not a fault" ;;
  esac
  return 0
}

# =============================================================================
# hooks
# =============================================================================

module::check() {
  os::has_cmd ssh || return 1
  os::has_cmd ssh-keygen || return 1
  _ssh_manifest_load >/dev/null 2>&1 || return 1        # unparseable => divergent
  if _ssh_any_divergent; then return 1; fi

  local gm; gm="$(_ssh_gen_mode)"
  [ "$gm" = "conflict" ] && return 1
  if [ "$gm" != "none" ] && [ "${#_SSH_K_PATH[@]}" -eq 0 ] && [ ! -e "$(_ssh_default_key)" ]; then
    return 1                                            # install would generate
  fi

  if [ -n "${ATLAS_SSH_IMPORT_KEY:-}" ]; then           # install would import
    local rel i seen=0
    rel="$(_ssh_rel "${ATLAS_SSH_IMPORT_KEY}")"
    for ((i = 0; i < ${#_SSH_K_PATH[@]}; i++)); do
      [ "${_SSH_K_PATH[$i]}" = "$rel" ] && seen=1
    done
    [ "$seen" -eq 1 ] || return 1
  fi

  if _ssh_gh_authed; then                               # install would register
    local i fp g known
    for ((i = 0; i < ${#_SSH_K_PATH[@]}; i++)); do
      _ssh_key_intact "$i" || continue
      fp="${_SSH_K_FP[$i]}"; known=0
      for g in "${_SSH_GH_FP[@]:-}"; do [ "$g" = "$fp" ] && known=1; done
      [ "$known" -eq 1 ] || return 1
    done
  fi
  return 0
}

module::install() {
  # 1. packages
  local -a want=()
  os::has_cmd ssh || want+=(openssh-clients)
  os::has_cmd gpg || want+=(gnupg2)
  if [ "${#want[@]}" -gt 0 ]; then
    os::dnf_install "${want[@]}" || { log::error "failed to install ${want[*]}"; return 1; }
  fi

  # 2. refuse to act on a divergent manifest, before touching anything
  _ssh_manifest_load || { log::error "  fix: repair or delete $(_ssh_manifest)"; return 1; }
  if _ssh_any_divergent; then _ssh_report_divergence; return 1; fi

  # 3. Atlas's own known_hosts (never the user's)
  mkdir -p "$(_ssh_cfg_dir)" || { log::error "cannot create $(_ssh_cfg_dir)"; return 1; }
  chmod 700 "$(_ssh_cfg_dir)" || return 1
  cp -f "$_SSH_MODULE_DIR/config/known_hosts" "$(_ssh_known_hosts)" \
    || { log::error "cannot write $(_ssh_known_hosts)"; return 1; }

  # 4. import
  if [ -n "${ATLAS_SSH_IMPORT_KEY:-}" ]; then
    _ssh_import "${ATLAS_SSH_IMPORT_KEY}" || return 1
    _ssh_manifest_load || return 1
  fi

  # 5. generate — opt-in, never a default
  local gm key; gm="$(_ssh_gen_mode)"; key="$(_ssh_default_key)"
  case "$gm" in
    conflict)
      log::error "ATLAS_SSH_KEY_PASSPHRASE and ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE=1 contradict each other"
      log::error "  fix: unset one. Atlas will not guess which you meant"
      return 1 ;;
    none)
      if [ "${#_SSH_K_PATH[@]}" -eq 0 ]; then
        log::warn "no SSH key generated: Atlas never creates an identity you did not ask for"
        log::warn "  fix: set ATLAS_SSH_KEY_PASSPHRASE in ~/.config/atlas/atlas.env (mode 600),"
        log::warn "       or ATLAS_SSH_ALLOW_EMPTY_PASSPHRASE=1 to accept an unencrypted key"
      fi ;;
    pass|empty)
      if [ -e "$key" ]; then
        local claimed=0 i
        for ((i = 0; i < ${#_SSH_K_PATH[@]}; i++)); do
          [ "${_SSH_K_PATH[$i]}" = "$(_ssh_rel "$key")" ] && claimed=1
        done
        if [ "$claimed" -eq 0 ]; then
          log::warn "$key already exists and Atlas does not own it — not overwriting it"
          log::warn "  fix: import it with ATLAS_SSH_IMPORT_KEY=$key, or move it aside"
        fi
      elif [ "${#_SSH_K_PATH[@]}" -gt 0 ]; then
        log::info "Atlas already owns a key — not generating another"
      else
        _ssh_generate "$key" "$gm" || return 1
        _ssh_record_key generated "$key" || return 1
        _ssh_manifest_load || return 1
      fi ;;
  esac

  # 6. GitHub registration — best-effort, never fails the install
  _ssh_register || return 1
  return 0
}

module::verify() {
  os::has_cmd ssh || { log::error "ssh is not installed"; return 1; }
  os::has_cmd ssh-keygen || { log::error "ssh-keygen is not installed"; return 1; }
  ssh -V >/dev/null 2>&1 || { log::error "ssh -V failed"; return 1; }

  _ssh_manifest_load || return 1
  if _ssh_any_divergent; then _ssh_report_divergence; return 1; fi

  local n="${#_SSH_K_PATH[@]}" i abs mode fail=0

  if [ -d "$HOME/.ssh" ]; then
    mode="$(stat -c '%a' "$HOME/.ssh" 2>/dev/null)"
    if [ "$mode" != "700" ]; then
      log::error "$HOME/.ssh has mode $mode; OpenSSH requires 700"
      log::error "  fix: chmod 700 $HOME/.ssh   (Atlas will not change a directory it did not create)"
      fail=1
    fi
  fi

  for ((i = 0; i < n; i++)); do
    abs="$(_ssh_abs "${_SSH_K_PATH[$i]}")"
    mode="$(stat -c '%a' "$abs" 2>/dev/null)"
    if [ "$mode" != "600" ]; then
      log::error "$abs has mode $mode; OpenSSH requires 600"
      log::error "  fix: chmod 600 $abs"
      fail=1
    fi
    mode="$(stat -c '%a' "$abs.pub" 2>/dev/null)"
    if [ "$mode" != "644" ]; then
      log::warn "$abs.pub has mode $mode (644 is conventional)"
    fi
  done

  [ "$fail" -eq 0 ] || return 1

  if [ "$n" -eq 0 ]; then
    log::warn "Atlas owns no SSH key on this machine"
    local gm; gm="$(_ssh_gen_mode)"
    if [ "$gm" != "none" ] && [ -e "$(_ssh_default_key)" ]; then
      log::warn "  a passphrase is set, but $(_ssh_default_key) exists and Atlas does not own it"
      log::warn "  fix: ATLAS_SSH_IMPORT_KEY=$(_ssh_default_key) atlas install core/ssh"
    fi
  fi

  # External keys: report by fingerprint AND path, touch nothing. (RFC §4.15 asks
  # for the fingerprint — it identifies the key even if the file is later moved.)
  local f rel owned fp
  for f in "$HOME"/.ssh/id_*; do
    case "$f" in *.pub|*'*'*) continue ;; esac
    [ -f "$f" ] || continue
    rel="$(_ssh_rel "$f")"; owned=0
    for ((i = 0; i < n; i++)); do [ "${_SSH_K_PATH[$i]}" = "$rel" ] && owned=1; done
    [ "$owned" -eq 1 ] && continue
    if [ -r "$f.pub" ]; then fp="$(_ssh_fp_of_pub "$f.pub")"; else fp="(no public half)"; fi
    log::info "external key (Atlas does not manage it): $fp  $f"
  done

  for ((i = 0; i < n; i++)); do
    _ssh_report_connectivity "$(_ssh_abs "${_SSH_K_PATH[$i]}")"
  done
  return 0
}

module::update() {
  os::has_cmd ssh || { log::error "ssh is not installed — run 'atlas install core/ssh'"; return 1; }
  mkdir -p "$(_ssh_cfg_dir)" || { log::error "cannot create $(_ssh_cfg_dir)"; return 1; }
  chmod 700 "$(_ssh_cfg_dir)" || return 1
  cp -f "$_SSH_MODULE_DIR/config/known_hosts" "$(_ssh_known_hosts)" \
    || { log::error "cannot refresh $(_ssh_known_hosts)"; return 1; }
  log::info "refreshed the pinned known_hosts"
  log::info "left every key untouched: Atlas never rotates or re-encrypts a key"
  return 0
}

# --- backup / restore: the reference implementation (RFC-0004 §4.10) ---------

# Thin wrapper (see module::restore): removes the staging dir this call created —
# a symlink farm, so no plaintext key, but temp dirs should not outlive the hook
# that made them. The `_ssh_cleanup` trap remains the backstop.
module::backup() {
  local st_before="${_SSH_TMP:-}"
  _ssh_backup_impl; local rc=$?
  if [ -n "${_SSH_TMP:-}" ] && [ "${_SSH_TMP:-}" != "$st_before" ]; then
    rm -rf -- "$_SSH_TMP"
  fi
  return "$rc"
}

_ssh_backup_impl() {
  _ssh_manifest_load || return 1
  if _ssh_any_divergent; then
    _ssh_report_divergence
    log::error "refusing to back up: the manifest and the disk disagree"
    return 1
  fi

  local art n="${#_SSH_K_PATH[@]}"; art="$(_ssh_artifact)"
  if [ "$n" -eq 0 ]; then
    log::info "nothing to back up: Atlas owns no SSH key"
    if [ -e "$art" ]; then
      log::warn "a previous artifact remains at $art"
      log::warn "  it describes state Atlas no longer owns; restoring it would re-adopt those keys"
    fi
    return 0
  fi

  os::has_cmd gpg || {
    log::error "gpg is not installed — cannot encrypt the backup"
    log::error "  fix: sudo dnf install gnupg2"; return 1; }

  # Discard-probe: separates "no usable secret" (this) from "the tool rejected it".
  env::get_secret ATLAS_BACKUP_PASSPHRASE >/dev/null || {
    log::error "no usable ATLAS_BACKUP_PASSPHRASE — refusing to write an unencrypted backup"
    log::error "  fix: add ATLAS_BACKUP_PASSPHRASE to ~/.config/atlas/atlas.env (mode 600)"
    return 1; }

  # Staging is a farm of SYMLINKS; `tar --dereference` archives the contents.
  # No plaintext copy of a private key is ever written.
  _ssh_mktemp_dir || return 1
  local st="$_SSH_TMP" i abs rel
  mkdir -p "$st/config/ssh" || return 1
  for ((i = 0; i < n; i++)); do
    rel="${_SSH_K_PATH[$i]}"; abs="$(_ssh_abs "$rel")"
    mkdir -p "$st/home/$(dirname "$rel")" || return 1
    ln -s "$abs" "$st/home/$rel" || return 1
    ln -s "$abs.pub" "$st/home/$rel.pub" || return 1
  done
  ln -s "$(_ssh_manifest)" "$st/config/ssh/manifest" || return 1
  [ -e "$(_ssh_known_hosts)" ] && { ln -s "$(_ssh_known_hosts)" "$st/config/ssh/known_hosts" || return 1; }

  mkdir -p "$(dirname "$art")" || { log::error "cannot create $(dirname "$art")"; return 1; }
  chmod 700 "$(dirname "$art")" || return 1

  # Write a TEMP artifact. `gpg --yes -o "$art"` would truncate the last good
  # backup before this one is verified (§4.10 item 3). The `umask 077` in a
  # subshell means gpg creates the file 600 from the start — without it there is a
  # window between gpg's create (at the process umask, typically 644) and the
  # chmod below where the *ciphertext* is world-readable.
  if ! ( umask 077
         tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner --dereference \
             -cf - -C "$st" . 2>/dev/null \
         | gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-fd 3 \
               --symmetric --cipher-algo AES256 -o "$art.tmp" \
               3< <(env::get_secret ATLAS_BACKUP_PASSPHRASE) 2>/dev/null )
  then
    log::error "the backup pipeline failed"; rm -f "$art.tmp"; return 1
  fi
  chmod 600 "$art.tmp" || { rm -f "$art.tmp"; return 1; }

  # Read it back. A backup that has not been read back is a hypothesis.
  local listing
  listing="$(gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 -d "$art.tmp" \
               3< <(env::get_secret ATLAS_BACKUP_PASSPHRASE) 2>/dev/null | tar -t 2>/dev/null)" || {
    log::error "the artifact did not read back — not replacing the previous one"
    rm -f "$art.tmp"; return 1; }

  # …and it must NOT open without a passphrase. gpg refuses an empty one today;
  # assert it rather than trust it, on whatever gpg the user actually has.
  if gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 -d "$art.tmp" \
         3< /dev/null >/dev/null 2>&1; then
    log::error "the artifact decrypts with an empty passphrase — refusing to keep it"
    rm -f "$art.tmp"; return 1
  fi

  # here-strings, not `printf … | grep -q`: grep closes the pipe on its first match,
  # printf takes SIGPIPE (141), and `pipefail` would then read the whole check as
  # failed — a false "artifact is missing" that fails a perfectly good backup.
  for ((i = 0; i < n; i++)); do
    rel="${_SSH_K_PATH[$i]}"
    grep -qxF "./home/$rel" <<<"$listing" || {
      log::error "the artifact is missing $rel"; rm -f "$art.tmp"; return 1; }
  done
  grep -qxF "./config/ssh/manifest" <<<"$listing" || {
    log::error "the artifact is missing the manifest"; rm -f "$art.tmp"; return 1; }

  mv -f "$art.tmp" "$art" || { rm -f "$art.tmp"; log::error "cannot replace $art"; return 1; }
  log::info "wrote $art"
  log::info "  it holds only Atlas-owned state, encrypted with ATLAS_BACKUP_PASSPHRASE"
  log::info "  Atlas never uploads it. Copying it somewhere safe is your job"
  return 0
}

# Thin wrapper: guarantees the staging dir — which holds DECRYPTED private keys —
# is removed the instant restore returns, on EVERY path including failure, rather
# than lingering on tmpfs until the module's subshell exits. The `_ssh_cleanup`
# trap remains the backstop (a SIGKILL between here and the rm). `set -f` for the
# duration: the archived-manifest split below is `set -- $line`, which globs.
module::restore() {
  local -; set -f
  local st_before="${_SSH_TMP:-}"
  _ssh_restore_impl; local rc=$?
  # Remove the staging dir this call created (if any), even on the failure paths.
  if [ -n "${_SSH_TMP:-}" ] && [ "${_SSH_TMP:-}" != "$st_before" ]; then
    rm -rf -- "$_SSH_TMP"
  fi
  return "$rc"
}

_ssh_restore_impl() {
  local art; art="$(_ssh_artifact)"
  [ -f "$art" ] || { log::error "no backup artifact at $art"; return 1; }
  os::has_cmd gpg || { log::error "gpg is not installed"; return 1; }
  env::get_secret ATLAS_BACKUP_PASSPHRASE >/dev/null || {
    log::error "no usable ATLAS_BACKUP_PASSPHRASE — cannot decrypt $art"; return 1; }

  _ssh_mktemp_dir || return 1
  local st="$_SSH_TMP"

  gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 3 -d "$art" \
      3< <(env::get_secret ATLAS_BACKUP_PASSPHRASE) > "$st/archive.tar" 2>/dev/null || {
    log::error "cannot decrypt $art (wrong passphrase, or a corrupt artifact)"; return 1; }

  # LIST BEFORE EXTRACTING. `tar -t` prints names only — it cannot see member
  # types, so a symlink member would sail through. `tar -tv` shows the type flag.
  local types name
  types="$(tar -tvf "$st/archive.tar" 2>/dev/null | cut -c1 | sort -u | tr -d '\n')" || {
    log::error "cannot list $art"; return 1; }
  # Only regular files (-) and directories (d) are allowed. Test the character SET,
  # not a sorted string: `sort -u` orders "-d", and the collation is locale-dependent.
  # `-` must come last inside the bracket so it is a literal, not a range.
  case "$types" in
    ''|*[!d-]*)
      log::error "the artifact contains members that are not plain files or directories"
      log::error "  (a symlink, hardlink or device member — refusing to extract it)"
      return 1 ;;
  esac
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    name="${name#./}"
    case "$name" in
      home/*|config/*) ;;
      *) log::error "artifact member outside home/ or config/: $name"; return 1 ;;
    esac
    case "$name" in
      /*|*..*) log::error "unsafe artifact member: $name"; return 1 ;;
    esac
  done < <(tar -tf "$st/archive.tar" 2>/dev/null | grep -v '/$')

  mkdir -p "$st/x" || return 1
  tar -xf "$st/archive.tar" -C "$st/x" --no-same-owner 2>/dev/null || {
    log::error "cannot extract $art"; return 1; }

  # Validate the archived manifest against the archived keys.
  local am="$st/x/config/ssh/manifest"
  [ -f "$am" ] || { log::error "the artifact has no manifest"; return 1; }

  # Scan EVERY target for conflicts before writing ANY of them.
  local -a srcs=() dsts=() modes=()
  local line rel fp hash mode src dst conflicts=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*) continue ;; esac
    # shellcheck disable=SC2086
    set -- $line                                  # globbing disabled by the wrapper's set -f
    [ "${1:-}" = "key" ] || continue
    # The archived manifest is untrusted input. A short record must be REJECTED,
    # not crash the hook: under the runner's `set -u`, `rel="$3"` on a 2-field
    # line aborts the whole subshell with `$3: unbound variable`.
    if [ "$#" -ne 6 ]; then log::error "the artifact's manifest has a malformed key record"; return 1; fi
    rel="$3"; fp="$4"; hash="$5"; mode="$6"
    # `dst` is built as `$HOME/$rel`. A `..`, an absolute path, or a glob in `rel`
    # would let a crafted (passphrase-protected) artifact write outside where Atlas
    # is allowed to. Refuse; the write target must stay a plain path under $HOME.
    case "$rel" in
      /*|*..*) log::error "the artifact names an unsafe key path: $rel"; return 1 ;;
      *'*'*|*'?'*|*'['*|*']'*) log::error "the artifact names a glob key path: $rel"; return 1 ;;
    esac
    # An owned key lives directly in ~/.ssh. A crafted, passphrase-protected
    # artifact must not be able to name (say) `.bashrc` and have restore write
    # arbitrary bytes there. The generated key is `.ssh/id_ed25519`; imports are
    # constrained to ~/.ssh too. (Security hardening, §12.)
    case "$rel" in
      .ssh/*/*) log::error "the artifact names a key outside ~/.ssh: $rel"; return 1 ;;
      .ssh/?*) ;;
      *) log::error "the artifact names a key outside ~/.ssh: $rel"; return 1 ;;
    esac
    src="$st/x/home/$rel"
    [ -f "$src" ] || { log::error "the artifact is missing $rel"; return 1; }
    [ "$(_ssh_hash_of "$src")" = "$hash" ] || { log::error "$rel does not match its recorded hash"; return 1; }
    [ "$(_ssh_fp_of_pub "$src.pub")" = "$fp" ] || { log::error "$rel does not match its recorded fingerprint"; return 1; }
    srcs+=("$src" "$src.pub"); dsts+=("$HOME/$rel" "$HOME/$rel.pub"); modes+=("$mode" "644")
  done < "$am"

  srcs+=("$am"); dsts+=("$(_ssh_manifest)"); modes+=("600")     # manifest LAST
  if [ -f "$st/x/config/ssh/known_hosts" ]; then
    srcs=("$st/x/config/ssh/known_hosts" "${srcs[@]}")
    dsts=("$(_ssh_known_hosts)" "${dsts[@]}")
    modes=("644" "${modes[@]}")
  fi

  local i
  for ((i = 0; i < ${#dsts[@]}; i++)); do
    dst="${dsts[$i]}"
    if [ -L "$dst" ]; then
      log::error "conflict: $dst is a symlink; Atlas will not write through it"; conflicts=1
    elif [ -e "$dst" ]; then
      if ! cmp -s "${srcs[$i]}" "$dst"; then
        log::error "conflict: $dst exists and differs from the backup"; conflicts=1
      fi
    fi
  done
  if [ "$conflicts" -ne 0 ]; then
    log::error "restoring would overwrite files that are not the ones Atlas backed up"
    log::error "  nothing has been written"
    log::error "  fix: move the listed files aside, or restore into a different \$HOME"
    return 1
  fi

  log::info "restoring into $HOME:"
  for ((i = 0; i < ${#dsts[@]}; i++)); do log::info "  ${dsts[$i]}"; done

  _ssh_ensure_dot_ssh || return 1
  mkdir -p "$(_ssh_cfg_dir)" || return 1
  chmod 700 "$(_ssh_cfg_dir)" || return 1
  for ((i = 0; i < ${#dsts[@]}; i++)); do
    dst="${dsts[$i]}"
    if [ -e "$dst" ]; then continue; fi                       # byte-identical: skip (idempotent)
    mkdir -p "$(dirname "$dst")" || return 1
    cp -f "${srcs[$i]}" "$dst" || { log::error "cannot write $dst"; return 1; }
    chmod "${modes[$i]}" "$dst" || return 1
  done

  # The trap (§5.1) is a safety net for the failure paths, and it fires only when
  # the module's subshell exits. Staging holds the DECRYPTED private keys, so on
  # the success path remove it the moment it is no longer needed rather than
  # leaving it on tmpfs for the rest of the run. The trap's later `rm -rf` on an
  # already-removed path is a harmless no-op.
  rm -rf -- "$st"

  log::info "restore complete — Atlas now owns the keys listed above"
  return 0
}
