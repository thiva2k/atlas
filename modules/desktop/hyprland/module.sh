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
# Per-tree ownership record. A config tree is Atlas-owned ONLY after Atlas has
# actually created it or adopted it byte-for-byte — never merely because a
# marker exists (RFC-0038 §6). This closes the crash-window laundering where an
# `installing` marker written before any tree existed would let a retry destroy
# foreign content that appeared in the gap. Mode 600, atomic writes.
_hypr_owned_file() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/hypr-owned-trees"
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

# aquamarine is installed AND still the Atlas .atlas1 local build (vs a later
# official rebuild that superseded it via `dnf upgrade`, RFC-0038 §9). The
# release is pinned to exactly 2.fc44.atlas1 (RFC-0038 §5), so ownership keys off
# the exact `.atlas1` suffix, never a looser `.atlas*` glob.
_hypr_aquamarine_is_atlas() {
  local rel
  rel="$(rpm -q --qf '%{RELEASE}' aquamarine 2>/dev/null || true)"
  case "$rel" in *.atlas1) return 0 ;; *) return 1 ;; esac
}

# Per-tree config ownership. A tree name is present in the record iff Atlas
# created or adopted that exact tree. Consulted before any destructive rewrite.
_hypr_tree_owned() {
  local d="$1" f
  f="$(_hypr_owned_file)"
  [ -f "$f" ] && [ ! -L "$f" ] || return 1
  grep -qxF "$d" "$f" 2>/dev/null
}
_hypr_mark_tree_owned() {
  local d="$1" f dir tmp
  _hypr_tree_owned "$d" && return 0
  f="$(_hypr_owned_file)"
  dir="$(dirname "$f")"
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" 2>/dev/null || true
  tmp="$(mktemp "$dir/.hypr-owned.XXXXXX")" || return 1
  { [ -f "$f" ] && cat "$f"; printf '%s\n' "$d"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$f" || { rm -f "$tmp"; return 1; }
}
_hypr_clear_owned() { rm -f "$(_hypr_owned_file)" 2>/dev/null || true; }

_hypr_files_same() { [ "$(_hypr_sha256 "$1")" = "$(_hypr_sha256 "$2")" ]; }

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

# A full directory manifest: every entry with its type, plus a content hash for
# regular files. Directories (incl. empty ones) are listed so an added/removed
# empty dir is detected; ANY symlink, device, socket, or fifo anywhere in the
# tree makes the manifest fail closed (return 1) so such a tree can never be
# treated as byte-identical, adopted, or later destroyed. NUL-delimited find
# output keeps unusual (but in-tree) filenames from corrupting the comparison.
_hypr_tree_manifest() {
  local root="$1" bad
  [ -d "$root" ] && [ ! -L "$root" ] || return 1
  # Reject anything that is neither a regular file nor a directory (symlinks,
  # devices, sockets, fifos). -print -quit stops at the first offender.
  bad="$(cd "$root" && find . -mindepth 1 ! -type d ! -type f -print -quit 2>/dev/null)"
  [ -n "$bad" ] && return 1
  (
    cd "$root" || exit 1
    find . -mindepth 1 -type d -printf 'd %p\n' 2>/dev/null | LC_ALL=C sort
    find . -mindepth 1 -type f -print0 2>/dev/null | LC_ALL=C sort -z |
      while IFS= read -r -d '' p; do
        printf 'f %s %s\n' "$(_hypr_sha256 "$p")" "$p"
      done
  ) 2>/dev/null
}

_hypr_tree_matches() {
  local name="$1" src dst sm dm
  src="$(_hypr_cfg_src "$name")"
  dst="$(_hypr_cfg_dst "$name")"
  [ -d "$src" ] && [ ! -L "$src" ] || return 1
  [ -d "$dst" ] && [ ! -L "$dst" ] || return 1
  sm="$(_hypr_tree_manifest "$src")" || return 1
  dm="$(_hypr_tree_manifest "$dst")" || return 1
  [ "$sm" = "$dm" ]
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

# A wallpaper file is Atlas-owned iff the sidecar records it. The sidecar is
# written only after Atlas actually bakes/stages the file, so — like the config
# ownership record — it is never implied by a marker alone.
_hypr_wall_owned() {
  local f="$1" side line name
  side="$(_hypr_wall_dir)/.atlas-hypr-wall.sha256"
  [ -f "$side" ] && [ ! -L "$side" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    name="${line##* }"; name="${name#./}"
    [ "$name" = "$f" ] && return 0
  done < "$side"
  return 1
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

# Bake expected wallpapers into a temp dir (the ONLY tested seam for the PNG
# bake; the safety wrapper around it in _hypr_bake_wallpapers runs for real).
_hypr_preview_bake_wallpapers() {
  local out="$1"
  mkdir -p "$out" || return 1
  ATLAS_WALL_OUT="$out" bash "$_HYPR_ASSETS_DIR/generate.sh" >/dev/null 2>&1
}

# Ownership/adoption/refusal gate, run BEFORE any package mutation on EVERY
# install path (RFC-0038 §6/§7/§8 step 3). Ownership is decided per target from
# the durable ownership records, never from the marker: a config tree or
# wallpaper may be touched only when it is absent, already Atlas-owned, or
# byte-identical to Atlas source (adoptable). Anything else — including content
# that appeared in the crash window after an `installing` marker was written but
# before Atlas created the tree — is refused, never destroyed. Symlinked targets
# are refused outright (they could redirect a write anywhere).
_hypr_preflight_targets() {
  local d src dst f tmp
  for d in $_HYPR_CONFIG_TREES; do
    src="$(_hypr_cfg_src "$d")"
    dst="$(_hypr_cfg_dst "$d")"
    [ -d "$src" ] || { log::error "missing staged config: $src"; return 1; }
    if [ -L "$dst" ]; then
      log::error "refusing: managed config path is a symlink: $dst"; return 1
    fi
    [ -e "$dst" ] || continue
    _hypr_tree_owned "$d" && continue
    _hypr_tree_matches "$d" && continue
    log::error "refusing to overwrite unmanaged differing config: $dst"
    return 1
  done

  # Wallpapers: reject symlinked targets; adopt owned or byte-identical; refuse
  # anything else. Only the two named files are ever inspected (RFC-0038 §7).
  local need_bake=0
  for f in $_HYPR_WALLPAPERS; do
    dst="$(_hypr_wall_dst "$f")"
    if [ -L "$dst" ]; then
      log::error "refusing: managed wallpaper path is a symlink: $dst"; return 1
    fi
    [ -e "$dst" ] || continue
    _hypr_wall_owned "$f" && continue
    need_bake=1
  done
  if [ "$need_bake" -eq 1 ]; then
    tmp="$(mktemp -d)" || return 1
    if ! _hypr_preview_bake_wallpapers "$tmp"; then
      rm -rf "$tmp"; log::error "cannot bake wallpapers to validate adoption"; return 1
    fi
    for f in $_HYPR_WALLPAPERS; do
      dst="$(_hypr_wall_dst "$f")"
      [ -e "$dst" ] || continue
      _hypr_wall_owned "$f" && continue
      if ! _hypr_files_same "$dst" "$tmp/$f"; then
        rm -rf "$tmp"
        log::error "refusing to overwrite unmanaged differing wallpaper: $dst"; return 1
      fi
    done
    rm -rf "$tmp"
  fi
  return 0
}

# Deploy the five config trees from Atlas source. Ownership is per-tree and
# durable (RFC-0038 §6): a differing tree is rewritten ONLY when Atlas already
# owns it (recorded drift reconciliation). A tree that is absent is created and
# recorded as owned; a byte-identical tree is adopted (recorded, not rewritten);
# an unowned, differing tree is refused loudly — Atlas never rm -rf's content it
# has not proven it owns, even under an `installing`/`installed` marker. This is
# the same safety on every path (fresh, reconcile, update), so the mode argument
# is gone.
_hypr_deploy_configs() {
  local d src dst
  for d in $_HYPR_CONFIG_TREES; do
    src="$(_hypr_cfg_src "$d")"
    dst="$(_hypr_cfg_dst "$d")"
    [ -d "$src" ] || { log::error "missing staged config: $src"; return 1; }
    if [ -L "$dst" ]; then
      log::error "refusing: managed config path is a symlink: $dst"; return 1
    fi
    if [ ! -e "$dst" ]; then
      mkdir -p "$(dirname "$dst")" || return 1
      cp -a "$src" "$dst" || return 1
      _hypr_mark_tree_owned "$d" || return 1
      continue
    fi
    if _hypr_tree_matches "$d"; then
      _hypr_mark_tree_owned "$d" || return 1
      continue
    fi
    if _hypr_tree_owned "$d"; then
      rm -rf "$dst" || return 1
      cp -a "$src" "$dst" || return 1
      continue
    fi
    log::error "config tree changed under us or is not Atlas-owned; refusing to overwrite: $dst"
    return 1
  done
}

# Bake the two wallpapers and stage them symlink-safely and atomically. The PNG
# bake itself (generate.sh) is a seam; everything protective around it runs for
# real: a symlinked target is refused, an unowned differing target is refused
# (a race after preflight), and each file is renamed into place from a same-dir
# temp so a reader never sees a partial write.
_hypr_bake_wallpapers() {
  local dir tmp f src dst
  dir="$(_hypr_wall_dir)"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp -d)" || return 1
  if ! _hypr_preview_bake_wallpapers "$tmp"; then
    rm -rf "$tmp"; log::error "hyprland wallpaper bake failed"; return 1
  fi
  for f in $_HYPR_WALLPAPERS; do
    src="$tmp/$f"
    dst="$(_hypr_wall_dst "$f")"
    if [ ! -f "$src" ]; then
      rm -rf "$tmp"; log::error "baked wallpaper missing: $f"; return 1
    fi
    if [ -L "$dst" ]; then
      rm -rf "$tmp"; log::error "refusing to write wallpaper through a symlink: $dst"; return 1
    fi
    if [ -e "$dst" ] && ! _hypr_wall_owned "$f" && ! _hypr_files_same "$dst" "$src"; then
      rm -rf "$tmp"; log::error "refusing to overwrite unmanaged wallpaper: $dst"; return 1
    fi
    if ! _hypr_install_file "$src" "$dst" 644; then
      rm -rf "$tmp"; return 1
    fi
  done
  rm -rf "$tmp"
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
  # EXACT soname capabilities: the soname must be followed by the rpm decoration
  # `(...)`, end-of-line, or whitespace — never another digit — so `.so.3` never
  # matches `.so.30` and `.so.8` never matches `.so.80`.
  rpm -qp --requires "$rpm" 2>/dev/null | grep -Eq 'libdisplay-info\.so\.3(\(|$|[[:space:]])' || return 1
  rpm -qp --requires "$rpm" 2>/dev/null | grep -Eq 'libdisplay-info\.so\.2(\(|$|[[:space:]])' && return 1
  rpm -qp --provides "$rpm" 2>/dev/null | grep -Eq 'libaquamarine\.so\.8(\(|$|[[:space:]])' || return 1
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

# Fail-closed parser for a resolved dnf5 transaction plan. It requires a
# recognized transaction plan to be present at all, rejects any removal,
# erasure, obsoletion/"replacing", or downgrade, and permits an upgrade OR
# reinstall only for a package on the exact hypr/aquamarine allowlist. Plain
# installs (including dependencies) are additive and always allowed. Any
# unrecognized non-indented line that looks like an operation heading (ends in
# ":") is treated as an unknown mutation and rejected — the parser never
# silently ignores a section it does not understand.
_hypr_rehearse_output_ok() {
  local out="$1" raw line section="" name indented saw_plan=0
  while IFS= read -r raw || [ -n "$raw" ]; do
    case "$raw" in
      " "*|$'\t'*) indented=1 ;;
      *) indented=0 ;;
    esac
    line="${raw#"${raw%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    if [ "$indented" -eq 0 ]; then
      [ -z "$line" ] && { section=""; continue; }
      case "$line" in
        "Installing:"|"Installing dependencies:"|"Installing weak dependencies:") section=install; saw_plan=1 ;;
        "Reinstalling:") section=reinstall; saw_plan=1 ;;
        "Upgrading:") section=upgrade; saw_plan=1 ;;
        "Downgrading:") section=downgrade; saw_plan=1 ;;
        "Removing:"|"Removing dependent packages:"|"Removing unused dependencies:") section=remove; saw_plan=1 ;;
        "Obsoleting:") section=obsolete; saw_plan=1 ;;
        "Transaction Summary:") section=summary ;;
        *)
          # Prose/column-header lines are fine; an unknown "...:" heading is not.
          case "$line" in
            *:) return 1 ;;
            *) section="" ;;
          esac
          ;;
      esac
      continue
    fi
    # Indented line: a package row, a "replacing ..." note, or a summary detail.
    case "$line" in
      [Rr]eplacing\ *) return 1 ;;
    esac
    [ -n "$section" ] || continue
    name="$(printf '%s\n' "$line" | awk '{print $1}')"
    [ -z "$name" ] && continue
    case "$name" in Package|Name) continue ;; esac
    case "$section" in
      summary) : ;;
      remove|obsolete|downgrade) return 1 ;;
      upgrade|reinstall) _hypr_pkg_allowed "$name" || return 1 ;;
      install) : ;;
      *) return 1 ;;
    esac
  done <<< "$out"
  [ "$saw_plan" -eq 1 ] || return 1
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

