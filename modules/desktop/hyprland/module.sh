#!/usr/bin/env bash
# desktop/hyprland — RFC-0038 (corrected post comparative review).
#
# Atlas owns: COPR solopasha/hyprland intent; local aquamarine-0.9.5-2.fc44.atlas1
# while needed; the fixed hypr package set; five ~/.config trees; two named
# wallpapers; the recorded dnf history transaction that installed them; watcher
# script + user systemd units. Does NOT own: Plasma, user shell, unrelated
# themes, or package removal on detach.
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

# Aquamarine artifact identity (must match modules/.../build/build-aquamarine.sh
# and RFC-0038 §5). Re-validated here before the RPM is ever handed to dnf.
_HYPR_AQ_NAME="aquamarine"
_HYPR_AQ_VERSION="0.9.5"
_HYPR_AQ_RELEASE="2.fc44.atlas1"
_HYPR_AQ_ARCH="x86_64"

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

# aquamarine is installed at all (any release)?
_hypr_aquamarine_installed() { rpm -q aquamarine >/dev/null 2>&1; }

# aquamarine is installed AND still the Atlas .atlas* local build (vs a later
# official rebuild that superseded it via `dnf upgrade`, RFC-0038 §9).
_hypr_aquamarine_is_atlas() {
  local rel
  rel="$(rpm -q --qf '%{RELEASE}' aquamarine 2>/dev/null || true)"
  case "$rel" in *.atlas*) return 0 ;; *) return 1 ;; esac
}

# The one real package transaction has already landed (interrupted-retry gate).
_hypr_packages_installed() {
  _hypr_hyprland_present || return 1
  _hypr_aquamarine_installed || return 1
}

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
  local f src_hash dst line
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

# Adoption/refusal before package mutation (RFC-0038 §6/§7). Only meaningful in
# absent/detached state (no marker); once a marker exists the trees are managed.
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

# Deploy config trees. <mode> is:
#   fresh   — entry state absent/detached: targets were absent or byte-identical
#             at preflight. NEVER rm -rf here; create absent trees, skip
#             identical ones, and FAIL LOUDLY on a tree that now differs (the
#             filesystem raced us between preflight and deploy — RFC-0038 §8
#             step 9). This closes the preflight/deploy race without ever
#             destroying content we have not proven Atlas-owned.
#   managed — entry state installing/installed: the marker already establishes
#             Atlas ownership of these five trees (RFC-0038 §6), so drift is
#             reconciled from source. Byte-identical trees are still skipped.
_hypr_deploy_configs() {
  local mode="${1:-managed}" d src dst
  for d in $_HYPR_CONFIG_TREES; do
    src="$(_hypr_cfg_src "$d")"
    dst="$(_hypr_cfg_dst "$d")"
    [ -d "$src" ] || { log::error "missing staged config: $src"; return 1; }
    if [ ! -e "$dst" ]; then
      mkdir -p "$(dirname "$dst")" || return 1
      cp -a "$src" "$dst" || return 1
      continue
    fi
    if _hypr_tree_matches "$d"; then
      continue
    fi
    if [ "$mode" = fresh ]; then
      log::error "config tree changed under us since preflight; refusing to overwrite: $dst"
      return 1
    fi
    rm -rf "$dst" || return 1
    cp -a "$src" "$dst" || return 1
  done
}

_hypr_bake_wallpapers() {
  bash "$_HYPR_ASSETS_DIR/generate.sh" >/dev/null 2>&1 || return 1
  _hypr_record_wall_hashes
}

