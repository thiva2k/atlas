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

# True if our fragment path is already an include.path in ~/.gitconfig.
_git_include_present() {
  git config --global --get-all include.path 2>/dev/null \
    | grep -qxF "$(_git_fragment)"
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

  # 3. ensure exactly one include.path line
  if _git_include_present; then
    log::info "include.path already present"
  else
    git config --global --add include.path "$frag" || { log::error "cannot add include.path"; return 1; }
    log::info "added include.path -> $frag"
  fi

  # 4. identity (optional, non-blocking, set-if-unset)
  _git_apply_identity
  return 0
}

module::verify() {
  os::has_cmd git || { log::error "git not installed"; return 1; }
  git --version >/dev/null 2>&1 || { log::error "git --version failed"; return 1; }
  [ -r "$(_git_fragment)" ] || { log::error "managed fragment missing"; return 1; }
  _git_include_present || { log::error "include.path not wired into ~/.gitconfig"; return 1; }
  [ "$(git config --global --includes --get init.defaultBranch 2>/dev/null)" = "main" ] \
    || { log::error "managed config not effective (init.defaultBranch != main)"; return 1; }
  return 0
}