# Newest dnf history transaction id as a before/after boundary anchor. dnf5
# `history list` is newest-first, so the first data row holds the max id.
# Prints the max numeric id, or "0" when history is CONFIRMED empty (a real
# table header with no data rows). Exits NON-ZERO when the command fails or the
# output is unparseable — so a genuine lookup failure is never mistaken for an
# empty history (which would let a stale id be recorded). Unprivileged.
_hypr_history_max_id() {
  local out body first tok
  out="$(dnf history list 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  body="$(printf '%s\n' "$out" | tail -n +2 | sed '/^[[:space:]]*$/d')"
  if [ -z "$body" ]; then
    printf '0\n'; return 0
  fi
  first="$(printf '%s\n' "$body" | head -n1)"
  tok="$(printf '%s\n' "$first" | awk '{print $1}')"
  case "$tok" in ""|*[!0-9]*) return 1 ;; esac
  printf '%s\n' "$tok"
}

# Strict identity check for a recorded rollback transaction. Parses the stable,
# documented dnf5 JSON (`dnf history info <id> --json`) and requires:
#   - exactly one transaction whose id equals <id>,
#   - status "Ok" (a failed/aborted transaction is never a valid rollback point),
#   - an Install of the EXACT aquamarine NEVRA (name/version/release/arch),
#   - an Install of hyprland,
#   - every altered package is additive: only Install is unconditional; Upgrade/
#     Reinstall are allowed solely for the exact hypr/aquamarine allowlist; any
#     Remove/Downgrade/Obsolete/Reinstall of anything else, or any unknown
#     action, fails closed.
# Proves the recorded id is really this module's install, not an unrelated,
# newer, or partially-failed global transaction (RFC-0038 §8 step 8 / §10.3).
_hypr_txn_contains_expected() {
  local id="$1" json
  _hypr_txn_id_valid "$id" || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  json="$(dnf history info "$id" --json 2>/dev/null)" || return 1
  [ -n "$json" ] || return 1
  printf '%s' "$json" | python3 -c '
import json, sys
txid = sys.argv[1]
aq_v, aq_r, aq_a = sys.argv[2], sys.argv[3], sys.argv[4]
allow = set(sys.argv[5].split())
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not isinstance(data, list) or len(data) != 1:
    sys.exit(1)
t = data[0]
try:
    if int(t.get("id", -1)) != int(txid):
        sys.exit(1)
except Exception:
    sys.exit(1)
if str(t.get("status", "")).strip().lower() != "ok":
    sys.exit(1)
pkgs = t.get("packages")
if not isinstance(pkgs, list) or not pkgs:
    sys.exit(1)
def parse(nevra):
    try:
        rest, arch = nevra.rsplit(".", 1)
        rest, rel = rest.rsplit("-", 1)
        name, ev = rest.rsplit("-", 1)
    except ValueError:
        return None
    ver = ev.split(":", 1)[1] if ":" in ev else ev
    return name, ver, rel, arch
FORBID = {"remove", "removed", "erase", "erased", "downgrade", "downgraded",
          "obsolete", "obsoleted"}
INSTALL = {"install", "installed", "install (dependency)"}
UPGRADE = {"upgrade", "upgraded", "reinstall", "reinstalled", "replaced"}
have_aq = have_hypr = False
for p in pkgs:
    nevra = str(p.get("nevra", ""))
    action = str(p.get("action", "")).strip().lower()
    parsed = parse(nevra)
    name = parsed[0] if parsed else ""
    if action in FORBID:
        sys.exit(1)
    if action in INSTALL:
        if parsed and name == "aquamarine":
            if (parsed[1], parsed[2], parsed[3]) == (aq_v, aq_r, aq_a):
                have_aq = True
        if name == "hyprland":
            have_hypr = True
        continue
    if action in UPGRADE:
        if name not in allow:
            sys.exit(1)
        continue
    sys.exit(1)  # unknown action: fail closed
sys.exit(0 if (have_aq and have_hypr) else 1)
' "$id" "$_HYPR_AQ_VERSION" "$_HYPR_AQ_RELEASE" "$_HYPR_AQ_ARCH" "$_HYPR_AQ_NAME ${_HYPR_PACKAGES[*]}"
}

