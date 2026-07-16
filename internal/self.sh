#!/usr/bin/env bash
[ -n "${ATLAS_SELF_SH:-}" ] && return 0; ATLAS_SELF_SH=1

readonly ATLAS_SELF_REMOTE="origin"
readonly ATLAS_SELF_REMOTE_IDENTITY="github.com/thiva2k/atlas"
readonly ATLAS_SELF_BRANCH="main"

_self_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/atlas-self"
}

_self_refuse_unmanaged() {
  log::error "Refusing self-update."
  log::error "Repository is not in managed state."
  return 1
}

_self_refuse_executable() {
  log::error "Refusing self-update."
  log::error "Current Atlas executable does not match the managed installation."
  return 1
}

_self_abs_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s\n' "$PWD/$1" ;;
  esac
}

_self_canonical_path() {
  local p="$1" dir base
  [ -e "$p" ] || return 1
  if [ -d "$p" ]; then
    ( cd -P "$p" >/dev/null 2>&1 && pwd ) || return 1
    return 0
  fi
  dir="$(dirname "$p")"
  base="$(basename "$p")"
  dir="$(cd -P "$dir" >/dev/null 2>&1 && pwd)" || return 1
  if command -v readlink >/dev/null 2>&1; then
    local resolved
    resolved="$(readlink -f "$dir/$base" 2>/dev/null)" && [ -n "$resolved" ] && {
      printf '%s\n' "$resolved"
      return 0
    }
  fi
  printf '%s/%s\n' "$dir" "$base"
}

_self_remote_identity_from_url() {
  local url="$1" rest host path
  url="${url%.git}"
  case "$url" in
    git@*:*)
      host="${url#git@}"
      host="${host%%:*}"
      path="${url#*:}"
      printf '%s/%s\n' "$host" "$path"
      ;;
    ssh://*|https://*|http://*)
      rest="${url#*://}"
      rest="${rest#*@}"
      host="${rest%%/*}"
      path="${rest#*/}"
      printf '%s/%s\n' "$host" "$path"
      ;;
    *)
      printf '%s\n' "$url"
      ;;
  esac
}

_self_marker_init() {
  _SELF_MARKER_STATE=absent
  _SELF_MARKER_SOURCE=
  _SELF_MARKER_PATH=
  _SELF_MARKER_REMOTE=
  _SELF_MARKER_REMOTE_IDENTITY=
  _SELF_MARKER_BRANCH=
  _SELF_MARKER_REF=
  _SELF_MARKER_EXECUTABLE=
  _SELF_MARKER_LAUNCHER=
}

