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
    /^[[:space:]]*\[/ {                       # any section header
      insec = ($0 ~ /^[[:space:]]*\[[Ii][Nn][Cc][Ll][Uu][Dd][Ee]\][[:space:]]*(path[[:space:]]*=.*)?$/)
      if (insec) {
        rest = $0
        if (sub(/^[[:space:]]*\[[^]]*\][[:space:]]*/, "", rest) && rest != "" &&
            value(rest) == frag) next         # inline: [include] path = frag
      }
      print; next
    }
    insec && $0 ~ /^[[:space:]]*path[[:space:]]*=/ { if (value($0) == frag) next }
    { print }
  ' "$1"
}

# Rewrite $1 as: include block + original content minus any stale include line.
# ONE atomic write (same-dir temp + mv), mode-preserving, so a crash leaves the
# old file untouched and nothing can fail after the file has been modified.
# Caller holds the lock. Returns 1 on failure, never dies.
_git_prepend_include() {
  local real="$1" dir tmp
  dir="$(dirname "$real")"
  tmp="$(mktemp "$dir/.atlas-gitconfig.XXXXXX")" || {
    log::error "cannot create a temp file in $dir"; return 1; }
  if ! { _git_include_block; _git_strip_include "$real"; } > "$tmp"; then
    rm -f "$tmp"; log::error "cannot write $tmp"; return 1
  fi
  chmod --reference="$real" "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$real"; then
    rm -f "$tmp"; log::error "cannot replace $real"; return 1
  fi
}

# Guarantee the Atlas [include] block is the first section of the global config.
# Dies (exit 4) rather than touch a config it cannot safely rewrite.
_git_ensure_include() {
  local frag target real dir lock rc
  frag="$(_git_fragment)"
  target="$(_git_config_file)"

  # 1. resolve a symlinked config (chezmoi/stow): edit the target, keep the link
  if [ -L "$target" ]; then
    real="$(readlink -f "$target" 2>/dev/null || true)"
    [ -n "$real" ] || die "$ATLAS_EXIT_MODULE" "cannot resolve $target" \
      "it is a symlink whose target directory does not exist" \
      "repair or remove the symlink, then re-run 'atlas install git'"
  else
    real="$target"
  fi

  # 2. refuse anything we cannot safely rewrite
  if [ -e "$real" ] && [ ! -f "$real" ]; then
    die "$ATLAS_EXIT_MODULE" "$real is not a regular file" \
      "Atlas rewrites the global git config in place and will not touch a directory or special file" \
      "move it aside, then re-run 'atlas install git'"
  fi
  dir="$(dirname "$real")"
  [ -d "$dir" ] && [ -w "$dir" ] || die "$ATLAS_EXIT_MODULE" "$dir is not a writable directory" \
    "Atlas writes the new config to a temp file there before renaming it into place" \
    "fix the permissions on $dir, then re-run 'atlas install git'"
  if [ -f "$real" ] && [ ! -w "$real" ]; then
    die "$ATLAS_EXIT_MODULE" "$real is not writable" \
      "Atlas must add its include directive to your global git config" \
      "fix the permissions on $real, then re-run 'atlas install git'"
  fi
  if [ "${EUID:-$(id -u)}" -eq 0 ] && [ -f "$real" ] && [ ! -O "$real" ]; then
    die "$ATLAS_EXIT_MODULE" "refusing to rewrite $real as root" \
      "the file is not owned by root, so rewriting it would change its owner" \
      "run 'atlas install git' as the user who owns $real, without sudo"
  fi

  # 3. missing or empty: just create it — no user content to preserve
  if [ ! -s "$real" ]; then
    _git_include_block > "$real" || { log::error "cannot write $real"; return 1; }
    log::info "created $real with include -> $frag"
    return 0
  fi

  # 4. never textually edit a file whose semantics git cannot confirm
  git config --file "$real" --list >/dev/null 2>&1 || \
    die "$ATLAS_EXIT_MODULE" "git cannot parse $real" \
      "Atlas will not rewrite a config file it cannot read" \
      "fix the syntax (try 'git config --list'), then re-run 'atlas install git'"

  # 5. already correct
  if _git_include_present && _git_include_is_first "$real"; then
    log::info "include.path already at the top of $real"
    return 0
  fi

  # 6. take git's own lock path, so we cannot race a concurrent `git config`.
  # `set -C` makes this fail rather than clobber: we never steal another
  # process's lock. This is the LAST thing that can fail before we write.
  lock="$real.lock"
  if ! (set -C; : > "$lock") 2>/dev/null; then
    die "$ATLAS_EXIT_MODULE" "cannot lock $real" \
      "$lock exists — another git process is writing, or a crash left it behind" \
      "wait for that process, or remove $lock if it is stale, then re-run 'atlas install git'"
  fi
  # INVARIANT: nothing between here and the `rm -f "$lock"` below may die() —
  # die() exits and would leak the lock, wedging every later run behind the
  # refusal above. _git_prepend_include only ever *returns* non-zero.
  # (A `trap … RETURN` here would outlive this function and fire under `set -u`
  # with $lock out of scope; don't.)

  # 7. one atomic rewrite: prepend our block, drop any stale include line
  # `A && B` would abort the hook under `set -e` when A is false — use `if`.
  if _git_include_present; then log::info "relocating include.path to the top of $real"; fi
  if _git_prepend_include "$real"; then rc=0; else rc=1; fi
  rm -f "$lock"
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
