#!/usr/bin/env bash
# development/starship - RFC-0011.
#
# Atlas owns an isolated Starship prompt config. It does not install Starship,
# activate shell integration, or edit user-owned Starship/shell configuration.
MODULE_NAME="starship"
MODULE_DESCRIPTION="Starship prompt theme: installs Atlas's engineering-focused prompt config."
MODULE_DEPENDS=()

_STARSHIP_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_starship_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-starship"
}

_starship_config_dir() {
  printf '%s\n' "${ATLAS_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/atlas}/starship"
}

_starship_config_file() { printf '%s\n' "$(_starship_config_dir)/starship.toml"; }
_starship_config_source() { printf '%s\n' "$_STARSHIP_MODULE_DIR/config/starship.toml"; }
_starship_user_config_file() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"; }
_starship_binary() { printf '%s\n' starship; }
_starship_sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

_starship_marker_init() {
  _STARSHIP_MARKER_STATE=absent
  _STARSHIP_MARKER_CONFIG_PATH=
  _STARSHIP_MARKER_CONFIG_SHA=
}

_starship_hash_valid() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in *[!0-9a-f]*|"") return 1 ;; *) return 0 ;; esac
}

_starship_marker_load() {
  _starship_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_config=0 seen_sha=0
  marker="$(_starship_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Starship marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Starship marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Starship marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Starship marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Starship marker schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          installing|installed|detached) _STARSHIP_MARKER_STATE="$val" ;;
          *) log::error "Starship marker state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      config_path) _STARSHIP_MARKER_CONFIG_PATH="$val"; seen_config=1 ;;
      config_sha256) _STARSHIP_MARKER_CONFIG_SHA="$val"; seen_sha=1 ;;
      *) log::error "Starship marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Starship marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Starship marker is missing state"; return 1; }
  [ "$seen_config" -eq 1 ] || { log::error "Starship marker is missing config_path"; return 1; }
  [ "$seen_sha" -eq 1 ] || { log::error "Starship marker is missing config_sha256"; return 1; }
  [ "$_STARSHIP_MARKER_CONFIG_PATH" = "$(_starship_config_file)" ] || {
    log::error "Starship marker config_path does not match this environment"; return 1; }
  _starship_hash_valid "$_STARSHIP_MARKER_CONFIG_SHA" || {
    log::error "Starship marker config_sha256 is invalid"; return 1; }
}

_starship_marker_write() {
  local state="$1" marker dir tmp config_sha
  marker="$(_starship_marker)"
  dir="$(dirname "$marker")"
  config_sha="$(_starship_sha256 "$(_starship_config_source)")"
  [ -n "$config_sha" ] || { log::error "cannot hash Starship config source"; return 1; }
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-starship.XXXXXX")" || {
    log::error "cannot create a Starship marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'config_path=%s\n' "$(_starship_config_file)"
    printf 'config_sha256=%s\n' "$config_sha"
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_starship_config_matches_source() {
  local dest="$(_starship_config_file)" src="$(_starship_config_source)"
  [ -f "$dest" ] || return 1
  [ ! -L "$dest" ] || return 1
  [ "$(_starship_sha256 "$dest")" = "$(_starship_sha256 "$src")" ]
}

_starship_write_config() {
  local src dest dir tmp
  src="$(_starship_config_source)"
  dest="$(_starship_config_file)"
  [ -r "$src" ] || { log::error "Starship config source missing: $src"; return 1; }
  if [ -L "$dest" ] || { [ -e "$dest" ] && [ ! -f "$dest" ]; }; then
    log::error "Starship managed config is not a regular file: $dest"
    return 1
  fi
  if _starship_config_matches_source; then
    log::info "Starship config already matches Atlas source"
    return 0
  fi
  dir="$(dirname "$dest")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.starship.toml.XXXXXX")" || {
    log::error "cannot create Starship config temp file in $dir"; return 1; }
  cp "$src" "$tmp" || { rm -f "$tmp"; log::error "cannot stage $dest"; return 1; }
  chmod 644 "$tmp" || { rm -f "$tmp"; log::error "cannot chmod $tmp"; return 1; }
  mv -f "$tmp" "$dest" || { rm -f "$tmp"; log::error "cannot replace $dest"; return 1; }
}

