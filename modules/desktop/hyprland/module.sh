#!/usr/bin/env bash
# desktop/hyprland — the B&W Atlas Hyprland session, installed via a locally
# rebuilt aquamarine (0.9.5-2.fc44.atlas1, linked against libdisplay-info.so.3).
# Owns: the COPR intent, the local aquamarine RPM install, the hypr* package set,
# the five ~/.config trees, and the wallpaper bake. Does NOT own user config or
# uninstall packages on remove (detach only; package rollback is dnf history undo).
MODULE_NAME="hyprland"
MODULE_DESCRIPTION="Atlas Hyprland desktop: local aquamarine rebuild + hypr stack + B&W configs."
MODULE_DEPENDS=()

_HYPR_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_HYPR_CONFIG_TREES="hypr waybar wofi mako kitty"
_HYPR_PACKAGES="hyprland xdg-desktop-portal-hyprland hyprlock hypridle hyprpaper waybar wofi mako kitty grim slurp brightnessctl playerctl"

_hypr_marker() { printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/desktop-hyprland"; }
_hypr_rpm_path() { printf '%s\n' "$HOME/atlas-hypr-rpms/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"; }
_hypr_cfg_src() { printf '%s\n' "$_HYPR_MODULE_DIR/config/$1"; }
_hypr_cfg_dst() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/$1"; }
_hypr_run_privileged() { if os::is_root; then "$@"; else sudo "$@"; fi; }
_hypr_hyprland_present() { os::has_cmd Hyprland || rpm -q hyprland >/dev/null 2>&1; }
_hypr_build_rpm() { bash "$_HYPR_MODULE_DIR/build/build-aquamarine.sh"; }
_hypr_bake_wallpapers() { bash "$_HYPR_MODULE_DIR/assets/generate.sh" >/dev/null 2>&1 || log::warn "wallpaper bake skipped"; }

_HYPR_ASSETS_DIR="$_HYPR_MODULE_DIR/assets"
_hypr_watcher_dst() { printf '%s\n' "$HOME/.local/bin/atlas-hypr-check.sh"; }  # matches the unit's %h/.local/bin ExecStart
_hypr_units_dir()   { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"; }

_hypr_deploy_watcher() {
  local bin units; bin="$(_hypr_watcher_dst)"; units="$(_hypr_units_dir)"
  mkdir -p "$(dirname "$bin")" "$units" || return 1
  cp "$_HYPR_ASSETS_DIR/watch-availability.sh" "$bin" || return 1
  chmod +x "$bin" || return 1
  cp "$_HYPR_ASSETS_DIR/atlas-hypr-check.service" "$_HYPR_ASSETS_DIR/atlas-hypr-check.timer" "$units/" || return 1
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now atlas-hypr-check.timer >/dev/null 2>&1 || true
}

_hypr_undeploy_watcher() {
  systemctl --user disable --now atlas-hypr-check.timer >/dev/null 2>&1 || true
  rm -f "$(_hypr_watcher_dst)" "$(_hypr_units_dir)/atlas-hypr-check.service" "$(_hypr_units_dir)/atlas-hypr-check.timer" || true
  systemctl --user daemon-reload >/dev/null 2>&1 || true
}

# Install the locally-built aquamarine RPM + the hypr stack in one dnf transaction.
_hypr_dnf_install_local() {
  local rpm="$1"
  [ -f "$rpm" ] || { log::error "aquamarine RPM not built: $rpm (run build/build-aquamarine.sh)"; return 1; }
  # shellcheck disable=SC2086
  _hypr_run_privileged dnf install -y "$rpm" $_HYPR_PACKAGES
}

# --- directory manifest (drift detection over all five trees) ---------------
_hypr_manifest_src() { local d; for d in $_HYPR_CONFIG_TREES; do (cd "$(_hypr_cfg_src "$d")" 2>/dev/null && find . -type f -print | sort | xargs -r sha256sum | sed "s#\$# [$d]#"); done; }
_hypr_manifest_dst() { local d; for d in $_HYPR_CONFIG_TREES; do (cd "$(_hypr_cfg_dst "$d")" 2>/dev/null && find . -type f -print | sort | xargs -r sha256sum | sed "s#\$# [$d]#"); done; }
_hypr_configs_match() { [ "$(_hypr_manifest_src)" = "$(_hypr_manifest_dst)" ]; }

_hypr_deploy_configs() {
  local d src dst
  for d in $_HYPR_CONFIG_TREES; do
    src="$(_hypr_cfg_src "$d")"; dst="$(_hypr_cfg_dst "$d")"
    [ -d "$src" ] || { log::error "missing staged config: $src"; return 1; }
    mkdir -p "$(dirname "$dst")" || return 1
    rm -rf "$dst" || return 1
    cp -a "$src" "$dst" || return 1
  done
}

# --- marker (schema + state machine, atomic writes; ghostty pattern) --------
_hypr_marker_load() {  # sets _HYPR_STATE to absent|installing|installed|detached
  _HYPR_STATE=absent
  local m; m="$(_hypr_marker)"; [ -e "$m" ] || return 0
  [ -f "$m" ] && [ ! -L "$m" ] && [ -r "$m" ] || { log::error "hyprland marker not a readable file"; return 1; }
  [ "$(stat -c '%a' "$m" 2>/dev/null)" = 600 ] || { log::error "hyprland marker mode must be 600"; return 1; }
  local line s=0 t=0 val
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"; case "$line" in ""|\#*) continue ;; esac
    case "$line" in
      schema=1) s=1 ;;
      state=*) val="${line#state=}"; case "$val" in installing|installed|detached) _HYPR_STATE="$val" ;; *) return 1 ;; esac; t=1 ;;
      *) return 1 ;;
    esac
  done < "$m"
  [ "$s" -eq 1 ] && [ "$t" -eq 1 ]
}
_hypr_marker_write() {
  local state="$1" m dir tmp; m="$(_hypr_marker)"; dir="$(dirname "$m")"
  mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
  tmp="$(mktemp "$dir/.desktop-hyprland.XXXXXX")" || return 1
  { printf 'schema=1\nstate=%s\n' "$state"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
  mv -f "$tmp" "$m" || { rm -f "$tmp"; return 1; }
}

module::check() {
  _hypr_marker_load || return 1
  [ "$_HYPR_STATE" = installed ] || return 1
  _hypr_hyprland_present || return 1
  _hypr_configs_match || return 1
}

module::install() {
  os::is_fedora || { log::error "hyprland module supports Fedora only"; return 1; }
  _hypr_marker_load || return 1
  _hypr_marker_write installing || return 1
  [ -f "$(_hypr_rpm_path)" ] || _hypr_build_rpm || { log::error "aquamarine build failed"; return 1; }
  _hypr_dnf_install_local "$(_hypr_rpm_path)" || { log::error "hyprland package install failed"; return 1; }
  _hypr_deploy_configs || return 1
  _hypr_bake_wallpapers || true
  _hypr_deploy_watcher || log::warn "supersession watcher not activated"
  _hypr_configs_match || return 1
  _hypr_marker_write installed || return 1
  log::info "Atlas Hyprland is installed; pick it at the login screen"
}

module::verify() {
  _hypr_marker_load || return 1
  case "$_HYPR_STATE" in
    absent|detached) return 0 ;;
    installing) log::error "hyprland install incomplete; rerun install"; return 1 ;;
  esac
  _hypr_configs_match || { log::error "hyprland managed config has drifted"; return 1; }
  log::info "Atlas Hyprland config is healthy"
}

