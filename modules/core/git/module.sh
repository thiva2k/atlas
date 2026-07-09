#!/usr/bin/env bash
MODULE_NAME="git"
MODULE_DESCRIPTION="Distributed version control: installs git and applies Atlas's global defaults."
MODULE_DEPENDS=()

# Absolute path to this module's directory (for its config/ fragment source).
_GIT_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- module-local helpers ----------------------------------------------------

_git_fragment_dir() {
  printf '%s\n' "${ATLAS_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/atlas}/git"
}
_git_fragment() { printf '%s\n' "$(_git_fragment_dir)/gitconfig"; }

# The global config file git itself would read/write.
_git_config_file() { printf '%s\n' "${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}"; }

# True if our fragment path is already an include.path in ~/.gitconfig.
_git_include_present() {
  git config --global --get-all include.path 2>/dev/null \
    | grep -qxF "$(_git_fragment)"
}

# The block we prepend. Git resolves config positionally and expands an include
# at the position of the directive, so this must come BEFORE the user's own
# sections: then anything they set below overrides our default (RFC-0001 §4.4).
# The path is quoted, as git's own writer would, so a `#` or `;` in it is not
# read as a comment.
_git_include_block() { printf '[include]\n\tpath = "%s"\n\n' "$(_git_fragment)"; }

# True if the Atlas [include] is the first section of $1 (blanks/comments skipped).
_git_include_is_first() {
  local file="$1" body first second
  [ -r "$file" ] || return 1
  body="$(grep -vE '^[[:space:]]*([#;].*)?$' "$file")" || return 1
  first="$(printf '%s\n' "$body" | sed -n 1p | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  second="$(printf '%s\n' "$body" | sed -n 2p | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ "$first" = "[include]" ] || return 1
  [ "$second" = "path = \"$(_git_fragment)\"" ] || return 1
}