_starship_validate_if_present() {
  if ! os::has_cmd starship; then
    log::warn "Starship binary is not present; Atlas installed only the prompt config"
    return 0
  fi
  STARSHIP_CONFIG="$(_starship_config_file)" "$(_starship_binary)" prompt >/dev/null 2>&1 || {
    log::error "Starship rejected the Atlas prompt config"; return 1; }
}

_starship_unmanaged_present() {
  os::has_cmd starship && return 0
  return 1
}

_starship_preflight_absent() {
  if [ -e "$(_starship_config_file)" ] || [ -L "$(_starship_config_file)" ]; then
    log::error "Starship Atlas config already exists and is not Atlas-owned: $(_starship_config_file)"
    log::error "  fix: move or remove it before Atlas manages development/starship"
    return 1
  fi
  return 0
}

_starship_preflight_detached() {
  if [ -e "$(_starship_config_file)" ] || [ -L "$(_starship_config_file)" ]; then
    log::error "Starship Atlas config exists while development/starship is detached: $(_starship_config_file)"
    log::error "  fix: move or remove it before re-enrolling development/starship"
    return 1
  fi
}

module::check() {
  _starship_marker_load || return 1
  [ "$_STARSHIP_MARKER_STATE" = "installed" ] || return 1
  _starship_config_matches_source || return 1
}

module::install() {
  os::is_fedora || { log::error "development/starship supports Fedora only"; return 1; }
  _starship_marker_load || return 1
  case "$_STARSHIP_MARKER_STATE" in
    absent) _starship_preflight_absent || return 1 ;;
    detached) _starship_preflight_detached || return 1 ;;
    installing|installed) ;;
  esac
  _starship_marker_write installing || return 1
  _starship_write_config || return 1
  _starship_validate_if_present || return 1
  _starship_marker_write installed || return 1
  log::info "Starship prompt config is installed"
}

module::verify() {
  _starship_marker_load || return 1
  case "$_STARSHIP_MARKER_STATE" in
    absent)
      if _starship_unmanaged_present; then
        log::info "Starship is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "development/starship is not installed by Atlas"
      fi
      return 0
      ;;
    detached)
      log::warn "development/starship is detached; Atlas is not asserting prompt config"
      return 0
      ;;
    installing)
      log::error "development/starship install is incomplete; rerun 'atlas install development/starship'"
      return 1
      ;;
  esac
  _starship_config_matches_source || { log::error "Starship managed config is missing or drifted"; return 1; }
  _starship_validate_if_present || return 1
  log::info "Starship prompt config is healthy"
}

module::update() {
  _starship_marker_load || return 1
  case "$_STARSHIP_MARKER_STATE" in
    absent|detached)
      log::info "development/starship is not actively managed by Atlas; nothing to update"
      return 0
      ;;
    installing|installed) ;;
  esac
  _starship_write_config || return 1
  _starship_validate_if_present || return 1
  _starship_marker_write installed || return 1
}

module::remove() {
  _starship_marker_load || return 1
  case "$_STARSHIP_MARKER_STATE" in
    absent)
      log::info "development/starship is not installed by Atlas; nothing to detach"
      return 0
      ;;
    detached)
      log::info "development/starship is already detached from Atlas"
      return 0
      ;;
  esac
  _starship_config_matches_source || {
    log::error "refusing to remove drifted Starship config"; return 1; }
  rm -f "$(_starship_config_file)" || { log::error "cannot remove $(_starship_config_file)"; return 1; }
  rmdir "$(_starship_config_dir)" 2>/dev/null || true
  _starship_marker_write detached || return 1
  log::info "detached development/starship without touching user prompt or shell config"
}