_self_marker_load() {
  _self_marker_init
  local marker dir line key val
  local seen_schema=0 seen_state=0 seen_source=0 seen_path=0 seen_remote=0
  local seen_remote_identity=0 seen_branch=0 seen_ref=0 seen_executable=0 seen_launcher=0
  marker="$(_self_marker)"
  [ -e "$marker" ] || return 1
  dir="$(dirname "$marker")"
  [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
  [ "$(stat -c '%a' "$dir" 2>/dev/null)" = "700" ] || return 1
  [ -f "$marker" ] && [ ! -L "$marker" ] && [ -r "$marker" ] || return 1
  [ "$(stat -c '%a' "$marker" 2>/dev/null)" = "600" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$seen_schema" -eq 0 ] && [ "$val" = "1" ] || return 1
        seen_schema=1
        ;;
      state)
        [ "$seen_state" -eq 0 ] && [ "$val" = "installed" ] || return 1
        _SELF_MARKER_STATE="$val"; seen_state=1
        ;;
      source)
        [ "$seen_source" -eq 0 ] && [ "$val" = "git" ] || return 1
        _SELF_MARKER_SOURCE="$val"; seen_source=1
        ;;
      path)
        [ "$seen_path" -eq 0 ] && case "$val" in /*) true ;; *) false ;; esac || return 1
        _SELF_MARKER_PATH="$val"; seen_path=1
        ;;
      remote)
        [ "$seen_remote" -eq 0 ] && [ "$val" = "$ATLAS_SELF_REMOTE" ] || return 1
        _SELF_MARKER_REMOTE="$val"; seen_remote=1
        ;;
      remote_identity)
        [ "$seen_remote_identity" -eq 0 ] && [ "$val" = "$ATLAS_SELF_REMOTE_IDENTITY" ] || return 1
        _SELF_MARKER_REMOTE_IDENTITY="$val"; seen_remote_identity=1
        ;;
      branch)
        [ "$seen_branch" -eq 0 ] && [ "$val" = "$ATLAS_SELF_BRANCH" ] || return 1
        _SELF_MARKER_BRANCH="$val"; seen_branch=1
        ;;
      ref)
        [ "$seen_ref" -eq 0 ] && [ "$val" = "refs/heads/$ATLAS_SELF_BRANCH" ] || return 1
        _SELF_MARKER_REF="$val"; seen_ref=1
        ;;
      executable)
        [ "$seen_executable" -eq 0 ] && case "$val" in /*) true ;; *) false ;; esac || return 1
        _SELF_MARKER_EXECUTABLE="$val"; seen_executable=1
        ;;
      launcher)
        [ "$seen_launcher" -eq 0 ] && case "$val" in ""|/*) true ;; *) false ;; esac || return 1
        _SELF_MARKER_LAUNCHER="$val"; seen_launcher=1
        ;;
      *)
        return 1
        ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || return 1
  [ "$seen_state" -eq 1 ] || return 1
  [ "$seen_source" -eq 1 ] || return 1
  [ "$seen_path" -eq 1 ] || return 1
  [ "$seen_remote" -eq 1 ] || return 1
  [ "$seen_remote_identity" -eq 1 ] || return 1
  [ "$seen_branch" -eq 1 ] || return 1
  [ "$seen_ref" -eq 1 ] || return 1
  [ "$seen_executable" -eq 1 ] || return 1
  return 0
}

_self_current_executable_matches() {
  local current marker_current marker_launcher
  current="${ATLAS_EXECUTABLE_PATH:-}"
  [ -n "$current" ] || current="$(command -v "${PROGRAM_NAME:-atlas}" 2>/dev/null)" || return 1
  current="$(_self_abs_path "$current")"
  current="$(_self_canonical_path "$current")" || return 1
  marker_current="$(_self_canonical_path "$_SELF_MARKER_EXECUTABLE")" || return 1
  [ "$current" = "$marker_current" ] && return 0
  if [ -n "$_SELF_MARKER_LAUNCHER" ]; then
    marker_launcher="$(_self_canonical_path "$_SELF_MARKER_LAUNCHER")" || return 1
    [ "$current" = "$marker_launcher" ] && return 0
  fi
  return 1
}

_self_validate_preflight() {
  _self_marker_load || return 1
  _self_current_executable_matches || return 2

  local marker_root atlas_root git_root remote_url remote_identity branch status_out
  marker_root="$(_self_canonical_path "$_SELF_MARKER_PATH")" || return 1
  atlas_root="$(_self_canonical_path "$ATLAS_ROOT")" || return 1
  [ "$marker_root" = "$atlas_root" ] || return 1

  git_root="$(git -C "$_SELF_MARKER_PATH" rev-parse --show-toplevel 2>/dev/null)" || return 1
  git_root="$(_self_canonical_path "$git_root")" || return 1
  [ "$git_root" = "$marker_root" ] || return 1

  remote_url="$(git -C "$_SELF_MARKER_PATH" remote get-url "$ATLAS_SELF_REMOTE" 2>/dev/null)" || return 1
  remote_identity="$(_self_remote_identity_from_url "$remote_url")"
  [ "$remote_identity" = "$ATLAS_SELF_REMOTE_IDENTITY" ] || return 1

  branch="$(git -C "$_SELF_MARKER_PATH" symbolic-ref --short HEAD 2>/dev/null)" || return 1
  [ "$branch" = "$ATLAS_SELF_BRANCH" ] || return 1

  status_out="$(git -C "$_SELF_MARKER_PATH" status --porcelain=v1 --untracked-files=normal 2>/dev/null)" || return 1
  [ -z "$status_out" ] || return 1
  return 0
}

_self_fast_forward() {
  git -C "$_SELF_MARKER_PATH" fetch "$ATLAS_SELF_REMOTE" >/dev/null 2>&1 || return 1
  git -C "$_SELF_MARKER_PATH" rev-parse --verify "refs/remotes/$ATLAS_SELF_REMOTE/$ATLAS_SELF_BRANCH" >/dev/null 2>&1 || return 1
  git -C "$_SELF_MARKER_PATH" merge-base --is-ancestor HEAD "$ATLAS_SELF_REMOTE/$ATLAS_SELF_BRANCH" >/dev/null 2>&1 || return 1
  git -C "$_SELF_MARKER_PATH" merge --ff-only "$ATLAS_SELF_REMOTE/$ATLAS_SELF_BRANCH" >/dev/null 2>&1 || return 1
}

_self_validate_shell() {
  local f
  bash -n "$_SELF_MARKER_PATH/atlasctl" || return 1
  for f in "$_SELF_MARKER_PATH"/internal/*.sh; do
    [ -e "$f" ] || continue
    bash -n "$f" || return 1
  done
  while IFS= read -r f; do
    bash -n "$f" || return 1
  done < <(find "$_SELF_MARKER_PATH/modules" -name '*.sh' -type f | sort)
}

_self_post_update_validate() {
  _self_validate_shell || { log::error "self-update validation failed: shell syntax"; return 1; }
  "$_SELF_MARKER_EXECUTABLE" version >/dev/null || { log::error "self-update validation failed: atlas version"; return 1; }
  "$_SELF_MARKER_EXECUTABLE" help >/dev/null || { log::error "self-update validation failed: atlas help"; return 1; }
  log::info "${PROGRAM_NAME:-atlas} status"
  "$_SELF_MARKER_EXECUTABLE" status >/dev/null || { log::error "self-update validation failed: atlas status"; return 1; }
}

_self_full_test() {
  log::info "running full Atlas test suite"
  bash "$_SELF_MARKER_PATH/tests/run.sh" || return 1
}

self::usage() {
  cat <<EOF
Usage: ${PROGRAM_NAME:-atlas} self-update [--verify|--full-test]

Updates the managed Atlas checkout with a fast-forward-only Git update.

Options:
      --verify     run the full test suite after the default validation
      --full-test  alias for --verify
      --help       show this help
EOF
}

self::version() {
  [ "$#" -eq 0 ] || die "$ATLAS_EXIT_USAGE" "self-version takes no arguments" "" "run '${PROGRAM_NAME:-atlas} self-version'"
  printf '%s\n' "$ATLAS_VERSION"
}

self::verify() {
  [ "$#" -eq 0 ] || die "$ATLAS_EXIT_USAGE" "self-verify takes no arguments" "" "run '${PROGRAM_NAME:-atlas} self-verify'"
  local preflight_rc
  _self_validate_preflight
  preflight_rc=$?
  case "$preflight_rc" in
    0) ;;
    2) _self_refuse_executable; return 1 ;;
    *) _self_refuse_unmanaged; return 1 ;;
  esac
  _self_post_update_validate || return 1
  log::info "Atlas self-management is healthy"
}

self::update() {
  local full_test=0 arg
  for arg in "$@"; do
    case "$arg" in
      --help) self::usage; return 0 ;;
      --verify|--full-test) full_test=1 ;;
      *) die "$ATLAS_EXIT_USAGE" "unknown self-update option: $arg" "" "run '${PROGRAM_NAME:-atlas} self-update --help'" ;;
    esac
  done

  local preflight_rc
  _self_validate_preflight
  preflight_rc=$?
  case "$preflight_rc" in
    0) ;;
    2) _self_refuse_executable; return 1 ;;
    *) _self_refuse_unmanaged; return 1 ;;
  esac

  if ! _self_fast_forward; then
    _self_refuse_unmanaged
    return 1
  fi

  _self_post_update_validate || return 1
  if [ "$full_test" -eq 1 ]; then
    _self_full_test || return 1
  fi
  log::info "Atlas self-update complete"
}