# The recorded rollback transaction file is a regular (non-symlink) mode-600
# file holding a numeric id that still exists in dnf history and corresponds to
# this module's install (identity, not merely well-formedness).
_hypr_txn_ok() {
  local path id mode
  path="$(_hypr_txn_file)"
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  mode="$(stat -c '%a' "$path" 2>/dev/null)" || return 1
  [ "$mode" = "600" ] || return 1
  id="$(tr -d '[:space:]' < "$path" 2>/dev/null || true)"
  _hypr_txn_id_valid "$id" || return 1
  _hypr_txn_contains_expected "$id"
}

# Record the transaction produced by THIS invocation, using a before/after
# history boundary. Both boundary reads MUST have succeeded (the caller passes
# the captured values only when `_hypr_history_max_id` exited 0). Rejects: a
# malformed boundary, no new transaction (after not strictly greater than
# before), or a newest id that is not our exact aquamarine/hyprland install.
# Atomic write, mode 600.
_hypr_record_txn_from_boundary() {
  local before="$1" after="$2" path dir tmp
  path="$(_hypr_txn_file)"
  dir="$(dirname "$path")"
  case "$before" in ""|*[!0-9]*)
    log::error "dnf history boundary before-value is malformed (got '${before:-empty}')"; return 1 ;;
  esac
  _hypr_txn_id_valid "$after" || {
    log::error "dnf history returned no usable id after install (got '${after:-empty}')"; return 1; }
  [ "$after" -gt "$before" ] || {
    log::error "no new dnf transaction recorded (before=$before after=$after)"; return 1; }
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