# Strip any existing include line pointing at our fragment, in every shape git
# accepts: quoted or bare (an older Atlas wrote it bare via `git config --add`),
# `path=x` or `path = x`, and the inline `[include] path = x` form. The value is
# compared as a literal string, so a path with regex metacharacters is safe.
# `[includeIf …]` is deliberately NOT matched — it is a different section.
# Only ever called on input git has already parsed successfully (see step 4).
_git_strip_include() {
  awk -v frag="$(_git_fragment)" '
    function value(s) {                       # "  path = \"x\" " -> x
      sub(/^[^=]*=[[:space:]]*/, "", s)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      if (s ~ /^".*"$/) s = substr(s, 2, length(s) - 2)
      return s
    }
    # Close the pending section. If our line was the ONLY thing in an [include]
    # section, the now-empty header goes too (with the blank line we wrote after
    # it) — otherwise `remove` would not be a clean revert. A section we did not
    # strip from is always emitted verbatim.
    function endsec(   i, start) {
      start = 1
      if (hdr != "" && stripped && !kept) {
        while (start <= nb && buf[start] ~ /^[[:space:]]*$/) start++
      } else if (hdr != "") {
        print hdr
      }
      for (i = start; i <= nb; i++) print buf[i]
      hdr = ""; nb = 0; stripped = 0; kept = 0
    }
    /^[[:space:]]*\[/ {                       # any section header
      endsec()
      if ($0 ~ /^[[:space:]]*\[[Ii][Nn][Cc][Ll][Uu][Dd][Ee]\][[:space:]]*(path[[:space:]]*=.*)?$/) {
        insec = 1
        rest = $0
        if (sub(/^[[:space:]]*\[[^]]*\][[:space:]]*/, "", rest) && rest != "") {
          if (value(rest) == frag) { stripped = 1; next }   # inline: [include] path = frag
          kept = 1; print; next                             # inline, someone else s
        }
        hdr = $0; next                        # hold: it may end up empty
      }
      insec = 0; print; next                  # [includeIf …] and every other section
    }
    insec {
      if ($0 ~ /^[[:space:]]*path[[:space:]]*=/ && value($0) == frag) { stripped = 1; next }
      if ($0 ~ /^[[:space:]]*([#;].*)?$/) { buf[++nb] = $0; next }   # blank/comment: hold
      kept = 1                                # a real key: the section survives
      if (hdr != "") { print hdr; hdr = "" }
      for (i = 1; i <= nb; i++) print buf[i]
      nb = 0
      print; next
    }
    { print }
    END { endsec() }
  ' "$1"
}

# Rewrite $1 in ONE atomic write (same-dir temp + mv), mode-preserving: the
# include block (when $2 is `with-block`) followed by the original content minus
# any stale include line of ours. A crash leaves the old file untouched, and
# nothing can fail after the file has been modified.
# Caller holds the lock. Returns 1 on failure, never dies.
_git_rewrite_config() {
  local real="$1" block="${2:-}" dir tmp
  dir="$(dirname "$real")"
  tmp="$(mktemp "$dir/.atlas-gitconfig.XXXXXX")" || {
    log::error "cannot create a temp file in $dir"; return 1; }
  if ! {
        if [ "$block" = "with-block" ]; then _git_include_block; fi
        _git_strip_include "$real"
      } > "$tmp"; then
    rm -f "$tmp"; log::error "cannot write $tmp"; return 1
  fi
  chmod --reference="$real" "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$real"; then
    rm -f "$tmp"; log::error "cannot replace $real"; return 1
  fi
}

# Resolve the global config and refuse anything we cannot safely rewrite.
# Sets _GIT_REAL. Dies (exit 4) rather than damage a user-owned file. `$1` is
# the verb quoted back at the user in the "how to fix" line.
# NOTE: this must never be called from inside `$( … )` — `die` calls `exit`,
# which inside a command substitution would only kill the subshell.
_git_guard_config() {
  local verb="$1" target dir
  target="$(_git_config_file)"

  # a symlinked config (chezmoi/stow): edit the target, keep the link
  if [ -L "$target" ]; then
    _GIT_REAL="$(readlink -f "$target" 2>/dev/null || true)"
    [ -n "$_GIT_REAL" ] || die "$ATLAS_EXIT_MODULE" "cannot resolve $target" \
      "it is a symlink whose target directory does not exist" \
      "repair or remove the symlink, then re-run 'atlas $verb git'"
  else
    _GIT_REAL="$target"
  fi

  if [ -e "$_GIT_REAL" ] && [ ! -f "$_GIT_REAL" ]; then
    die "$ATLAS_EXIT_MODULE" "$_GIT_REAL is not a regular file" \
      "Atlas rewrites the global git config in place and will not touch a directory or special file" \
      "move it aside, then re-run 'atlas $verb git'"
  fi
  dir="$(dirname "$_GIT_REAL")"
  [ -d "$dir" ] && [ -w "$dir" ] || die "$ATLAS_EXIT_MODULE" "$dir is not a writable directory" \
    "Atlas writes the new config to a temp file there before renaming it into place" \
    "fix the permissions on $dir, then re-run 'atlas $verb git'"
  if [ -f "$_GIT_REAL" ] && [ ! -w "$_GIT_REAL" ]; then
    die "$ATLAS_EXIT_MODULE" "$_GIT_REAL is not writable" \
      "Atlas must edit the include directive in your global git config" \
      "fix the permissions on $_GIT_REAL, then re-run 'atlas $verb git'"
  fi
  if [ "${EUID:-$(id -u)}" -eq 0 ] && [ -f "$_GIT_REAL" ] && [ ! -O "$_GIT_REAL" ]; then
    die "$ATLAS_EXIT_MODULE" "refusing to rewrite $_GIT_REAL as root" \
      "the file is not owned by root, so rewriting it would change its owner" \
      "run 'atlas $verb git' as the user who owns $_GIT_REAL, without sudo"
  fi
  # never textually edit a file whose semantics git cannot confirm
  if [ -s "$_GIT_REAL" ]; then
    git config --file "$_GIT_REAL" --list >/dev/null 2>&1 || \
      die "$ATLAS_EXIT_MODULE" "git cannot parse $_GIT_REAL" \
        "Atlas will not rewrite a config file it cannot read" \
        "fix the syntax (try 'git config --list'), then re-run 'atlas $verb git'"
  fi
}

# Take git's own lock path, so we cannot race a concurrent `git config`.
# `set -C` makes this fail rather than clobber: we never steal another process's
# lock. Callers must treat this as the LAST thing that may fail before writing.
_git_lock() {
  local verb="$1" lock="$2"
  if ! (set -C; : > "$lock") 2>/dev/null; then
    die "$ATLAS_EXIT_MODULE" "cannot lock ${lock%.lock}" \
      "$lock exists — another git process is writing, or a crash left it behind" \
      "wait for that process, or remove $lock if it is stale, then re-run 'atlas $verb git'"
  fi
}

# Guarantee the Atlas [include] block is the first section of the global config.
_git_ensure_include() {
  local frag real rc
  frag="$(_git_fragment)"
  _git_guard_config install
  real="$_GIT_REAL"

  # missing or empty: just create it — no user content to preserve
  if [ ! -s "$real" ]; then
    _git_include_block > "$real" || { log::error "cannot write $real"; return 1; }
    log::info "created $real with include -> $frag"
    return 0
  fi

  if _git_include_present && _git_include_is_first "$real"; then
    log::info "include.path already at the top of $real"
    return 0
  fi

  _git_lock install "$real.lock"
  # INVARIANT: nothing between here and the `rm -f` below may die() — die() exits
  # and would leak the lock, wedging every later run behind the refusal above.
  # _git_rewrite_config only ever *returns* non-zero. (A `trap … RETURN` here
  # would outlive this function and fire under `set -u` with $lock out of scope.)

  # `A && B` would abort the hook under `set -e` when A is false — use `if`.
  if _git_include_present; then log::info "relocating include.path to the top of $real"; fi
  if _git_rewrite_config "$real" with-block; then rc=0; else rc=1; fi
  rm -f "$real.lock"
  [ "$rc" -eq 0 ] || return 1
  log::info "added include.path -> $frag"
}

# Set user.name / user.email from env/atlas.env, only if currently unset.
# Never fails the install; always returns 0.
_git_apply_identity() {
  local name email
  name="$(env::get ATLAS_GIT_USER_NAME || true)"
  email="$(env::get ATLAS_GIT_USER_EMAIL || true)"
  if [ -z "$name" ] && [ -z "$email" ]; then
    log::warn "git identity not set — export ATLAS_GIT_USER_NAME/EMAIL or add them to ~/.config/atlas/atlas.env"
    return 0
  fi
  if [ -n "$name" ]; then
    if [ -n "$(git config --global --get user.name 2>/dev/null)" ]; then
      log::info "user.name already set — leaving it"
    else
      git config --global user.name "$name" && log::info "set user.name"
    fi
  fi
  if [ -n "$email" ]; then
    if [ -n "$(git config --global --get user.email 2>/dev/null)" ]; then
      log::info "user.email already set — leaving it"
    else
      git config --global user.email "$email" && log::info "set user.email"
    fi
  fi
  return 0
}

# --- required hooks ----------------------------------------------------------

module::check() {
  os::has_cmd git || return 1
  [ -r "$(_git_fragment)" ] || return 1
  _git_include_present || return 1
  # Not merely present — first. An include left at the bottom by an older Atlas
  # would override the user's own settings, and `install` is skipped when check
  # passes, so this is what lets a bad install migrate itself.
  _git_include_is_first "$(_git_config_file)" || return 1
  return 0
}

module::install() {
  # 1. package
  if os::has_cmd git; then
    log::info "git already installed"
  else
    os::dnf_install git || { log::error "failed to install git"; return 1; }
  fi

  # 2. write the Atlas-owned fragment (Atlas owns it -> overwrite is idempotent)
  local frag_dir frag
  frag_dir="$(_git_fragment_dir)"; frag="$(_git_fragment)"
  mkdir -p "$frag_dir" || { log::error "cannot create $frag_dir"; return 1; }
  cp -f "$_GIT_MODULE_DIR/config/gitconfig" "$frag" || { log::error "cannot write $frag"; return 1; }
  log::info "wrote managed git config: $frag"

  # 3. wire the fragment in as the FIRST section, so the user's own settings win
  _git_ensure_include || return 1

  # 4. identity (optional, non-blocking, set-if-unset)
  _git_apply_identity
  return 0
}

# --- optional hooks ----------------------------------------------------------

# Re-apply the latest managed fragment and re-check the include line, so a change
# to Atlas's default set reaches an existing machine. Per RFC-0001 §4.7 this
# deliberately does NOT touch identity and does NOT upgrade the git package.
module::update() {
  os::has_cmd git || { log::error "git is not installed — run 'atlas install git'"; return 1; }
  local frag; frag="$(_git_fragment)"
  mkdir -p "$(_git_fragment_dir)" || { log::error "cannot create $(_git_fragment_dir)"; return 1; }
  cp -f "$_GIT_MODULE_DIR/config/gitconfig" "$frag" || { log::error "cannot write $frag"; return 1; }
  log::info "refreshed managed git config: $frag"
  _git_ensure_include || return 1
  return 0
}

# Drop the include line and delete the Atlas fragment. Per RFC-0001 §4.7 this
# deliberately does NOT uninstall the git package (shared, high blast radius) and
# does NOT touch the user's identity. Safely re-runnable.
module::remove() {
  local frag real rc; frag="$(_git_fragment)"

  if _git_include_present; then
    _git_guard_config remove
    real="$_GIT_REAL"
    _git_lock remove "$real.lock"
    # INVARIANT: no die() between here and the `rm -f` below (see _git_ensure_include).
    if _git_rewrite_config "$real"; then rc=0; else rc=1; fi
    rm -f "$real.lock"
    [ "$rc" -eq 0 ] || return 1
    log::info "removed include.path from $real"
  else
    log::info "no include.path to remove"
  fi

  if [ -e "$frag" ]; then
    rm -f "$frag" || { log::error "cannot delete $frag"; return 1; }
    log::info "deleted managed fragment: $frag"
    rmdir "$(_git_fragment_dir)" 2>/dev/null || true
  fi
  log::info "left the git package and your identity untouched"
  return 0
}

module::verify() {
  os::has_cmd git || { log::error "git not installed"; return 1; }
  git --version >/dev/null 2>&1 || { log::error "git --version failed"; return 1; }
  [ -r "$(_git_fragment)" ] || { log::error "managed fragment missing"; return 1; }
  _git_include_present || { log::error "include.path not wired into $(_git_config_file)"; return 1; }
  _git_include_is_first "$(_git_config_file)" \
    || { log::error "include.path is not the first section — Atlas defaults would override your own settings"; return 1; }
  # Health = "the fragment is intact and resolves", NOT "Atlas's value wins" — a
  # user who overrides a managed key below the include is the point, not a fault.
  # Read the fragment directly: an emptied fragment must fail even if the user
  # happens to set the same key themselves.
  [ "$(git config --file "$(_git_fragment)" --get init.defaultBranch 2>/dev/null)" = "main" ] \
    || { log::error "managed fragment is not intact (init.defaultBranch missing from $(_git_fragment))"; return 1; }
  # …and that git actually resolves it: --get-all lists every value in
  # precedence order, so ours appears even when the user overrides it.
  git config --global --includes --get-all init.defaultBranch 2>/dev/null | grep -qxF "main" \
    || { log::error "managed config not resolving (init.defaultBranch=main absent from $(_git_config_file))"; return 1; }
  return 0
}