# Full artifact gate (RFC-0038 §5): exact NEVRA + arch, soname requires/provides,
# and payload/header integrity. A pre-existing artifact is always re-validated.
_hypr_rpm_gate() {
  local rpm="$1" nevra name ver rel arch
  [ -f "$rpm" ] || return 1
  nevra="$(rpm -qp --qf '%{NAME} %{VERSION} %{RELEASE} %{ARCH}\n' "$rpm" 2>/dev/null)" || return 1
  read -r name ver rel arch <<<"$nevra" || return 1
  [ "$name" = "$_HYPR_AQ_NAME" ] || return 1
  [ "$ver" = "$_HYPR_AQ_VERSION" ] || return 1
  [ "$rel" = "$_HYPR_AQ_RELEASE" ] || return 1
  [ "$arch" = "$_HYPR_AQ_ARCH" ] || return 1
  rpm -qp --requires "$rpm" 2>/dev/null | grep -q 'libdisplay-info\.so\.3' || return 1
  rpm -qp --requires "$rpm" 2>/dev/null | grep -q 'libdisplay-info\.so\.2' && return 1
  rpm -qp --provides "$rpm" 2>/dev/null | grep -q 'libaquamarine\.so\.8' || return 1
  rpm -K --nosignature "$rpm" >/dev/null 2>&1 || return 1
  return 0
}

# Exact package-name allowlist for rehearsal upgrades (no broad kitty-* prefixes).
_hypr_pkg_allowed() {
  local n="$1" p
  for p in "$_HYPR_AQ_NAME" "${_HYPR_PACKAGES[@]}"; do
    [ "$n" = "$p" ] && return 0
  done
  return 1
}

# Positive confirmation that a --assumeno rehearsal RESOLVED cleanly and then
# declined. dnf5 --assumeno exits non-zero for BOTH a declined-but-resolved plan
# and a genuine resolver failure, so exit code cannot be trusted; classify by
# deterministic (LC_ALL=C) output and fail closed on anything unconfirmed.
_hypr_rehearse_resolved_ok() {
  local out="$1"
  printf '%s\n' "$out" \
    | grep -Eqi 'failed to resolve|nothing provides|no match for argument|depsolve error|problem:|conflicts with|cannot install' \
    && return 1
  printf '%s\n' "$out" | grep -qF 'Operation aborted by the user.' && return 0
  printf '%s\n' "$out" | grep -qiF 'nothing to do' && return 0
  return 1
}

# Fail-closed parser for a resolved dnf5 transaction plan. Rejects any removal,
# erasure, obsoletion/"replacing", or downgrade, and any upgrade of a package
# outside the exact hypr/aquamarine allowlist. Installs (incl. dependencies) are
# additive and always allowed.
_hypr_rehearse_output_ok() {
  local out="$1" raw line section="" name indented
  while IFS= read -r raw || [ -n "$raw" ]; do
    case "$raw" in
      " "*|$'\t'*) indented=1 ;;
      *) indented=0 ;;
    esac
    line="${raw#"${raw%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [ "$indented" -eq 0 ]; then
      case "$line" in
        "Installing:"|"Installing dependencies:"|"Installing weak dependencies:"|"Reinstalling:") section=install ;;
        "Upgrading:") section=upgrade ;;
        "Downgrading:") section=downgrade ;;
        "Removing:"|"Removing dependent packages:"|"Removing unused dependencies:") section=remove ;;
        "Obsoleting:") section=obsolete ;;
        *) section="" ;;
      esac
      continue
    fi
    case "$line" in
      [Rr]eplacing\ *) return 1 ;;
    esac
    [ -n "$section" ] || continue
    name="$(printf '%s\n' "$line" | awk '{print $1}')"
    [ -z "$name" ] && continue
    case "$name" in Package|Name) continue ;; esac
    case "$section" in
      remove|obsolete|downgrade) return 1 ;;
      upgrade) _hypr_pkg_allowed "$name" || return 1 ;;
      install) : ;;
    esac
  done <<< "$out"
  return 0
}

# Transaction rehearsal — the gate that protects Plasma (RFC-0038 §8.2).
_hypr_rehearse_transaction() {
  local rpm out
  rpm="$(_hypr_rpm_path)"
  out="$(_hypr_run_privileged env LC_ALL=C dnf install --assumeno "$rpm" "${_HYPR_PACKAGES[@]}" 2>&1)"
  if ! _hypr_rehearse_resolved_ok "$out"; then
    log::error "hyprland transaction rehearsal did not resolve cleanly — fail closed"
    return 1
  fi
  if ! _hypr_rehearse_output_ok "$out"; then
    log::error "hyprland transaction rehearsal is not additive (removal/obsoletion/downgrade or non-hypr upgrade)"
    return 1
  fi
  return 0
}