# Install <src> to <dst> with <mode>, never writing THROUGH a symlink and always
# atomically: a differing dst symlink is refused (it could point anywhere), and
# the content is staged in a same-directory temp then renamed into place so a
# concurrent reader never sees a half-written file and dst is never a truncation
# window. Idempotent: identical content is left byte-for-byte unchanged.
_hypr_install_file() {
  local src="$1" dst="$2" mode="$3" dir tmp
  [ -f "$src" ] || { log::error "missing source file: $src"; return 1; }
  if [ -L "$dst" ]; then
    log::error "refusing to write through a symlink: $dst"; return 1
  fi
  if [ -e "$dst" ] && [ ! -f "$dst" ]; then
    log::error "refusing to overwrite a non-regular file: $dst"; return 1
  fi
  if [ -f "$dst" ] && _hypr_files_same "$src" "$dst"; then
    chmod "$mode" "$dst" 2>/dev/null || true
    return 0
  fi
  dir="$(dirname "$dst")"
  mkdir -p "$dir" || return 1
  tmp="$(mktemp "$dir/.hypr-deploy.XXXXXX")" || return 1
  cp -f "$src" "$tmp" || { rm -f "$tmp"; return 1; }
  chmod "$mode" "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$dst" || { rm -f "$tmp"; return 1; }
}

