#!/usr/bin/env bash
# desktop/hyprland — RFC-0038.
#
# Atlas owns: COPR solopasha/hyprland intent, local aquamarine-0.9.5-2.fc44.atlas1
# when the official build still needs libdisplay-info.so.2, the fixed hypr package
# set, five ~/.config trees, two named wallpapers, the recorded dnf history id,
# and the supersession watcher disposition.
# Does NOT own: Plasma, user shell, unrelated themes, or package removal on detach.
MODULE_NAME="hyprland"
MODULE_DESCRIPTION="Atlas Hyprland desktop: local aquamarine rebuild + hypr stack + managed configs."
MODULE_DEPENDS=()

_HYPR_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_HYPR_COPR="solopasha/hyprland"
_HYPR_CONFIG_TREES="hypr waybar wofi mako kitty"
_HYPR_PACKAGES=(
  hyprland xdg-desktop-portal-hyprland hyprlock hypridle hyprpaper
  waybar wofi mako kitty grim slurp brightnessctl playerctl
)
_HYPR_WALLPAPERS="atlas-lock-bg.png atlas-wall-bw.png"

_hypr_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-hyprland"
}
_hypr_txn_file() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/hypr-install-txn"
}
_hypr_rpm_path() {
  printf '%s\n' "${ATLAS_HYPR_RPM_DIR:-$HOME/atlas-hypr-rpms}/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"
}
_hypr_cfg_src() { printf '%s\n' "$_HYPR_MODULE_DIR/config/$1"; }
_hypr_cfg_dst() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/$1"; }
_hypr_wall_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/backgrounds/atlas"; }
_hypr_wall_dst() { printf '%s\n' "$(_hypr_wall_dir)/$1"; }
_hypr_os_release() { printf '%s\n' "${ATLAS_HYPR_OS_RELEASE_FILE:-/etc/os-release}"; }
_hypr_fedora_release() { printf '%s\n' "${ATLAS_HYPR_FEDORA_RELEASE_FILE:-/etc/fedora-release}"; }

_hypr_run_privileged() { if os::is_root; then "$@"; else sudo "$@"; fi; }
_hypr_hyprland_present() { os::has_cmd Hyprland || rpm -q hyprland >/dev/null 2>&1; }
_hypr_build_rpm() { bash "$_HYPR_MODULE_DIR/build/build-aquamarine.sh" >/dev/null 2>&1; }

_hypr_fedora_44() {
  local osf fed
  osf="$(_hypr_os_release)"
  fed="$(_hypr_fedora_release)"
  if [ -r "$osf" ]; then
    if grep -qm1 '^ID=fedora$' "$osf" 2>/dev/null &&
       grep -Eqm1 '^VERSION_ID="?44"?$' "$osf" 2>/dev/null; then
      return 0
    fi
  fi
  [ -r "$fed" ] && grep -Eqm1 'release 44\b' "$fed" 2>/dev/null
}

_hypr_sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

_hypr_tree_manifest() {
  local root="$1"
  [ -d "$root" ] || return 1
  (cd "$root" && find . -type f -print | sort | xargs -r sha256sum) 2>/dev/null
}

_hypr_tree_matches() {
  local name="$1" src dst
  src="$(_hypr_cfg_src "$name")"
  dst="$(_hypr_cfg_dst "$name")"
  [ -d "$src" ] || return 1
  [ -d "$dst" ] || return 1
  [ "$(_hypr_tree_manifest "$src")" = "$(_hypr_tree_manifest "$dst")" ]
}

_hypr_configs_match() {
  local d
  for d in $_HYPR_CONFIG_TREES; do
    _hypr_tree_matches "$d" || return 1
  done
  return 0
}

_hypr_wallpapers_match() {
  local f src_hash dst
  # Source hashes come from last bake under the wall dir when managed; for
  # verify we require both named files exist and match the staged bake outputs
  # recorded at install (same paths). When only module source configs exist,
  # bake writes those two files — matching means both present and non-empty
  # after a managed install. Drift = content change after install.
  for f in $_HYPR_WALLPAPERS; do
    dst="$(_hypr_wall_dst "$f")"
    [ -f "$dst" ] || return 1
    [ -s "$dst" ] || return 1
  done
  # Compare against sidecar hashes written at bake/deploy time when present.
  if [ -f "$(_hypr_wall_dir)/.atlas-hypr-wall.sha256" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      [ -z "$line" ] && continue
      src_hash="${line%% *}"
      f="${line##* }"
      f="${f#./}"
      dst="$(_hypr_wall_dst "$f")"
      [ "$(_hypr_sha256 "$dst")" = "$src_hash" ] || return 1
    done < "$(_hypr_wall_dir)/.atlas-hypr-wall.sha256"
  fi
  return 0
}

_hypr_record_wall_hashes() {
  local dir f tmp
  dir="$(_hypr_wall_dir)"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "$dir/.atlas-hypr-wall.XXXXXX")" || return 1
  : > "$tmp" || { rm -f "$tmp"; return 1; }
  for f in $_HYPR_WALLPAPERS; do
    [ -f "$dir/$f" ] || { rm -f "$tmp"; return 1; }
    printf '%s  %s\n' "$(_hypr_sha256 "$dir/$f")" "$f" >> "$tmp" || { rm -f "$tmp"; return 1; }
  done
  mv -f "$tmp" "$dir/.atlas-hypr-wall.sha256" || { rm -f "$tmp"; return 1; }
}

