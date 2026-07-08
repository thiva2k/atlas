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

# --- placeholder installers (real logic lands with the modules that need them) ---
os::dnf_install()     { log::info "would dnf install: $*"; }
os::flatpak_install() { log::info "would flatpak install: $*"; }
