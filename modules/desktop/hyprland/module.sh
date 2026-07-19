#!/usr/bin/env bash
# desktop/hyprland — RFC-0038 (corrected post comparative review).
#
# Atlas owns: COPR solopasha/hyprland intent; local aquamarine-0.9.5-2.fc44.atlas1
# while needed; the fixed hypr package set; five ~/.config trees; two named
# wallpapers; recorded numeric dnf history id; watcher script + user systemd units.
# Does NOT own: Plasma, user shell, unrelated themes, or package removal on detach.
MODULE_NAME="hyprland"
MODULE_DESCRIPTION="Atlas Hyprland desktop: local aquamarine rebuild + hypr stack + managed configs."
MODULE_DEPENDS=()

_HYPR_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_HYPR_ASSETS_DIR="$_HYPR_MODULE_DIR/assets"
_HYPR_COPR="solopasha/hyprland"
_HYPR_REPO_ID="copr:copr.fedorainfracloud.org:solopasha:hyprland"
_HYPR_CONFIG_TREES="hypr waybar wofi mako kitty"
_HYPR_PACKAGES=(
  hyprland xdg-desktop-portal-hyprland hyprlock hypridle hyprpaper
  waybar wofi mako kitty grim slurp brightnessctl playerctl
)
_HYPR_WALLPAPERS="atlas-lock-bg.png atlas-wall-bw.png"
# Package NEVRA prefix allowlist for rehearsal (additive-only outside this set).
_HYPR_PKG_ALLOW_RE='^(aquamarine|hyprland|xdg-desktop-portal-hyprland|hyprlock|hypridle|hyprpaper|waybar|wofi|mako|kitty|grim|slurp|brightnessctl|playerctl)([.-]|$)'

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
_hypr_repo_file() {
  printf '%s\n' "${ATLAS_HYPR_REPO_FILE:-/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:solopasha:hyprland.repo}"
}
_hypr_watcher_dst() { printf '%s\n' "${ATLAS_HYPR_WATCHER_BIN:-$HOME/.local/bin/atlas-hypr-check.sh}"; }
_hypr_units_dir() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; }

_hypr_run_privileged() { if os::is_root; then "$@"; else sudo "$@"; fi; }
_hypr_hyprland_present() { os::has_cmd Hyprland || rpm -q hyprland >/dev/null 2>&1; }
_hypr_build_rpm() { bash "$_HYPR_MODULE_DIR/build/build-aquamarine.sh" >/dev/null 2>&1; }
_hypr_systemctl_user() { systemctl --user "$@"; }

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
  [ -f "$(_hypr_wall_dir)/.atlas-hypr-wall.sha256" ] || return 1
  for f in $_HYPR_WALLPAPERS; do
    dst="$(_hypr_wall_dst "$f")"
    [ -f "$dst" ] || return 1
    [ -s "$dst" ] || return 1
  done
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    src_hash="${line%% *}"
    f="${line##* }"
    f="${f#./}"
    dst="$(_hypr_wall_dst "$f")"
    [ "$(_hypr_sha256 "$dst")" = "$src_hash" ] || return 1
  done < "$(_hypr_wall_dir)/.atlas-hypr-wall.sha256"
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

# Bake expected wallpapers into a temp dir and compare to any pre-existing
# Atlas-named files (RFC-0038 §7). Seam for tests.
_hypr_preview_bake_wallpapers() {
  local out="$1"
  mkdir -p "$out" || return 1
  ATLAS_WALL_OUT="$out" bash "$_HYPR_ASSETS_DIR/generate.sh" >/dev/null 2>&1
}