module::backup() {
  log::info "nothing to back up: development/starship config is reconstructable from Atlas"
}

module::restore() {
  log::info "nothing to restore: reinstall development/starship to reconstruct Atlas-owned prompt config"
}

# --- RFC-0031 activation --------------------------------------------------------
# Reversible, opt-in wiring of the Atlas Starship prompt into interactive fish.
# Owns exactly one snippet (conf.d/10-atlas-starship.fish, distinct from
# development/fish's 00-atlas.fish); records any pre-existing file verbatim to a
# uniquely-named backup and restores it byte-for-byte on deactivate.
_STARSHIP_ACT_ABSENT="__ATLAS_ABSENT__"

_starship_act_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/activated/development-starship"
}

_starship_act_backup_dir() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/activated/backups/development-starship"
}

_starship_act_snippet_file() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/10-atlas-starship.fish"
}

# The Atlas-owned snippet bytes (RFC-0031 §5.3), an emitter whose output is hashed
# (mirroring development/fish's _fish_config_content / _fish_config_hash), so the
# ownership check is a SHA256 comparison, not a fragile text diff.
_starship_act_snippet_content() {
  printf '%s\n' "# Managed by Atlas: development/starship activation (RFC-0031). Do not edit."
  printf '%s\n' "# Reversible: run 'atlas deactivate development/starship' to remove this file."
  printf '%s\n' 'fish_add_path -gp $HOME/.local/bin'
  printf '%s\n' "if status is-interactive"
  printf '%s\n' '    set -gx STARSHIP_CONFIG $HOME/.config/atlas/starship/starship.toml'
  printf '%s\n' "    starship init fish | source"
  printf '%s\n' "end"
}

_starship_act_snippet_hash() {
  _starship_act_snippet_content | sha256sum | awk '{print $1}'
}

_starship_act_file_hash() {
  sha256sum "$1" 2>/dev/null | awk '{print $1}'
}

# True iff the on-disk snippet is a regular (non-symlink) file whose hash equals
# the RECORDED snippet_sha256 (§5.3 F3), NOT the current in-code template hash.
_starship_act_snippet_matches_recorded() {
  local path
  path="$(_starship_act_snippet_file)"
  [ -f "$path" ] || return 1
  [ ! -L "$path" ] || return 1
  [ -n "$_STARSHIP_ACT_SNIPPET_SHA" ] || return 1
  [ "$(_starship_act_file_hash "$path")" = "$_STARSHIP_ACT_SNIPPET_SHA" ]
}