module::update() {
  _hypr_marker_load || return 1
  case "$_HYPR_STATE" in
    absent|detached) return 0 ;;
    installing) log::error "hyprland install incomplete; rerun install"; return 1 ;;
  esac
  _hypr_deploy_configs || return 1
  _hypr_marker_write installed || return 1
  _hypr_configs_match
}

module::remove() {  # detach: drop Atlas-owned configs; leave packages (rollback = dnf history undo)
  _hypr_marker_load || return 1
  case "$_HYPR_STATE" in absent|detached) return 0 ;; esac
  local d txn
  for d in $_HYPR_CONFIG_TREES; do rm -rf "$(_hypr_cfg_dst "$d")" || return 1; done
  _hypr_undeploy_watcher
  _hypr_marker_write detached || return 1
  txn="${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/hypr-install-txn"
  if [ -f "$txn" ]; then
    log::info "detached Hyprland configs; packages remain — roll them back with: sudo dnf history undo $(cat "$txn")"
  else
    log::info "detached Hyprland configs; packages remain — to roll them back, find the aquamarine+hyprland install in 'sudo dnf history' and run 'sudo dnf history undo <id>'"
  fi
}

module::backup() { log::info "nothing to back up: desktop/hyprland is reconstructable"; }
module::restore() { log::info "nothing to restore: reinstall desktop/hyprland"; }