# Deploy the watcher, fail-closed on every safety-critical step (RFC-0038 §9).
# Files are placed symlink-safely and atomically (_hypr_install_file).
_hypr_deploy_watcher() {
  local bin units
  bin="$(_hypr_watcher_dst)"
  units="$(_hypr_units_dir)"
  mkdir -p "$(dirname "$bin")" "$units" || { log::error "cannot create watcher directories"; return 1; }
  _hypr_install_file "$_HYPR_ASSETS_DIR/watch-availability.sh" "$bin" 755 || {
    log::error "cannot deploy watcher script"; return 1; }
  _hypr_install_file "$_HYPR_ASSETS_DIR/atlas-hypr-check.service" \
    "$units/atlas-hypr-check.service" 644 || { log::error "cannot deploy watcher service unit"; return 1; }
  _hypr_install_file "$_HYPR_ASSETS_DIR/atlas-hypr-check.timer" \
    "$units/atlas-hypr-check.timer" 644 || { log::error "cannot deploy watcher timer unit"; return 1; }
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

  # Ownership/adoption gate runs on EVERY path, BEFORE any mutation. Ownership is
  # decided per target from durable records (not the marker), so a tree or
  # wallpaper that appeared in an interrupted run's crash window — or any other
  # unowned differing content — is refused here, before the COPR is enabled, the
  # RPM is built, or dnf runs (RFC-0038 §8 step 3).
  _hypr_preflight_targets || return 1

  _hypr_marker_write installing || return 1

  # Phase: the ONE real package transaction (RFC-0038 §8). Detect a completed
  # transaction FIRST, before any repository/build/package mutation: an
  # interrupted retry that already installed the packages must neither run a
  # second dnf transaction nor perform any other package mutation (e.g. pulling
  # in dnf-plugins-core) on the way to noticing they are present.
  if _hypr_packages_installed; then
    log::info "hypr packages already installed; not re-running the package transaction"
    if ! _hypr_txn_ok; then
      log::error "packages are installed but no valid rollback transaction is recorded; leaving state=installing"
      log::error "recover the id:  sudo dnf history list --contains-pkgs=aquamarine,hyprland"
      log::error "then record it:  echo <id> > \"$(_hypr_txn_file)\" && chmod 600 \"$(_hypr_txn_file)\""
      return 1
    fi
  else
    # Phase: COPR repository (idempotent).
    _hypr_write_repo || return 1

    # Phase: aquamarine artifact — build only if the gate does not already pass;
    # a pre-existing artifact is always re-validated, never trusted by name.
    if ! _hypr_rpm_gate "$(_hypr_rpm_path)"; then
      _hypr_build_rpm || { log::error "aquamarine build failed"; return 1; }
      _hypr_rpm_gate "$(_hypr_rpm_path)" || {
        log::error "aquamarine RPM failed the NEVRA/soname/integrity gate after build"; return 1; }
    fi

    _hypr_rehearse_transaction || return 1
    local before after
    before="$(_hypr_history_max_id)" || {
      log::error "cannot read dnf history boundary before install; aborting before any package mutation"
      return 1; }
    _hypr_dnf_install_local "$(_hypr_rpm_path)" || {
      log::error "hyprland package install failed"; return 1; }
    after="$(_hypr_history_max_id)" || {
      log::error "packages installed but the dnf history boundary is unreadable; leaving state=installing"
      log::error "recover the id:  sudo dnf history list --contains-pkgs=aquamarine,hyprland"
      log::error "then record it:  echo <id> > \"$(_hypr_txn_file)\" && chmod 600 \"$(_hypr_txn_file)\""
      return 1; }
    _hypr_record_txn_from_boundary "$before" "$after" || {
      log::error "packages installed but recording the rollback transaction failed; leaving state=installing"
      log::error "recover the id:  sudo dnf history list --contains-pkgs=aquamarine,hyprland"
      log::error "then record it:  echo <id> > \"$(_hypr_txn_file)\" && chmod 600 \"$(_hypr_txn_file)\""
      return 1
    }
  fi

  # Phase: config trees + wallpapers. Deploy is per-tree ownership-safe on every
  # path, so no fresh/managed mode is needed.
  _hypr_deploy_configs || return 1
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
  _hypr_clear_owned

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