# Adoption/refusal before package mutation (RFC-0038 §6/§7).
_hypr_preflight_targets() {
  local d src dst f
  for d in $_HYPR_CONFIG_TREES; do
    src="$(_hypr_cfg_src "$d")"
    dst="$(_hypr_cfg_dst "$d")"
    [ -d "$src" ] || { log::error "missing staged config: $src"; return 1; }
    if [ -e "$dst" ]; then
      if _hypr_tree_matches "$d"; then
        continue
      fi
      log::error "refusing to overwrite unmanaged differing config: $dst"
      return 1
    fi
  done
  # Wallpapers: if a hash sidecar exists, require a full match (drift = refuse).
  # If the two Atlas-named files exist without a sidecar, treat them as the
  # pre-module staged bake (RFC-0038 §7 / design §5) and adopt — install will
  # re-hash after bake. Never inspect any other file under the wallpaper dir.
  if [ -f "$(_hypr_wall_dir)/.atlas-hypr-wall.sha256" ]; then
    if ! _hypr_wallpapers_match; then
      log::error "refusing to overwrite unmanaged differing wallpaper under $(_hypr_wall_dir)"
      return 1
    fi
  fi
  return 0
}

_hypr_deploy_configs() {
  local d src dst
  for d in $_HYPR_CONFIG_TREES; do
    src="$(_hypr_cfg_src "$d")"
    dst="$(_hypr_cfg_dst "$d")"
    [ -d "$src" ] || { log::error "missing staged config: $src"; return 1; }
    if [ -d "$dst" ] && _hypr_tree_matches "$d"; then
      continue
    fi
    mkdir -p "$(dirname "$dst")" || return 1
    rm -rf "$dst" || return 1
    cp -a "$src" "$dst" || return 1
  done
}

_hypr_bake_wallpapers() {
  bash "$_HYPR_MODULE_DIR/assets/generate.sh" >/dev/null 2>&1 || return 1
  _hypr_record_wall_hashes
}

_hypr_rpm_gate() {
  local rpm="$1"
  [ -f "$rpm" ] || return 1
  rpm -qp --requires "$rpm" 2>/dev/null | grep -q 'libdisplay-info\.so\.3' || return 1
  rpm -qp --requires "$rpm" 2>/dev/null | grep -q 'libdisplay-info\.so\.2' && return 1
  rpm -qp --provides "$rpm" 2>/dev/null | grep -q 'libaquamarine\.so\.8' || return 1
  return 0
}

# Rehearsal: must be purely additive for non-hypr packages (RFC-0038 §8.2).
# Override in tests. Default uses dnf --assumeno and greps the transaction.
_hypr_rehearse_transaction() {
  local rpm out
  rpm="$(_hypr_rpm_path)"
  out="$(_hypr_run_privileged dnf install -y --assumeno "$rpm" "${_HYPR_PACKAGES[@]}" 2>&1)" || true
  printf '%s\n' "$out" | grep -Eqi 'removing|erasing|obsoleting' && {
    log::error "hyprland transaction rehearsal is not additive (removals detected)"; return 1; }
  return 0
}

_hypr_dnf_install_local() {
  local rpm="${1:-}"
  [ -n "$rpm" ] || rpm="$(_hypr_rpm_path)"
  [ -f "$rpm" ] || { log::error "aquamarine RPM not built: $rpm"; return 1; }
  _hypr_rpm_gate "$rpm" || { log::error "aquamarine RPM failed soname gate: $rpm"; return 1; }
  _hypr_run_privileged dnf install -y "$rpm" "${_HYPR_PACKAGES[@]}"
}

_hypr_record_txn_id() {
  local id path dir
  path="$(_hypr_txn_file)"
  dir="$(dirname "$path")"
  mkdir -p "$dir" || return 1
  id="$(_hypr_run_privileged dnf history --reverse 2>/dev/null | awk 'NR==3 {print $1; exit}')"
  # Fallback: newest id from `dnf history list`
  if [ -z "$id" ]; then
    id="$(_hypr_run_privileged dnf history list 2>/dev/null | awk 'NR==3 {print $1; exit}')"
  fi
  [ -n "$id" ] || id="${ATLAS_HYPR_TXN_ID:-unknown}"
  printf '%s\n' "$id" > "$path" || return 1
  chmod 600 "$path" 2>/dev/null || true
}