_starship_act_backup_ref_valid() {
  case "$1" in
    ""|.|..) return 1 ;;
    */*) return 1 ;;
    *) return 0 ;;
  esac
}

_starship_act_init() {
  _STARSHIP_ACT_STATE=absent
  _STARSHIP_ACT_PRIOR=
  _STARSHIP_ACT_PRIOR_SHA=
  _STARSHIP_ACT_BACKUP_REF=
  _STARSHIP_ACT_SNIPPET_SHA=
}

# Strict parser for activated/development-starship (§5.4).
_starship_act_load() {
  _starship_act_init
  local marker line key val
  local seen_schema=0 seen_state=0 seen_prior=0 seen_prior_sha=0 seen_backup=0 seen_snippet=0
  marker="$(_starship_act_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Starship activation marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || {
    log::error "cannot inspect Starship activation marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || {
    log::error "Starship activation marker mode must be 600: $marker"; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Starship activation marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema)
        [ "$val" = "1" ] || { log::error "Starship activation schema is unsupported: $val"; return 1; }
        seen_schema=1
        ;;
      state)
        case "$val" in
          activating|active|inactive) _STARSHIP_ACT_STATE="$val" ;;
          *) log::error "Starship activation state is invalid: $val"; return 1 ;;
        esac
        seen_state=1
        ;;
      prior_conf)
        case "$val" in
          "$_STARSHIP_ACT_ABSENT"|present) _STARSHIP_ACT_PRIOR="$val" ;;
          *) log::error "Starship activation prior_conf is invalid: $val"; return 1 ;;
        esac
        seen_prior=1
        ;;
      prior_conf_sha256) _STARSHIP_ACT_PRIOR_SHA="$val"; seen_prior_sha=1 ;;
      backup_ref) _STARSHIP_ACT_BACKUP_REF="$val"; seen_backup=1 ;;
      snippet_sha256) _STARSHIP_ACT_SNIPPET_SHA="$val"; seen_snippet=1 ;;
      *) log::error "Starship activation marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Starship activation marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Starship activation marker is missing state"; return 1; }

  # §5.4: prior_conf and snippet_sha256 are present iff state is activating|active.
  case "$_STARSHIP_ACT_STATE" in
    inactive)
      [ "$seen_prior" -eq 0 ] || { log::error "Starship activation marker has prior_conf under inactive state"; return 1; }
      [ "$seen_snippet" -eq 0 ] || { log::error "Starship activation marker has snippet_sha256 under inactive state"; return 1; }
      [ "$seen_prior_sha" -eq 0 ] || { log::error "Starship activation marker has prior_conf_sha256 under inactive state"; return 1; }
      [ "$seen_backup" -eq 0 ] || { log::error "Starship activation marker has backup_ref under inactive state"; return 1; }
      ;;
    activating|active)
      [ "$seen_prior" -eq 1 ] || { log::error "Starship activation marker is missing prior_conf under $_STARSHIP_ACT_STATE"; return 1; }
      [ "$seen_snippet" -eq 1 ] || { log::error "Starship activation marker is missing snippet_sha256 under $_STARSHIP_ACT_STATE"; return 1; }
      _starship_hash_valid "$_STARSHIP_ACT_SNIPPET_SHA" || { log::error "Starship activation snippet_sha256 is invalid"; return 1; }
      # §5.4: prior_conf_sha256 and backup_ref are present iff prior_conf=present.
      case "$_STARSHIP_ACT_PRIOR" in
        present)
          [ "$seen_prior_sha" -eq 1 ] || { log::error "Starship activation marker is missing prior_conf_sha256 under prior_conf=present"; return 1; }
          [ "$seen_backup" -eq 1 ] || { log::error "Starship activation marker is missing backup_ref under prior_conf=present"; return 1; }
          _starship_hash_valid "$_STARSHIP_ACT_PRIOR_SHA" || { log::error "Starship activation prior_conf_sha256 is invalid"; return 1; }
          _starship_act_backup_ref_valid "$_STARSHIP_ACT_BACKUP_REF" || { log::error "Starship activation backup_ref is not a safe path component"; return 1; }
          ;;
        *)
          [ "$seen_prior_sha" -eq 0 ] || { log::error "Starship activation marker has prior_conf_sha256 under prior_conf=__ATLAS_ABSENT__"; return 1; }
          [ "$seen_backup" -eq 0 ] || { log::error "Starship activation marker has backup_ref under prior_conf=__ATLAS_ABSENT__"; return 1; }
          ;;
      esac
      ;;
  esac
  return 0
}

# Atomic 600-mode write of the activation marker from the current _STARSHIP_ACT_* vars.
_starship_act_write() {
  local state="$1" marker dir tmp
  marker="$(_starship_act_marker)"
  dir="$(dirname "$marker")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-starship.act.XXXXXX")" || {
    log::error "cannot create a Starship activation temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    case "$state" in
      activating|active)
        printf 'prior_conf=%s\n' "$_STARSHIP_ACT_PRIOR"
        if [ "$_STARSHIP_ACT_PRIOR" = "present" ]; then
          printf 'prior_conf_sha256=%s\n' "$_STARSHIP_ACT_PRIOR_SHA"
          printf 'backup_ref=%s\n' "$_STARSHIP_ACT_BACKUP_REF"
        fi
        printf 'snippet_sha256=%s\n' "$_STARSHIP_ACT_SNIPPET_SHA"
        ;;
    esac
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

# Write the Atlas snippet bytes to the snippet path atomically (mktemp+644+mv).
_starship_act_write_snippet() {
  local path dir tmp
  path="$(_starship_act_snippet_file)"
  dir="$(dirname "$path")"
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  tmp="$(mktemp "$dir/.10-atlas-starship.XXXXXX")" || {
    log::error "cannot create a Starship snippet temp file in $dir"; return 1; }
  _starship_act_snippet_content > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 644 "$tmp" || { rm -f "$tmp"; log::error "cannot set mode on $tmp"; return 1; }
  mv -f "$tmp" "$path" || { rm -f "$tmp"; log::error "cannot replace $path"; return 1; }
}

# §5.1 precondition: the literal wiring points at $HOME/.config/atlas/starship/,
# so under a non-default ATLAS_CONFIG_HOME/XDG_CONFIG_HOME the managed config must
# still resolve there or the snippet would not point at it.
_starship_act_config_path_ok() {
  [ "$(_starship_config_file)" = "$HOME/.config/atlas/starship/starship.toml" ]
}

module::activate() {
  _starship_marker_load || return 1
  [ "$_STARSHIP_MARKER_STATE" = "installed" ] || {
    log::error "development/starship is not installed; run 'atlas install development/starship' before activating"; return 1; }
  _starship_config_matches_source || {
    log::error "development/starship managed config is missing or drifted; run 'atlas install development/starship' before activating"; return 1; }
  os::has_cmd starship || {
    log::error "starship binary not found on PATH; install it (e.g. to ~/.local/bin) before activating development/starship"; return 1; }
  _starship_act_config_path_ok || {
    log::error "managed Starship config does not resolve under ~/.config/atlas/starship/; the fixed wiring cannot point at it — refusing to activate"; return 1; }

  _starship_act_load || return 1

  local path
  path="$(_starship_act_snippet_file)"
  local target_hash
  target_hash="$(_starship_act_snippet_hash)"
  [ -n "$target_hash" ] || { log::error "cannot hash the Atlas Starship snippet"; return 1; }

  # §5.5 step 3: state=active is either idempotent no-op or refuse-to-clobber.
  if [ "$_STARSHIP_ACT_STATE" = "active" ]; then
    if _starship_act_snippet_matches_recorded; then
      log::info "Atlas Starship prompt is already active"
      return 0
    fi
    log::error "the Atlas Starship snippet was removed or edited since activation; refusing to clobber — delete $(_starship_act_marker) to disown"
    return 1
  fi

  # §5.5 step 4: transition (inactive|activating|no record), possibly resumed.
  # Determine/reuse the prior write-once (F1 record-verbatim).
  if [ "$_STARSHIP_ACT_PRIOR" = "present" ] || [ "$_STARSHIP_ACT_PRIOR" = "$_STARSHIP_ACT_ABSENT" ]; then
    : # interrupted activating: reuse the recorded prior/backup unchanged.
  else
    if [ -L "$path" ] || { [ -e "$path" ] && [ ! -f "$path" ]; }; then
      log::error "the file at $path is a symlink or non-regular file; refusing to back up or overwrite it — move it aside before activating"
      return 1
    fi
    if [ -e "$path" ]; then
      # A regular file exists: back it up verbatim to a uniquely-named mktemp file.
      local bdir bref btmp bhash
      bdir="$(_starship_act_backup_dir)"
      mkdir -p "$bdir" || { log::error "cannot create $bdir"; return 1; }
      chmod 700 "$bdir" || { log::error "cannot secure $bdir"; return 1; }
      btmp="$(mktemp "$bdir/XXXXXX.prior")" || { log::error "cannot create a Starship backup file in $bdir"; return 1; }
      cp "$path" "$btmp" || { rm -f "$btmp"; log::error "cannot back up $path"; return 1; }
      chmod 600 "$btmp" || { rm -f "$btmp"; log::error "cannot secure $btmp"; return 1; }
      bhash="$(_starship_act_file_hash "$btmp")"
      _starship_hash_valid "$bhash" || { rm -f "$btmp"; log::error "cannot hash the Starship backup"; return 1; }
      _STARSHIP_ACT_PRIOR="present"
      _STARSHIP_ACT_PRIOR_SHA="$bhash"
      _STARSHIP_ACT_BACKUP_REF="$(basename "$btmp")"
    else
      _STARSHIP_ACT_PRIOR="$_STARSHIP_ACT_ABSENT"
      _STARSHIP_ACT_PRIOR_SHA=
      _STARSHIP_ACT_BACKUP_REF=
    fi
  fi

  # §5.5 F2a: guard the write against an interruption-window foreign file. The
  # on-disk file must be absent, the recorded backup, or the Atlas snippet
  # (matching the hash about to be written OR the recorded snippet_sha256).
  if [ -e "$path" ] || [ -L "$path" ]; then
    if [ -L "$path" ] || [ ! -f "$path" ]; then
      log::error "the file at $path is a symlink or non-regular file; refusing to overwrite it — move it aside or delete $(_starship_act_marker) to disown"
      return 1
    fi
    local disk_hash
    disk_hash="$(_starship_act_file_hash "$path")"
    local ok=0
    [ "$disk_hash" = "$target_hash" ] && ok=1
    [ -n "$_STARSHIP_ACT_SNIPPET_SHA" ] && [ "$disk_hash" = "$_STARSHIP_ACT_SNIPPET_SHA" ] && ok=1
    [ "$_STARSHIP_ACT_PRIOR" = "present" ] && [ "$disk_hash" = "$_STARSHIP_ACT_PRIOR_SHA" ] && ok=1
    [ "$ok" -eq 1 ] || {
      log::error "the file at $path changed during activation and is neither the recorded prior nor the Atlas snippet; refusing to overwrite — re-run after moving it aside, or delete $(_starship_act_marker) to disown"
      return 1
    }
  fi

  # Record snippet_sha256 = the hash Atlas will write (F3), then write activating.
  _STARSHIP_ACT_SNIPPET_SHA="$target_hash"
  _starship_act_write activating || return 1
  _starship_act_write_snippet || return 1
  _starship_act_write active || return 1
  log::info "Atlas Starship prompt activated; open a new interactive fish (or source $(_starship_act_snippet_file)) to see it — already-open shells are unchanged. This wiring runs the starship binary at shell start; if you later remove it from ~/.local/bin/PATH, run 'atlas deactivate development/starship' (or re-install the binary) to avoid per-shell errors."
}

module::deactivate() {
  _starship_act_load || return 1
  case "$_STARSHIP_ACT_STATE" in
    absent|inactive) log::info "development/starship is not activated by Atlas"; return 0 ;;
  esac

  local path
  path="$(_starship_act_snippet_file)"

  # §5.6 step 2: establish ownership BEFORE any destructive step, in every state.
  if [ -L "$path" ]; then
    log::error "the Starship snippet path is a symlink; refusing to remove it — delete $(_starship_act_marker) to disown"
    return 1
  fi

  if [ ! -e "$path" ]; then
    if [ "$_STARSHIP_ACT_PRIOR" = "$_STARSHIP_ACT_ABSENT" ]; then
      # already-restored finalize (deletion landed, state write lost). No backup.
      _starship_act_init
      _starship_act_write inactive || return 1
      log::info "development/starship already restored (snippet absent); marked inactive"
      return 0
    fi
    # snippet absent + prior_conf=present: proceed to restore-from-backup (step 3).
  else
    if [ ! -f "$path" ]; then
      log::error "the Starship snippet path is not a regular file; refusing to remove it — delete $(_starship_act_marker) to disown"
      return 1
    fi
    local disk_hash
    disk_hash="$(_starship_act_file_hash "$path")"
    if [ "$disk_hash" = "$_STARSHIP_ACT_SNIPPET_SHA" ]; then
      : # Atlas owns this file; proceed to restore (step 3).
    elif [ "$_STARSHIP_ACT_PRIOR" = "present" ] && [ "$disk_hash" = "$_STARSHIP_ACT_PRIOR_SHA" ]; then
      # already-restored finalize (B1): restore mv landed, state write lost.
      # Checked BEFORE the drift branch so a normal crash is not misreported.
      local bref="$_STARSHIP_ACT_BACKUP_REF"
      _starship_act_init
      _starship_act_write inactive || return 1
      rm -f "$(_starship_act_backup_dir)/$bref"
      log::info "development/starship already restored (prior bytes on disk); marked inactive"
      return 0
    else
      log::error "the Starship snippet was edited or replaced since activation; refusing to remove it — delete $(_starship_act_marker) to disown"
      return 1
    fi
  fi

  # §5.6 step 3: restore the recorded prior (verbatim).
  local restored_prior=0
  if [ "$_STARSHIP_ACT_PRIOR" = "$_STARSHIP_ACT_ABSENT" ]; then
    rm -f "$path" || { log::error "cannot remove the Atlas Starship snippet: $path; state left unchanged"; return 1; }
    rmdir "$(dirname "$path")" 2>/dev/null || true
  else
    local backup bhash
    backup="$(_starship_act_backup_dir)/$_STARSHIP_ACT_BACKUP_REF"
    if [ ! -f "$backup" ] || [ -L "$backup" ]; then
      log::error "the recorded Starship backup is missing: $backup; state left unchanged — delete $(_starship_act_marker) to disown"
      return 1
    fi
    bhash="$(_starship_act_file_hash "$backup")"
    if [ "$bhash" != "$_STARSHIP_ACT_PRIOR_SHA" ]; then
      log::error "the recorded Starship backup no longer matches its hash: $backup; state left unchanged — delete $(_starship_act_marker) to disown"
      return 1
    fi
    local dir tmp
    dir="$(dirname "$path")"
    mkdir -p "$dir" || { log::error "cannot create $dir; state left unchanged"; return 1; }
    tmp="$(mktemp "$dir/.10-atlas-starship.XXXXXX")" || { log::error "cannot create a Starship restore temp file in $dir; state left unchanged"; return 1; }
    cp "$backup" "$tmp" || { rm -f "$tmp"; log::error "cannot stage restore of $path; state left unchanged"; return 1; }
    chmod 644 "$tmp" || { rm -f "$tmp"; log::error "cannot chmod $tmp; state left unchanged"; return 1; }
    mv -f "$tmp" "$path" || { rm -f "$tmp"; log::error "cannot restore $path; state left unchanged"; return 1; }
    restored_prior=1
  fi

  # §5.6 step 4: write state=inactive FIRST (escrow consumed), THEN remove backup.
  local bref="$_STARSHIP_ACT_BACKUP_REF"
  _starship_act_init
  _starship_act_write inactive || return 1
  if [ -n "$bref" ]; then
    rm -f "$(_starship_act_backup_dir)/$bref"
  fi
  if [ "$restored_prior" -eq 1 ]; then
    log::info "Atlas Starship prompt deactivated; new interactive fish shells will use your previous prompt — already-open shells are unchanged. Your previous 10-atlas-starship.fish has been restored."
  else
    log::info "Atlas Starship prompt deactivated; new interactive fish shells will use your previous prompt — already-open shells are unchanged."
  fi
}
