#!/usr/bin/env bash
[ -n "${ATLAS_OS_SH:-}" ] && return 0; ATLAS_OS_SH=1

os::has_cmd() { command -v "$1" >/dev/null 2>&1; }

# --- RPM query cache (RFC-0028) ----------------------------------------------
# Memoises `rpm -q` presence for the life of the module subshell the runner
# spawns. Inherently per-invocation and per-module (a subshell cannot outlive the
# atlas process; a `( … )` inherits only a copy of this map). Populated ONLY
# inside module subshells — never from the atlas parent process, or a stale entry
# would be inherited by every later module subshell.
declare -gA _OS_PKG_INSTALLED=()   # pkg name -> "0" installed / "1" not

# Is an RPM package installed? Same exit-code contract as `rpm -q "$1" >/dev/null`.
os::pkg_installed() {
  local pkg="$1"
  if [ -z "${_OS_PKG_INSTALLED[$pkg]+x}" ]; then
    local rc=0; rpm -q "$pkg" >/dev/null 2>&1 || rc=1
    _OS_PKG_INSTALLED[$pkg]="$rc"
  fi
  return "${_OS_PKG_INSTALLED[$pkg]}"
}

# Which package owns a path? Prints the owning package (empty when unowned) and
# returns 0 iff owned — the contract callers use via `o="$(os::pkg_owner "$p")"`.
# NOT memoised: callers invoke it in command substitution, whose child subshell
# would discard any cache write (RFC-0028 §5.4).
os::pkg_owner() {
  local owner; owner="$(rpm -qf "$1" 2>/dev/null)" || owner=""
  printf '%s\n' "$owner"
  [ -n "$owner" ]
}

# Drop the presence cache. Called after any package-state mutation.
os::pkg_cache_flush() { _OS_PKG_INSTALLED=(); }

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
  local rc=0
  $sudo dnf install -y "$@" || rc=1
  # Packages may have changed even when dnf exits non-zero (e.g. a post-
  # transaction scriptlet fails after the packages are on disk), so flush the
  # presence cache unconditionally, before evaluating rc (RFC-0028 §5.2).
  os::pkg_cache_flush
  if [ "$rc" -ne 0 ]; then
    log::error "dnf install failed: $*"
    return 1
  fi
}

# flatpak install placeholder (promoted when the first flatpak module lands).
os::flatpak_install() { log::info "would flatpak install: $*"; }