_hypr_marker_load() {
  _HYPR_STATE=absent
  local m line s=0 t=0 val mode
  m="$(_hypr_marker)"
  [ -e "$m" ] || return 0
  [ -f "$m" ] && [ ! -L "$m" ] && [ -r "$m" ] || {
    log::error "hyprland marker is not a readable regular file"; return 1; }
  mode="$(stat -c '%a' "$m" 2>/dev/null)" || {
    log::error "cannot inspect hyprland marker mode"; return 1; }
  [ "$mode" = "600" ] || { log::error "hyprland marker mode must be 600"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ""|\#*) continue ;; esac
    case "$line" in
      schema=1) s=1 ;;
      state=*)
        val="${line#state=}"
        case "$val" in
          installing|installed|detached) _HYPR_STATE="$val"; t=1 ;;
          *) log::error "hyprland marker state is invalid: $val"; return 1 ;;
        esac
        ;;
      *) log::error "hyprland marker has an unknown key: ${line%%=*}"; return 1 ;;
    esac
  done < "$m"
  [ "$s" -eq 1 ] && [ "$t" -eq 1 ] || {
    log::error "hyprland marker is missing schema or state"; return 1; }
}

_hypr_marker_write() {
  local state="$1" m dir tmp
  m="$(_hypr_marker)"
  dir="$(dirname "$m")"
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-hyprland.XXXXXX")" || return 1
  { printf 'schema=1\nstate=%s\n' "$state"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$m" || { rm -f "$tmp"; return 1; }
}

_hypr_managed_ok() {
  _hypr_configs_match || return 1
  _hypr_wallpapers_match || return 1
  [ -f "$(_hypr_txn_file)" ] || return 1
  _hypr_hyprland_present || return 1
  return 0
}

module::check() {
  _hypr_marker_load || return 1
  [ "$_HYPR_STATE" = installed ] || return 1
  _hypr_managed_ok || return 1
}

module::install() {
  _hypr_fedora_44 || { log::error "hyprland module supports Fedora 44 only"; return 1; }
  _hypr_marker_load || return 1

  case "$_HYPR_STATE" in
    absent|detached)
      _hypr_preflight_targets || return 1
      ;;
  esac

  _hypr_marker_write installing || return 1

  if [ ! -f "$(_hypr_rpm_path)" ]; then
    _hypr_build_rpm || { log::error "aquamarine build failed"; return 1; }
  fi
  _hypr_rpm_gate "$(_hypr_rpm_path)" || {
    log::error "aquamarine RPM failed soname gate"; return 1; }

  _hypr_rehearse_transaction || return 1
  _hypr_dnf_install_local "$(_hypr_rpm_path)" || {
    log::error "hyprland package install failed"; return 1; }
  _hypr_record_txn_id || { log::error "cannot record dnf history id"; return 1; }

  _hypr_deploy_configs || return 1
  _hypr_bake_wallpapers || { log::error "hyprland wallpaper bake failed"; return 1; }
  _hypr_configs_match || { log::error "hyprland config deploy mismatch"; return 1; }
  _hypr_wallpapers_match || { log::error "hyprland wallpapers missing after bake"; return 1; }
  _hypr_marker_write installed || return 1
  log::info "Atlas Hyprland is installed; pick it at the login screen (Plasma remains available)"
}

module::verify() {
  _hypr_marker_load || return 1
  case "$_HYPR_STATE" in
    absent|detached) return 0 ;;
    installing)
      log::error "hyprland install incomplete; rerun install"
      return 1
      ;;
  esac
  _hypr_configs_match || { log::error "hyprland managed config has drifted"; return 1; }
  _hypr_wallpapers_match || { log::error "hyprland managed wallpaper has drifted"; return 1; }
  [ -f "$(_hypr_txn_file)" ] || { log::error "hyprland dnf history id file missing"; return 1; }
  _hypr_hyprland_present || { log::error "hyprland package/binary missing"; return 1; }
  log::info "Atlas Hyprland config is healthy"
}

module::update() {
  _hypr_marker_load || return 1
  case "$_HYPR_STATE" in absent|detached) return 0 ;; esac
  _hypr_deploy_configs || return 1
  _hypr_bake_wallpapers || log::warn "wallpaper bake skipped"
  _hypr_marker_write installed || return 1
  _hypr_configs_match
}

module::remove() {
  _hypr_marker_load || return 1
  case "$_HYPR_STATE" in absent|detached) return 0 ;; esac

  if ! _hypr_configs_match || ! _hypr_wallpapers_match; then
    log::error "refusing detach: managed hyprland state has drifted"
    return 1
  fi

  local d f
  for d in $_HYPR_CONFIG_TREES; do
    rm -rf "$(_hypr_cfg_dst "$d")" || return 1
  done
  for f in $_HYPR_WALLPAPERS; do
    rm -f "$(_hypr_wall_dst "$f")" || return 1
  done
  rm -f "$(_hypr_wall_dir)/.atlas-hypr-wall.sha256" 2>/dev/null || true

  _hypr_marker_write detached || return 1
  local txn
  txn="$(cat "$(_hypr_txn_file)" 2>/dev/null || true)"
  if [ -n "$txn" ] && [ "$txn" != "unknown" ]; then
    log::info "detached Hyprland configs; packages remain — roll back with: sudo dnf history undo $txn"
  else
    log::info "detached Hyprland configs; packages remain (no recorded dnf history id)"
  fi
}

module::backup() { log::info "nothing to back up: desktop/hyprland is reconstructable"; }
module::restore() { log::info "nothing to restore: reinstall desktop/hyprland"; }