_hypr_wallpaper_matches_expected() {
  local f dst tmp expected
  tmp="$(mktemp -d)" || return 1
  if ! _hypr_preview_bake_wallpapers "$tmp"; then
    rm -rf "$tmp"
    return 1
  fi
  for f in $_HYPR_WALLPAPERS; do
    dst="$(_hypr_wall_dst "$f")"
    expected="$tmp/$f"
    [ -f "$expected" ] || { rm -rf "$tmp"; return 1; }
    if [ -e "$dst" ]; then
      [ "$(_hypr_sha256 "$dst")" = "$(_hypr_sha256 "$expected")" ] || {
        rm -rf "$tmp"; return 1; }
    fi
  done
  rm -rf "$tmp"
  return 0
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

  # Wallpapers: absent OK; present must match a fresh generate.sh bake.
  # Never adopt differing content just because the sidecar is missing.
  local any_wall=0
  for f in $_HYPR_WALLPAPERS; do
    [ -e "$(_hypr_wall_dst "$f")" ] && any_wall=1
  done
  if [ "$any_wall" -eq 1 ]; then
    if [ -f "$(_hypr_wall_dir)/.atlas-hypr-wall.sha256" ]; then
      _hypr_wallpapers_match || {
        log::error "refusing to overwrite drifted Atlas wallpapers"; return 1; }
    else
      _hypr_wallpaper_matches_expected || {
        log::error "refusing to overwrite unmanaged differing wallpaper under $(_hypr_wall_dir)"
        return 1
      }
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
  bash "$_HYPR_ASSETS_DIR/generate.sh" >/dev/null 2>&1 || return 1
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

# Fail-closed parser for dnf --assumeno output (testable without dnf).
# Rejects: dnf failure (caller), removals/erasures/obsoletes, and
# upgrade/downgrade of any package outside the hypr/aquamarine allowlist.
_hypr_rehearse_output_ok() {
  local out="$1" section="" line name
  printf '%s\n' "$out" | grep -Eqi '(^|[[:space:]])(Removing|Erasing|Obsoleting)(:|[[:space:]])' && return 1

  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      Removing:*|Erasing:*|Obsoleting:*|removing:*|erasing:*|obsoleting:*)
        return 1
        ;;
      Upgrading:*|Downgrading:*|upgrading:*|downgrading:*)
        section=mutate
        continue
        ;;
      Installing:*|installing:*|Reinstalling:*|reinstalling:*)
        section=install
        continue
        ;;
      Transaction*|" "*Summary*|"")
        section=""
        continue
        ;;
    esac
    if [ "$section" = mutate ]; then
      # Package name is usually the first field; strip arch/epoch noise.
      name="$(printf '%s\n' "$line" | awk '{print $1}')"
      name="${name##*/}"
      [ -z "$name" ] && continue
      case "$name" in
        Package|Name|---*|=====*) continue ;;
      esac
      printf '%s\n' "$name" | grep -Eq "$_HYPR_PKG_ALLOW_RE" || return 1
    fi
  done <<< "$out"
  return 0
}

_hypr_rehearse_transaction() {
  local rpm out rc=0
  rpm="$(_hypr_rpm_path)"
  out="$(_hypr_run_privileged dnf install -y --assumeno "$rpm" "${_HYPR_PACKAGES[@]}" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    log::error "hyprland transaction rehearsal failed (dnf exit $rc) — fail closed"
    return 1
  fi
  if ! _hypr_rehearse_output_ok "$out"; then
    log::error "hyprland transaction rehearsal is not additive (removal or non-hypr upgrade/downgrade)"
    return 1
  fi
  return 0
}

_hypr_dnf_copr_available() {
  command -v dnf >/dev/null 2>&1 || return 1
  dnf copr --help >/dev/null 2>&1
}

_hypr_repo_ok() {
  local repo="$(_hypr_repo_file)"
  [ -f "$repo" ] || return 1
  grep -qxF "[$_HYPR_REPO_ID]" "$repo" || return 1
  grep -qxF "enabled=1" "$repo" || return 1
  grep -qxF "gpgcheck=1" "$repo" || return 1
  grep -q '^baseurl=' "$repo" || return 1
}

_hypr_write_repo() {
  if _hypr_repo_ok >/dev/null 2>&1; then
    log::info "Hyprland COPR repository already enabled"
    return 0
  fi
  if ! _hypr_dnf_copr_available; then
    os::dnf_install dnf-plugins-core || { log::error "cannot install dnf COPR support"; return 1; }
  fi
  _hypr_run_privileged dnf -y copr enable "$_HYPR_COPR" || {
    log::error "cannot enable Hyprland COPR repository"; return 1; }
  _hypr_repo_ok || { log::error "Hyprland COPR repo file failed validation"; return 1; }
  log::info "enabled Hyprland COPR repository: $_HYPR_COPR"
}

_hypr_dnf_install_local() {
  local rpm="${1:-}"
  [ -n "$rpm" ] || rpm="$(_hypr_rpm_path)"
  [ -f "$rpm" ] || { log::error "aquamarine RPM not built: $rpm"; return 1; }
  _hypr_rpm_gate "$rpm" || { log::error "aquamarine RPM failed soname gate: $rpm"; return 1; }
  _hypr_run_privileged dnf install -y "$rpm" "${_HYPR_PACKAGES[@]}"
}

_hypr_txn_id_valid() {
  local id="$1"
  case "$id" in
    ""|unknown|0) return 1 ;;
    *[!0-9]*) return 1 ;;
  esac
  return 0
}

_hypr_txn_ok() {
  local id
  [ -f "$(_hypr_txn_file)" ] || return 1
  id="$(tr -d '[:space:]' < "$(_hypr_txn_file)" 2>/dev/null || true)"
  _hypr_txn_id_valid "$id"
}

# Resolve newest history id. Prefer ATLAS_HYPR_TXN_ID in tests. Never write "unknown".
_hypr_fetch_txn_id() {
  local id=""
  if [ -n "${ATLAS_HYPR_TXN_ID:-}" ]; then
    printf '%s\n' "$ATLAS_HYPR_TXN_ID"
    return 0
  fi
  # dnf5: `dnf history list` — first numeric field on a data row
  id="$(_hypr_run_privileged dnf history list 2>/dev/null \
    | awk '/^[[:space:]]*[0-9]+[[:space:]]/{print $1; exit}')"
  if ! _hypr_txn_id_valid "${id:-}"; then
    id="$(_hypr_run_privileged dnf history info 2>/dev/null \
      | awk -F: '/^Transaction ID/{gsub(/[[:space:]]/,"",$2); print $2; exit}')"
  fi
  printf '%s\n' "${id:-}"
}

