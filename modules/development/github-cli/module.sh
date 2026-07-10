#!/usr/bin/env bash
# development/github-cli — GitHub's official CLI.
# Design: docs/rfcs/RFC-0003-github-cli-module.md
#
# Atlas owns NO gh configuration (§4.6): this module installs the package and,
# when the user supplied a token out of band, authenticates once. It never runs
# `gh config`, never reads or creates config.yml, and never runs
# `gh auth setup-git` — that would edit core/git's owned file (§4.7).

MODULE_NAME="github-cli"
MODULE_DESCRIPTION="GitHub's official CLI: installs gh and authenticates it non-interactively."
MODULE_DEPENDS=("core/git")

# gh's own token variables. When either is exported, gh authenticates from it and
# `gh auth login --with-token` *refuses to run* (§6.1) — so an exported token is
# deferred to, never overridden.
# Prints the variable's NAME, never its value. Returns 1 when neither is set.
_gh_env_token_var() {
  if [ -n "${GH_TOKEN:-}" ]; then printf 'GH_TOKEN\n'; return 0; fi
  if [ -n "${GITHUB_TOKEN:-}" ]; then printf 'GITHUB_TOKEN\n'; return 0; fi
  return 1
}

# `gh auth token` PRINTS THE TOKEN on stdout. It is used here only as an offline
# predicate, and its output must never be captured. Do not "improve" this into a
# command substitution. `gh auth status` is not an alternative: its exit code is
# not stable across gh versions (§6.1).
_gh_authenticated() { gh auth token >/dev/null 2>&1; }

_gh_authenticate() {
  local var
  if var="$(_gh_env_token_var)"; then
    log::info "gh is authenticated from \$$var in the environment"
    log::info "  note: that credential is ephemeral — it dies with this shell"
    return 0
  fi

  if _gh_authenticated; then
    log::info "gh is already authenticated — leaving the credential untouched"
    return 0
  fi

  local token
  if ! token="$(env::get_secret ATLAS_GH_TOKEN)"; then
    log::warn "gh is installed but not authenticated, and no ATLAS_GH_TOKEN was supplied"
    log::warn "  fix: run 'gh auth login' — Atlas will never prompt you for a credential"
    return 0
  fi

  log::info "authenticating gh from ATLAS_GH_TOKEN"
  # printf is a shell builtin, so the token never becomes a process argument and
  # never appears in /proc/*/cmdline. gh reads it from stdin.
  if ! printf '%s' "$token" | gh auth login --with-token; then
    log::error "gh did not accept the supplied token"
    log::error "  why: the token was rejected, or GitHub was unreachable — gh validates over the network and the two are indistinguishable"
    log::error "  fix: check ATLAS_GH_TOKEN's value and scopes, then re-run 'atlas install development/github-cli'"
    return 1
  fi
  log::info "gh authenticated"
}

module::check() {
  os::has_cmd gh || return 1
  # If a token is resolvable and gh is logged out, install has work to do, so
  # check must fail: the runner skips install entirely whenever check passes.
  # Nothing about gh's configuration is asserted — Atlas owns none of it.
  if ! _gh_authenticated && env::get_secret ATLAS_GH_TOKEN >/dev/null; then
    return 1
  fi
  return 0
}

module::install() {
  os::has_cmd gh || os::dnf_install gh || return 1
  _gh_authenticate
}

module::verify() {
  if ! gh --version >/dev/null 2>&1; then
    log::error "gh is not runnable"
    log::error "  fix: run 'atlas install development/github-cli'"
    return 1
  fi

  # Auth state is reported, never enforced: only the user can grant gh access.
  local var
  if var="$(_gh_env_token_var)"; then
    log::info "gh is authenticated from \$$var (ephemeral — it dies with this shell)"
  elif _gh_authenticated; then
    log::info "gh is authenticated"
  else
    log::warn "gh is installed but not authenticated — run 'gh auth login'"
  fi
  return 0
}

module::update() {
  log::info "nothing to update: package currency is dnf's job, Atlas owns no gh configuration, and auth is user-granted"
  return 0
}

# No `remove` hook, deliberately (§4.8): Atlas wrote no file it owns, and must
# not delete a credential the user granted, a config.yml it never authored, or a
# package other tools depend on. The runner skips a hook a module does not define.

module::backup() {
  log::info "nothing to back up: gh's only state is a live OAuth token in hosts.yml (regenerable — never copied) and config.yml, which Atlas does not own"
  return 0
}

module::restore() {
  log::info "nothing to restore: this module backs nothing up"
  return 0
}
