#!/usr/bin/env bash
[ -n "${ATLAS_ENV_SH:-}" ] && return 0; ATLAS_ENV_SH=1

: "${ATLAS_CONFIG_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/atlas}"

# env::get <NAME> — echo the user-supplied value of NAME.
# Resolution order: environment variable NAME, then NAME=value in atlas.env.
# Prints nothing and returns 1 if NAME is set in neither.
env::get() {
  local name="$1"
  if [ -n "${!name:-}" ]; then
    printf '%s\n' "${!name}"
    return 0
  fi
  local file="${ATLAS_CONFIG_HOME}/atlas.env"
  [ -r "$file" ] || return 1
  local line val=""
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    case "$line" in
      \#*) continue ;;
      "$name="*) val="${line#*=}" ;;
    esac
  done < "$file"
  [ -n "$val" ] || return 1
  # strip one layer of surrounding double or single quotes
  val="${val%\"}"; val="${val#\"}"
  val="${val%\'}"; val="${val#\'}"
  printf '%s\n' "$val"
}
