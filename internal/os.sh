#!/usr/bin/env bash
[ -n "${ATLAS_OS_SH:-}" ] && return 0; ATLAS_OS_SH=1

os::has_cmd() { command -v "$1" >/dev/null 2>&1; }

os::require_cmd() {
  os::has_cmd "$1" && return 0
  die "$ATLAS_EXIT_UNSUPPORTED" \
    "required command not found: $1" \
    "Atlas needs '$1' on PATH to continue" \
    "install '$1' and re-run"
}

os::is_fedora() {
  [ -r /etc/os-release ] || return 1
  grep -qi '^ID=fedora$' /etc/os-release
}

os::is_root() { [ "$(id -u)" -eq 0 ]; }

# Install one or more packages via dnf. Idempotent (dnf is a no-op for
# already-installed packages). Uses sudo only when not already root.
os::dnf_install() {
  [ "$#" -gt 0 ] || return 0
  os::require_cmd dnf
  local sudo=""
  os::is_root || sudo="sudo"
  log::info "installing packages: $*"
  if ! $sudo dnf install -y "$@"; then
    log::error "dnf install failed: $*"
    return 1
  fi
}

# flatpak install placeholder (promoted when the first flatpak module lands).
os::flatpak_install() { log::info "would flatpak install: $*"; }