_hypr_dnf_copr_available() {
  command -v dnf >/dev/null 2>&1 || return 1
  dnf copr --help >/dev/null 2>&1
}

_hypr_repo_ok() {
  local repo
  repo="$(_hypr_repo_file)"
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
  _hypr_rpm_gate "$rpm" || { log::error "aquamarine RPM failed gate: $rpm"; return 1; }
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

# Newest dnf history transaction id ("" if none). dnf history list is
# newest-first, so the first numeric data row is the max id. Unprivileged
# (dnf5 history is readable by the invoking user).
_hypr_history_max_id() {
  dnf history list 2>/dev/null | awk '/^[[:space:]]*[0-9]+[[:space:]]/{print $1; exit}'
}

# Does dnf history transaction <id> exist AND install both aquamarine and
# hyprland? Proves the recorded id is really this module's install, not an
# unrelated/newer global transaction (RFC-0038 §8 step 8 / §10.3).
_hypr_txn_contains_expected() {
  local id="$1" info
  _hypr_txn_id_valid "$id" || return 1
  info="$(dnf history info "$id" 2>/dev/null)" || return 1
  [ -n "$info" ] || return 1
  printf '%s\n' "$info" | grep -Eq "^Transaction ID[[:space:]]*:[[:space:]]*${id}([[:space:]]|\$)" || return 1
  printf '%s\n' "$info" | grep -Eq '^[[:space:]]*Install[[:space:]]+aquamarine-' || return 1
  printf '%s\n' "$info" | grep -Eq '^[[:space:]]*Install[[:space:]]+hyprland-' || return 1
  return 0
}

# The recorded rollback transaction is present, numeric, exists in dnf history,
# and corresponds to this module's install (not merely well-formed).
_hypr_txn_ok() {
  local id
  [ -f "$(_hypr_txn_file)" ] || return 1
  id="$(tr -d '[:space:]' < "$(_hypr_txn_file)" 2>/dev/null || true)"
  _hypr_txn_id_valid "$id" || return 1
  _hypr_txn_contains_expected "$id"
}

# Record the transaction produced by THIS invocation, using a before/after
# history boundary. Rejects: no new transaction, malformed/absent id, a newer id
# that is not our aquamarine/hyprland install. Atomic write, mode 600.
_hypr_record_txn_from_boundary() {
  local before="$1" after="$2" path dir tmp
  path="$(_hypr_txn_file)"
  dir="$(dirname "$path")"
  _hypr_txn_id_valid "$after" || {
    log::error "dnf history returned no usable id after install (got '${after:-empty}')"; return 1; }
  if _hypr_txn_id_valid "$before"; then
    [ "$after" -gt "$before" ] || {
      log::error "no new dnf transaction recorded (before=$before after=$after)"; return 1; }
  fi
  _hypr_txn_contains_expected "$after" || {
    log::error "newest dnf transaction ($after) is not the expected aquamarine/hyprland install"; return 1; }
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" 2>/dev/null || true
  tmp="$(mktemp "$dir/.hypr-install-txn.XXXXXX")" || return 1
  printf '%s\n' "$after" > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$path" || { rm -f "$tmp"; return 1; }
}

_hypr_watcher_files_ok() {
  local bin units
  bin="$(_hypr_watcher_dst)"
  units="$(_hypr_units_dir)"
  [ -f "$bin" ] || return 1
  cmp -s "$_HYPR_ASSETS_DIR/watch-availability.sh" "$bin" || return 1
  cmp -s "$_HYPR_ASSETS_DIR/atlas-hypr-check.service" "$units/atlas-hypr-check.service" || return 1
  cmp -s "$_HYPR_ASSETS_DIR/atlas-hypr-check.timer" "$units/atlas-hypr-check.timer" || return 1
  return 0
}

_hypr_watcher_active() {
  _hypr_systemctl_user is-enabled atlas-hypr-check.timer >/dev/null 2>&1 || return 1
  _hypr_systemctl_user is-active atlas-hypr-check.timer >/dev/null 2>&1 || return 1
  return 0
}

# Watcher health (RFC-0038 §9): while aquamarine is still the .atlas1 local
# build, the timer must be deployed and active. Once an official rebuild
# supersedes it, the watcher may have self-disabled — that is valid, so only the
# file ownership is required in that state.
_hypr_watcher_ok() {
  _hypr_watcher_files_ok || return 1
  if _hypr_aquamarine_is_atlas; then
    _hypr_watcher_active || return 1
  fi
  return 0
}

# Deploy the watcher, fail-closed on every safety-critical step (RFC-0038 §9).
_hypr_deploy_watcher() {
  local bin units
  bin="$(_hypr_watcher_dst)"
  units="$(_hypr_units_dir)"
  mkdir -p "$(dirname "$bin")" "$units" || { log::error "cannot create watcher directories"; return 1; }
  cp -f "$_HYPR_ASSETS_DIR/watch-availability.sh" "$bin" || { log::error "cannot deploy watcher script"; return 1; }
  chmod 755 "$bin" || { log::error "cannot chmod watcher script"; return 1; }
  cp -f "$_HYPR_ASSETS_DIR/atlas-hypr-check.service" \
        "$_HYPR_ASSETS_DIR/atlas-hypr-check.timer" "$units/" || {
    log::error "cannot deploy watcher units"; return 1; }
  _hypr_systemctl_user daemon-reload || { log::error "systemctl --user daemon-reload failed"; return 1; }
  _hypr_systemctl_user enable --now atlas-hypr-check.timer || {
    log::error "cannot enable atlas-hypr-check.timer"; return 1; }
  _hypr_watcher_active || { log::error "atlas-hypr-check.timer is not active after enable"; return 1; }
  _hypr_watcher_files_ok || { log::error "deployed watcher files do not match repository source"; return 1; }
  return 0
}

# Undeploy only verified Atlas-owned watcher files (RFC-0038 §10.5).
_hypr_undeploy_watcher() {
  local bin units
  bin="$(_hypr_watcher_dst)"
  units="$(_hypr_units_dir)"
  _hypr_systemctl_user disable --now atlas-hypr-check.timer >/dev/null 2>&1 || true
  if [ -f "$bin" ] && cmp -s "$_HYPR_ASSETS_DIR/watch-availability.sh" "$bin"; then
    rm -f "$bin" || true
  fi
  if [ -f "$units/atlas-hypr-check.service" ] && \
     cmp -s "$_HYPR_ASSETS_DIR/atlas-hypr-check.service" "$units/atlas-hypr-check.service"; then
    rm -f "$units/atlas-hypr-check.service" || true
  fi
  if [ -f "$units/atlas-hypr-check.timer" ] && \
     cmp -s "$_HYPR_ASSETS_DIR/atlas-hypr-check.timer" "$units/atlas-hypr-check.timer"; then
    rm -f "$units/atlas-hypr-check.timer" || true
  fi
  _hypr_systemctl_user daemon-reload >/dev/null 2>&1 || true
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

# Full healthy-installed predicate (RFC-0038 §10). A healthy state means every
# owned surface is present and matching, so a healthy repeated install is a no-op.
_hypr_managed_ok() {
  _hypr_configs_match || return 1
  _hypr_wallpapers_match || return 1
  _hypr_txn_ok || return 1
  _hypr_hyprland_present || return 1
  _hypr_aquamarine_installed || return 1
  _hypr_watcher_ok || return 1
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

  # Fast path: a healthy installed state performs ZERO mutations — no dnf, no
  # rehearsal, no build, no config/wallpaper/watcher rewrites (RFC-0038 §10.2).
  if [ "$_HYPR_STATE" = installed ] && _hypr_managed_ok; then
    log::info "Atlas Hyprland already installed and healthy"
    return 0
  fi

  # Ownership is re-evaluated on EVERY mutating path. absent/detached has no
  # marker, so trees/wallpapers are adopted-if-identical or refused before any
  # package or filesystem mutation. installing/installed already carries Atlas
  # ownership (RFC-0038 §6/§7), so reconciliation may rewrite drift.
  local owned=0
  case "$_HYPR_STATE" in
    absent|detached)
      _hypr_preflight_targets || return 1
      owned=0
      ;;
    installing|installed)
      owned=1
      ;;
  esac

  _hypr_marker_write installing || return 1

  # Phase: COPR repository (idempotent).
  _hypr_write_repo || return 1

  # Phase: aquamarine artifact — build only if the gate does not already pass;
  # a pre-existing artifact is always re-validated, never trusted by name.
  if ! _hypr_rpm_gate "$(_hypr_rpm_path)"; then
    _hypr_build_rpm || { log::error "aquamarine build failed"; return 1; }
    _hypr_rpm_gate "$(_hypr_rpm_path)" || {
      log::error "aquamarine RPM failed the NEVRA/soname/integrity gate after build"; return 1; }
  fi

  # Phase: the ONE real package transaction. An interrupted retry that already
  # installed the packages must NOT run a second dnf transaction (RFC-0038 §8).
  if _hypr_packages_installed; then
    log::info "hypr packages already installed; not re-running the package transaction"
    if ! _hypr_txn_ok; then
      log::error "packages are installed but no valid rollback transaction is recorded; leaving state=installing"
      log::error "recover the id:  sudo dnf history list --contains-pkgs=aquamarine,hyprland"
      log::error "then record it:  echo <id> > \"$(_hypr_txn_file)\" && chmod 600 \"$(_hypr_txn_file)\""
      return 1
    fi
  else
    _hypr_rehearse_transaction || return 1
    local before after
    before="$(_hypr_history_max_id)"
    _hypr_dnf_install_local "$(_hypr_rpm_path)" || {
      log::error "hyprland package install failed"; return 1; }
    after="$(_hypr_history_max_id)"
    _hypr_record_txn_from_boundary "$before" "$after" || {
      log::error "packages installed but recording the rollback transaction failed; leaving state=installing"
      log::error "recover the id:  sudo dnf history list --contains-pkgs=aquamarine,hyprland"
      log::error "then record it:  echo <id> > \"$(_hypr_txn_file)\" && chmod 600 \"$(_hypr_txn_file)\""
      return 1
    }
  fi

  # Phase: config trees + wallpapers.
  if [ "$owned" -eq 1 ]; then
    _hypr_deploy_configs managed || return 1
  else
    _hypr_deploy_configs fresh || return 1
  fi
  _hypr_bake_wallpapers || { log::error "hyprland wallpaper bake failed"; return 1; }

  # Phase: watcher (fail-closed).
  _hypr_deploy_watcher || return 1

  # Phase: re-verify everything before promoting the marker.
  _hypr_configs_match || { log::error "hyprland config deploy mismatch"; return 1; }
  _hypr_wallpapers_match || { log::error "hyprland wallpapers missing after bake"; return 1; }
  _hypr_txn_ok || { log::error "hyprland dnf history id unusable"; return 1; }
  _hypr_hyprland_present || { log::error "hyprland not present after install"; return 1; }
  _hypr_aquamarine_installed || { log::error "aquamarine not installed after transaction"; return 1; }
  _hypr_watcher_ok || { log::error "supersession watcher not healthy after deploy"; return 1; }

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
  _hypr_txn_ok || { log::error "hyprland rollback transaction missing or unrelated"; return 1; }
  _hypr_hyprland_present || { log::error "hyprland package/binary missing"; return 1; }
  _hypr_aquamarine_installed || { log::error "aquamarine package missing"; return 1; }
  _hypr_watcher_ok || { log::error "hyprland supersession watcher is not healthy"; return 1; }
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
  _hypr_deploy_configs managed || return 1
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