_hypr_record_txn_id() {
  local id path dir
  path="$(_hypr_txn_file)"
  dir="$(dirname "$path")"
  mkdir -p "$dir" || return 1
  id="$(_hypr_fetch_txn_id)"
  _hypr_txn_id_valid "$id" || {
    log::error "cannot record a usable numeric dnf history id (got '${id:-empty}')"
    return 1
  }
  printf '%s\n' "$id" > "$path" || return 1
  chmod 600 "$path" || return 1
}

_hypr_deploy_watcher() {
  local bin units
  bin="$(_hypr_watcher_dst)"
  units="$(_hypr_units_dir)"
  mkdir -p "$(dirname "$bin")" "$units" || return 1
  cp -f "$_HYPR_ASSETS_DIR/watch-availability.sh" "$bin" || return 1
  chmod 755 "$bin" || return 1
  cp -f "$_HYPR_ASSETS_DIR/atlas-hypr-check.service" \
        "$_HYPR_ASSETS_DIR/atlas-hypr-check.timer" "$units/" || return 1
  _hypr_systemctl_user daemon-reload >/dev/null 2>&1 || true
  _hypr_systemctl_user enable --now atlas-hypr-check.timer >/dev/null 2>&1 || true
}

_hypr_undeploy_watcher() {
  _hypr_systemctl_user disable --now atlas-hypr-check.timer >/dev/null 2>&1 || true
  rm -f "$(_hypr_watcher_dst)" \
        "$(_hypr_units_dir)/atlas-hypr-check.service" \
        "$(_hypr_units_dir)/atlas-hypr-check.timer" || true
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
  _hypr_txn_ok || return 1
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

  # True idempotency: healthy installed state does not re-run dnf.
  if [ "$_HYPR_STATE" = installed ] && _hypr_managed_ok; then
    log::info "Atlas Hyprland already installed and healthy"
    return 0
  fi

  case "$_HYPR_STATE" in
    absent|detached)
      _hypr_preflight_targets || return 1
      ;;
  esac

  _hypr_marker_write installing || return 1

  _hypr_write_repo || return 1

  if [ ! -f "$(_hypr_rpm_path)" ]; then
    _hypr_build_rpm || { log::error "aquamarine build failed"; return 1; }
  fi
  # Always re-gate — even a pre-existing file at the expected path.
  _hypr_rpm_gate "$(_hypr_rpm_path)" || {
    log::error "aquamarine RPM failed soname gate"; return 1; }

  _hypr_rehearse_transaction || return 1
  _hypr_dnf_install_local "$(_hypr_rpm_path)" || {
    log::error "hyprland package install failed"; return 1; }
  _hypr_record_txn_id || { log::error "cannot record dnf history id"; return 1; }

  _hypr_deploy_configs || return 1
  _hypr_bake_wallpapers || { log::error "hyprland wallpaper bake failed"; return 1; }
  _hypr_deploy_watcher || log::warn "supersession watcher not activated"

  _hypr_configs_match || { log::error "hyprland config deploy mismatch"; return 1; }
  _hypr_wallpapers_match || { log::error "hyprland wallpapers missing after bake"; return 1; }
  _hypr_txn_ok || { log::error "hyprland dnf history id unusable"; return 1; }
  _hypr_hyprland_present || { log::error "hyprland not present after install"; return 1; }

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
  _hypr_txn_ok || { log::error "hyprland dnf history id missing or unusable"; return 1; }
  _hypr_hyprland_present || { log::error "hyprland package/binary missing"; return 1; }
  log::info "Atlas Hyprland config is healthy"
}

module::update() {
  _hypr_marker_load || return 1
  case "$_HYPR_STATE" in
    absent|detached) return 0 ;;
    installing)
      log::error "hyprland install incomplete; rerun install"
      return 1
      ;;
  esac
  _hypr_deploy_configs || return 1
  _hypr_bake_wallpapers || { log::error "hyprland wallpaper bake failed"; return 1; }
  _hypr_configs_match || return 1
  _hypr_wallpapers_match || return 1
  _hypr_marker_write installed || return 1
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
  _hypr_undeploy_watcher

  _hypr_marker_write detached || return 1
  local txn
  txn="$(tr -d '[:space:]' < "$(_hypr_txn_file)" 2>/dev/null || true)"
  if _hypr_txn_id_valid "$txn"; then
    log::info "detached Hyprland configs; packages remain — roll back with: sudo dnf history undo $txn"
  else
    log::info "detached Hyprland configs; packages remain (no usable recorded dnf history id)"
  fi
}

module::backup() { log::info "nothing to back up: desktop/hyprland is reconstructable"; }
module::restore() { log::info "nothing to restore: reinstall desktop/hyprland"; }
