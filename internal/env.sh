#!/usr/bin/env bash
[ -n "${ATLAS_ENV_SH:-}" ] && return 0; ATLAS_ENV_SH=1

: "${ATLAS_CONFIG_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/atlas}"

# env::get <NAME> — echo the user-supplied value of NAME.
# Resolution order: environment variable NAME, then NAME=value in atlas.env.
# Prints nothing and returns 1 if NAME is set in neither.
#
# xtrace is disabled for the body and restored on return. This is not about
# NAME's own value: atlas.env holds the user's *secrets* alongside their
# preferences, and the read loop below walks every line of the file. Under an
# operator's `bash -x`, tracing `line=ATLAS_GH_TOKEN=ghp_…` would leak a
# credential during a lookup of something else entirely.
env::get() {
  local name="$1" restore_xtrace=0
  case "$-" in *x*) restore_xtrace=1; set +x ;; esac

  local rc=0 out=""
  if [ -n "${!name:-}" ]; then
    out="${!name}"
  else
    local file="${ATLAS_CONFIG_HOME}/atlas.env"
    if [ ! -r "$file" ]; then
      rc=1
    else
      local line val=""
      while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"          # atlas.env may have been written on Windows
        [ -z "$line" ] && continue
        case "$line" in
          \#*) continue ;;
          "$name="*) val="${line#*=}" ;;
        esac
      done < "$file"
      if [ -n "$val" ]; then
        # strip one layer of surrounding double or single quotes
        val="${val%\"}"; val="${val#\"}"
        val="${val%\'}"; val="${val#\'}"
        out="$val"
      else
        rc=1
      fi
    fi
  fi

  # An `A && B` statement would itself return non-zero when rc != 0, tripping a
  # caller's `set -e` before the restore below could run.
  if [ "$rc" -eq 0 ]; then printf '%s\n' "$out"; fi
  if [ "$restore_xtrace" -eq 1 ]; then set -x; fi
  return "$rc"
}

# env::get_secret <NAME> — env::get, hardened for credentials (RFC-0003 §4.5).
#
# Differences from env::get, all of them deliberate:
#   * xtrace is disabled for the body and restored on return, so a caller running
#     under `set -x` cannot leak the value to stderr.
#   * A secret is never consumed from a group- or world-readable atlas.env. The
#     value is treated as absent and the user is told how to fix the mode: Atlas
#     refuses to make an already-leaked credential load-bearing.
#   * If the file's mode cannot be determined, the secret is refused. Fail closed.
#
# A value taken from the environment is not mode-checked — the environment is the
# caller's problem. The value goes to stdout and nowhere else; nothing here may
# log it. Prints nothing and returns 1 if NAME cannot be resolved.
env::get_secret() {
  local name="$1" restore_xtrace=0
  case "$-" in *x*) restore_xtrace=1; set +x ;; esac

  local val="" rc=0
  if [ -n "${!name:-}" ]; then
    val="${!name}"
  else
    local file="${ATLAS_CONFIG_HOME}/atlas.env"
    if [ ! -r "$file" ]; then
      rc=1
    else
      # -L: judge the target of a symlink, not the link itself.
      local mode=""
      mode="$(stat -Lc '%a' "$file" 2>/dev/null)" || mode=""
      if [ -z "$mode" ]; then
        log::warn "refusing to read $name from $file: cannot determine its permissions"
        rc=1
      elif [ "$(( 8#$mode & 8#077 ))" -ne 0 ]; then
        log::warn "refusing to read $name from $file: it is group- or world-readable"
        log::warn "  fix: chmod 600 $file"
        rc=1
      else
        val="$(env::get "$name")" || rc=1
      fi
    fi
  fi

  if [ "$rc" -eq 0 ] && [ -n "$val" ]; then
    printf '%s\n' "$val"
  else
    rc=1
  fi

  if [ "$restore_xtrace" -eq 1 ]; then set -x; fi
  return "$rc"
}
