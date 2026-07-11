#!/usr/bin/env bash
# development/docker - RFC-0005.
#
# Atlas owns the Docker Engine installation boundary: the Docker CE repository
# file it writes, the package/service intent recorded in its marker, and
# rootful systemd enablement. It never owns workloads or user Docker config.
MODULE_NAME="docker"
MODULE_DESCRIPTION="Docker Engine: installs Docker CE and enables the rootful system service."
MODULE_DEPENDS=()

_DOCKER_MODULE_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_DOCKER_PACKAGES=(docker-ce docker-ce-cli containerd.io docker-compose-plugin)
_DOCKER_REPO_ID="docker-ce-stable"
_DOCKER_REPO_URL='https://download.docker.com/linux/fedora/$releasever/$basearch/stable'
_DOCKER_GPG_URL="https://download.docker.com/linux/fedora/gpg"
_DOCKER_KEY_FP="060A61C51B558A7F742B77AAC52FEB6B621E9F35"
_DOCKER_KEY_SHA256="e6c650e0700b1bf4868b693b30761b926844befc8a0acb7ac0dd9b1faf1b7423"

_docker_marker() {
  printf '%s\n' "${ATLAS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/atlas}/installed/development-docker"
}
_docker_repo_source() { printf '%s\n' "$_DOCKER_MODULE_DIR/config/docker-ce.repo"; }
_docker_key_source() { printf '%s\n' "$_DOCKER_MODULE_DIR/config/docker.asc"; }
_docker_repo_file() { printf '%s\n' "/etc/yum.repos.d/docker-ce.repo"; }
_docker_socket() { printf '%s\n' "/var/run/docker.sock"; }
_docker_cli() { printf '%s\n' "/usr/bin/docker"; }
_docker_daemon_json() { printf '%s\n' "/etc/docker/daemon.json"; }
_docker_dropin_dir() { printf '%s\n' "/etc/systemd/system/docker.service.d"; }
_docker_desktop_marker() { printf '%s\n' "/opt/docker-desktop"; }

_docker_sha256() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

_docker_run_privileged() {
  if os::is_root; then "$@"; else sudo "$@"; fi
}

_docker_fixed_env() {
  env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_CONFIG -u DOCKER_TLS \
      -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH PATH=/usr/bin:/bin "$@"
}

_docker_marker_init() {
  _DOCKER_MARKER_STATE=absent
  _DOCKER_MARKER_MODE=
  _DOCKER_MARKER_SOURCE=
  _DOCKER_MARKER_REPO_CREATED=
  _DOCKER_MARKER_REPO_SHA=
}

_docker_marker_load() {
  _docker_marker_init
  local marker line key val seen_schema=0 seen_state=0 seen_mode=0 seen_source=0 seen_created=0 seen_sha=0
  marker="$(_docker_marker)"
  [ -e "$marker" ] || return 0
  if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
    log::error "Docker marker is not a readable regular file: $marker"
    return 1
  fi
  local marker_mode
  marker_mode="$(stat -c '%a' "$marker" 2>/dev/null)" || { log::error "cannot inspect Docker marker mode"; return 1; }
  [ "$marker_mode" = "600" ] || { log::error "Docker marker mode must be 600: $marker"; return 1; }
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    case "$line" in
      *=*) key="${line%%=*}"; val="${line#*=}" ;;
      *) log::error "Docker marker has an invalid line: $line"; return 1 ;;
    esac
    case "$key" in
      schema) [ "$val" = "1" ] || { log::error "Docker marker schema is unsupported: $val"; return 1; }; seen_schema=1 ;;
      state)
        case "$val" in installing|installed|detached) _DOCKER_MARKER_STATE="$val" ;; *) log::error "Docker marker state is invalid: $val"; return 1 ;; esac
        seen_state=1
        ;;
      mode) _DOCKER_MARKER_MODE="$val"; seen_mode=1 ;;
      package_source) _DOCKER_MARKER_SOURCE="$val"; seen_source=1 ;;
      repo_created) case "$val" in 0|1) _DOCKER_MARKER_REPO_CREATED="$val" ;; *) log::error "Docker marker repo_created is invalid: $val"; return 1 ;; esac; seen_created=1 ;;
      repo_sha256) case "$val" in [0-9a-f][0-9a-f]*) _DOCKER_MARKER_REPO_SHA="$val" ;; *) log::error "Docker marker repo_sha256 is invalid"; return 1 ;; esac; seen_sha=1 ;;
      *) log::error "Docker marker has an unknown key: $key"; return 1 ;;
    esac
  done < "$marker"

  [ "$seen_schema" -eq 1 ] || { log::error "Docker marker is missing schema"; return 1; }
  [ "$seen_state" -eq 1 ] || { log::error "Docker marker is missing state"; return 1; }
  [ "$seen_mode" -eq 1 ] || { log::error "Docker marker is missing mode"; return 1; }
  [ "$seen_source" -eq 1 ] || { log::error "Docker marker is missing package_source"; return 1; }
  [ "$seen_created" -eq 1 ] || { log::error "Docker marker is missing repo_created"; return 1; }
  [ "$seen_sha" -eq 1 ] || { log::error "Docker marker is missing repo_sha256"; return 1; }
  [ "$_DOCKER_MARKER_MODE" = "rootful-system" ] || { log::error "Docker marker mode is unsupported: $_DOCKER_MARKER_MODE"; return 1; }
  [ "$_DOCKER_MARKER_SOURCE" = "$_DOCKER_REPO_ID" ] || { log::error "Docker marker package_source is unsupported: $_DOCKER_MARKER_SOURCE"; return 1; }
  local expected_repo_sha
  expected_repo_sha="$(_docker_sha256 "$(_docker_repo_source)")"
  [ -n "$expected_repo_sha" ] || { log::error "cannot hash Docker repo source"; return 1; }
  [ "$_DOCKER_MARKER_REPO_SHA" = "$expected_repo_sha" ] || { log::error "Docker marker repo_sha256 does not match Atlas source"; return 1; }
  return 0
}

_docker_marker_write() {
  local state="$1" marker dir tmp repo_sha
  marker="$(_docker_marker)"
  dir="$(dirname "$marker")"
  repo_sha="$(_docker_sha256 "$(_docker_repo_source)")"
  [ -n "$repo_sha" ] || { log::error "cannot hash Docker repo source"; return 1; }
  mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
  chmod 700 "$dir" || { log::error "cannot secure $dir"; return 1; }
  tmp="$(mktemp "$dir/.development-docker.XXXXXX")" || { log::error "cannot create a marker temp file in $dir"; return 1; }
  {
    printf 'schema=1\n'
    printf 'state=%s\n' "$state"
    printf 'mode=rootful-system\n'
    printf 'package_source=%s\n' "$_DOCKER_REPO_ID"
    printf 'repo_created=1\n'
    printf 'repo_sha256=%s\n' "$repo_sha"
  } > "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f "$tmp"; log::error "cannot secure $tmp"; return 1; }
  mv -f "$tmp" "$marker" || { rm -f "$tmp"; log::error "cannot replace $marker"; return 1; }
}

_docker_repo_source_valid() {
  local file="$(_docker_repo_source)"
  [ -r "$file" ] || { log::error "Docker repo source missing: $file"; return 1; }
  grep -qxF "[$_DOCKER_REPO_ID]" "$file" || { log::error "Docker repo source has wrong repo id"; return 1; }
  grep -qxF "baseurl=$_DOCKER_REPO_URL" "$file" || { log::error "Docker repo source has wrong baseurl"; return 1; }
  grep -qxF "gpgcheck=1" "$file" || { log::error "Docker repo source must enable gpgcheck"; return 1; }
  grep -qxF "gpgkey=$_DOCKER_GPG_URL" "$file" || { log::error "Docker repo source has wrong gpgkey"; return 1; }
}

_docker_repo_matches_source() {
  local dest="$(_docker_repo_file)" src="$(_docker_repo_source)"
  [ -f "$dest" ] || return 1
  [ "$(_docker_sha256 "$dest")" = "$(_docker_sha256 "$src")" ]
}

_docker_write_repo() {
  _docker_repo_source_valid || return 1
  local src dest dir tmp
  src="$(_docker_repo_source)"
  dest="$(_docker_repo_file)"
  if _docker_repo_matches_source; then
    log::info "Docker CE repository already matches Atlas source"
    return 0
  fi
  dir="$(dirname "$dest")"
  if [ -d "$dir" ] && [ -w "$dir" ]; then
    tmp="$(mktemp "$dir/.docker-ce.repo.XXXXXX")" || { log::error "cannot create repo temp file in $dir"; return 1; }
    cp "$src" "$tmp" || { rm -f "$tmp"; log::error "cannot write $tmp"; return 1; }
    chmod 644 "$tmp" || { rm -f "$tmp"; log::error "cannot chmod $tmp"; return 1; }
    mv -f "$tmp" "$dest" || { rm -f "$tmp"; log::error "cannot replace $dest"; return 1; }
  else
    _docker_run_privileged mkdir -p "$dir" || { log::error "cannot create $dir"; return 1; }
    tmp="$(_docker_run_privileged mktemp "$dir/.docker-ce.repo.XXXXXX")" || { log::error "cannot create privileged repo temp file in $dir"; return 1; }
    if ! _docker_run_privileged cp "$src" "$tmp"; then _docker_run_privileged rm -f "$tmp" 2>/dev/null || true; log::error "cannot write $tmp"; return 1; fi
    if ! _docker_run_privileged chmod 644 "$tmp"; then _docker_run_privileged rm -f "$tmp" 2>/dev/null || true; log::error "cannot chmod $tmp"; return 1; fi
    if ! _docker_run_privileged mv -f "$tmp" "$dest"; then _docker_run_privileged rm -f "$tmp" 2>/dev/null || true; log::error "cannot replace $dest"; return 1; fi
  fi
  log::info "wrote Docker CE repository: $dest"
  _docker_repo_matches_source || { log::error "Docker CE repository write did not match Atlas source"; return 1; }
}

_docker_key_present() {
  local fp
  fp="$(rpmkeys --list 2>/dev/null | awk '{print toupper($1)}' | tr -d '[:space:]')"
  case "$fp" in *"$_DOCKER_KEY_FP"*) return 0 ;; *) return 1 ;; esac
}

_docker_key_source_valid() {
  local key tmp fp
  key="$(_docker_key_source)"
  [ -r "$key" ] || { log::error "Docker RPM signing key source missing: $key"; return 1; }
  [ "$(_docker_sha256 "$key")" = "$_DOCKER_KEY_SHA256" ] || {
    log::error "Docker RPM signing key source hash does not match Atlas allowlist"; return 1; }
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/atlas-docker-rpm.XXXXXX")" || {
    log::error "cannot create a temporary RPM root"; return 1; }
  if ! rpmkeys --root "$tmp" --import "$key" >/dev/null 2>&1; then
    rm -rf "$tmp"
    log::error "Docker RPM signing key source cannot be parsed by rpmkeys"
    return 1
  fi
  fp="$(rpmkeys --root "$tmp" --list 2>/dev/null | awk '{print toupper($1)}' | tr -d '[:space:]')"
  rm -rf "$tmp"
  case "$fp" in
    "$_DOCKER_KEY_FP") return 0 ;;
    *) log::error "Docker RPM signing key source fingerprint does not match Atlas allowlist"; return 1 ;;
  esac
}

_docker_import_key() {
  _docker_key_source_valid || return 1
  if _docker_key_present; then
    log::info "Docker RPM signing key is already trusted"
    return 0
  fi
  _docker_run_privileged rpmkeys --import "$(_docker_key_source)" || { log::error "cannot import Docker RPM signing key"; return 1; }
  _docker_key_present || { log::error "Docker RPM signing key fingerprint did not match the Atlas allowlist"; return 1; }
}

_docker_packages_installed() {
  local pkg
  for pkg in "${_DOCKER_PACKAGES[@]}"; do
    rpm -q "$pkg" >/dev/null 2>&1 || return 1
  done
  return 0
}

_docker_cli_present() {
  local cli owner
  cli="$(_docker_cli)"
  [ -x "$cli" ] || return 1
  owner="$(rpm -qf "$cli" 2>/dev/null)" || return 1
  case "$owner" in
    docker-ce-cli-*) return 0 ;;
    *) return 1 ;;
  esac
}

_docker_compose_ok() {
  _docker_fixed_env "$(_docker_cli)" compose version >/dev/null 2>&1
}

_docker_service_enabled() { systemctl is-enabled --quiet docker.service >/dev/null 2>&1; }
_docker_service_active() { systemctl is-active --quiet docker.service >/dev/null 2>&1; }

_docker_socket_ok() {
  local sock owner group mode
  sock="$(_docker_socket)"
  [ -S "$sock" ] || { log::error "Docker socket is not a Unix socket: $sock"; return 1; }
  owner="$(stat -c '%u' "$sock" 2>/dev/null)" || { log::error "cannot inspect Docker socket owner"; return 1; }
  group="$(stat -c '%G' "$sock" 2>/dev/null)" || { log::error "cannot inspect Docker socket group"; return 1; }
  mode="$(stat -c '%a' "$sock" 2>/dev/null)" || { log::error "cannot inspect Docker socket mode"; return 1; }
  [ "$owner" = "0" ] || { log::error "Docker socket is not owned by root"; return 1; }
  [ "$group" = "docker" ] || { log::error "Docker socket group is not docker"; return 1; }
  case "$mode" in
    *[!0-7]*|"") log::error "Docker socket mode is invalid: $mode"; return 1 ;;
  esac
  [ $((8#$mode & 0007)) -eq 0 ] || { log::error "Docker socket is accessible by other users"; return 1; }
  [ $((8#$mode & 0117)) -eq 0 ] || { log::error "Docker socket grants executable or write permissions outside owner/group"; return 1; }
  [ $((8#$mode & 0660)) -eq $((8#$mode)) ] || { log::error "Docker socket mode is broader than 0660"; return 1; }
  return 0
}

_docker_probe_direct() {
  _docker_fixed_env "$(_docker_cli)" --host "unix://$(_docker_socket)" version >/dev/null 2>&1
}

_docker_probe_sudo_noninteractive() {
  sudo -n env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_CONFIG -u DOCKER_TLS \
    -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH PATH=/usr/bin:/bin \
    "$(_docker_cli)" --host "unix://$(_docker_socket)" version >/dev/null 2>&1
}

_docker_probe_privileged() {
  if os::is_root; then
    _docker_probe_direct
  else
    _docker_run_privileged env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_CONFIG -u DOCKER_TLS \
      -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH PATH=/usr/bin:/bin \
      "$(_docker_cli)" --host "unix://$(_docker_socket)" version >/dev/null 2>&1
  fi
}

_docker_api_ok_for_verify() {
  local sock
  sock="$(_docker_socket)"
  if [ -r "$sock" ] && [ -w "$sock" ]; then
    _docker_probe_direct || { log::error "Docker local API probe failed through the accessible Unix socket"; return 1; }
    log::info "Docker local API is reachable through the explicit Unix socket"
    return 0
  fi
  if _docker_probe_direct; then
    log::info "Docker local API is reachable through the explicit Unix socket"
    return 0
  fi
  if sudo -n true >/dev/null 2>&1; then
    _docker_probe_sudo_noninteractive || { log::error "Docker local API probe failed with available sudo"; return 1; }
    log::info "Docker local API is reachable through non-interactive sudo"
    return 0
  fi
  log::warn "Docker local API was not reachable by this user and sudo is not already authorized"
  log::warn "  fix: run 'sudo docker --host unix://$(_docker_socket) version' to verify daemon API access"
  return 0
}

_docker_user_config_present() {
  [ -e "$(_docker_daemon_json)" ] || [ -d "$(_docker_dropin_dir)" ]
}

_docker_proc_net_files() {
  printf '%s\n' /proc/net/tcp /proc/net/tcp6
}

_docker_proc_dirs() {
  local proc
  for proc in /proc/[0-9]*; do
    [ -d "$proc" ] && printf '%s\n' "$proc"
  done
}

_docker_tcp_listener_in_proc() {
  local -A listen=()
  local file line local_addr remote_addr state rest inode proc comm fd target sock_inode
  while IFS= read -r file; do
    [ -r "$file" ] || continue
    while read -r line; do
      case "$line" in sl*) continue ;; esac
      # shellcheck disable=SC2086
      set -- $line
      local_addr="${2:-}"; remote_addr="${3:-}"; state="${4:-}"; inode="${10:-}"
      [ -n "$local_addr$remote_addr" ] || continue
      [ "$state" = "0A" ] || continue
      case "$inode" in *[!0-9]*|"") continue ;; esac
      listen["$inode"]=1
    done < "$file"
  done < <(_docker_proc_net_files)
  [ "${#listen[@]}" -gt 0 ] || return 1

  while IFS= read -r proc; do
    [ -r "$proc/comm" ] || continue
    IFS= read -r comm < "$proc/comm" || continue
    [ "$comm" = "dockerd" ] || continue
    for fd in "$proc"/fd/*; do
      target="$(readlink "$fd" 2>/dev/null)" || continue
      case "$target" in
        socket:\[*\])
          sock_inode="${target#socket:[}"
          sock_inode="${sock_inode%]}"
          [ -n "${listen[$sock_inode]:-}" ] && return 0
          ;;
      esac
    done
  done < <(_docker_proc_dirs)
  return 1
}

_docker_tcp_listener_present() {
  _docker_tcp_listener_in_proc
}

_docker_rootless_active() {
  [ -S "${XDG_RUNTIME_DIR:-}/docker.sock" ] && return 0
  systemctl --user is-active --quiet docker.service >/dev/null 2>&1
}

_docker_desktop_present() {
  [ -e "$(_docker_desktop_marker)" ]
}

_docker_pkg_present() {
  rpm -q "$1" >/dev/null 2>&1
}

_docker_service_active_named() {
  systemctl is-active --quiet "$1" >/dev/null 2>&1
}

_docker_unit_exists() {
  systemctl cat "$1" >/dev/null 2>&1 || systemctl list-unit-files "$1" >/dev/null 2>&1
}

_docker_unmanaged_docker_present() {
  command -v docker >/dev/null 2>&1 && return 0
  _docker_pkg_present docker-ce && return 0
  _docker_pkg_present docker-ce-cli && return 0
  _docker_pkg_present moby-engine && return 0
  _docker_pkg_present podman-docker && return 0
  [ -S "$(_docker_socket)" ] && return 0
  _docker_unit_exists docker.service && return 0
  return 1
}

_docker_external_docker_conflict_present() {
  _docker_pkg_present moby-engine && return 0
  _docker_pkg_present podman-docker && return 0
  _docker_desktop_present && return 0
  return 1
}

_docker_runtime_conflict_present() {
  _docker_pkg_present containerd && return 0
  _docker_pkg_present cri-o && return 0
  _docker_pkg_present kubelet && return 0
  _docker_service_active_named containerd.service && return 0
  _docker_service_active_named crio.service && return 0
  _docker_service_active_named kubelet.service && return 0
  return 1
}

_docker_preflight_common() {
  os::is_fedora || { log::error "Docker module supports Fedora only"; return 1; }
  if [ -e "$(_docker_repo_file)" ]; then
    log::error "Docker repository file already exists and is not Atlas-owned: $(_docker_repo_file)"
    log::error "  fix: decide whether to remove or migrate the existing Docker repository manually, then re-run"
    return 1
  fi
  if _docker_user_config_present; then
    log::error "Docker daemon configuration already exists and is user-owned"
    log::error "  fix: review $(_docker_daemon_json) and $(_docker_dropin_dir); Atlas will not merge daemon policy"
    return 1
  fi
  if _docker_rootless_active; then
    log::error "rootless Docker is active for this user"
    log::error "  fix: choose rootless or rootful Docker explicitly; Atlas will not mix topologies"
    return 1
  fi
  if _docker_desktop_present; then
    log::error "Docker Desktop state detected"
    log::error "  fix: remove or migrate Docker Desktop manually before Atlas manages rootful Docker"
    return 1
  fi
  if _docker_runtime_conflict_present; then
    log::error "container runtime or Kubernetes conflict detected"
    log::error "  fix: decide manually before installing Docker's containerd.io package"
    return 1
  fi
  return 0
}

_docker_preflight_unmanaged() {
  _docker_preflight_common || return 1
  if _docker_unmanaged_docker_present; then
    log::error "Docker already exists but is not Atlas-owned"
    log::error "  fix: remove or migrate the existing Docker installation manually before Atlas claims ownership"
    return 1
  fi
  return 0
}

_docker_preflight_detached() {
  _docker_preflight_common || return 1
  if _docker_external_docker_conflict_present; then
    log::error "Docker conflict detected outside Atlas-detached Docker CE state"
    log::error "  fix: remove or migrate the conflicting Docker implementation manually before re-enrolling"
    return 1
  fi
  return 0
}

_docker_preflight_managed_repair() {
  if _docker_user_config_present; then
    log::error "Docker daemon configuration already exists and is user-owned"
    log::error "  fix: review $(_docker_daemon_json) and $(_docker_dropin_dir); Atlas will not repair across daemon policy it does not own"
    return 1
  fi
  if _docker_rootless_active; then
    log::error "rootless Docker is active for this user"
    log::error "  fix: choose rootless or rootful Docker explicitly; Atlas will not mix topologies"
    return 1
  fi
  if _docker_external_docker_conflict_present; then
    log::error "Docker conflict detected outside Atlas-managed Docker CE state"
    log::error "  fix: remove or migrate the conflicting Docker implementation manually before repairing Atlas-managed Docker"
    return 1
  fi
  if _docker_runtime_conflict_present; then
    log::error "container runtime or Kubernetes conflict detected"
    log::error "  fix: decide manually before repairing Docker's containerd.io package"
    return 1
  fi
  if _docker_tcp_listener_present; then
    log::error "Docker TCP listener detected"
    log::error "  fix: remove unsupported daemon exposure before repairing Atlas-managed Docker"
    return 1
  fi
  return 0
}

_docker_verify_managed() {
  _docker_marker_load || return 1
  case "$_DOCKER_MARKER_STATE" in
    absent)
      if _docker_unmanaged_docker_present; then
        log::info "Docker is present but not installed by Atlas; treating it as user-owned"
      else
        log::info "Docker is absent and development/docker is not installed by Atlas"
      fi
      return 0
      ;;
    detached)
      log::warn "development/docker is detached; Atlas is not asserting Docker service health"
      return 0
      ;;
  esac

  _docker_repo_source_valid || return 1
  _docker_repo_matches_source || { log::error "Docker CE repository file is missing or changed: $(_docker_repo_file)"; return 1; }
  _docker_key_present || { log::error "Docker RPM signing key is missing or unexpected"; return 1; }
  _docker_packages_installed || { log::error "Docker package set is incomplete"; return 1; }
  _docker_cli_present || { log::error "Docker CLI is missing or not executable: $(_docker_cli)"; return 1; }
  _docker_compose_ok || { log::error "Docker Compose plugin is not runnable"; return 1; }
  _docker_service_enabled || { log::error "docker.service is not enabled"; return 1; }
  _docker_service_active || { log::error "docker.service is not active"; return 1; }
  _docker_socket_ok || return 1
  if _docker_user_config_present; then
    log::error "unsupported Docker daemon co-configuration detected"
    log::error "  fix: remove or formally adopt $(_docker_daemon_json) / $(_docker_dropin_dir) through a future RFC"
    return 1
  fi
  if _docker_tcp_listener_present; then
    log::error "Docker TCP listener detected"
    log::error "  fix: use SSH/TLS through an explicit user-owned design; Atlas manages only the local Unix socket"
    return 1
  fi
  _docker_api_ok_for_verify || return 1
  if groups 2>/dev/null | grep -qw docker; then
    log::warn "this user is in the docker group; that is root-equivalent access and is user-managed"
  fi
  return 0
}

module::check() {
  _docker_marker_load || return 1
  [ "$_DOCKER_MARKER_STATE" = "installed" ] || return 1
  _docker_repo_matches_source || return 1
  _docker_key_present || return 1
  _docker_packages_installed || return 1
  _docker_cli_present || return 1
  _docker_compose_ok || return 1
  _docker_service_enabled || return 1
  _docker_service_active || return 1
  _docker_socket_ok >/dev/null 2>&1 || return 1
  _docker_user_config_present && return 1
  _docker_tcp_listener_present && return 1
  return 0
}

module::install() {
  os::is_fedora || { log::error "Docker module supports Fedora only"; return 1; }
  _docker_marker_load || return 1
  case "$_DOCKER_MARKER_STATE" in
    absent) _docker_preflight_unmanaged || return 1 ;;
    detached) _docker_preflight_detached || return 1 ;;
    installing|installed) _docker_preflight_managed_repair || return 1 ;;
  esac
  _docker_marker_write installing || return 1
  _docker_write_repo || return 1
  _docker_import_key || return 1
  os::dnf_install "${_DOCKER_PACKAGES[@]}" || return 1
  _docker_run_privileged systemctl enable --now docker.service || { log::error "cannot enable/start docker.service"; return 1; }
  _docker_packages_installed || { log::error "Docker package set is incomplete after install"; return 1; }
  _docker_cli_present || { log::error "Docker CLI is missing after install"; return 1; }
  _docker_compose_ok || { log::error "Docker Compose plugin is not runnable after install"; return 1; }
  _docker_service_enabled || { log::error "docker.service is not enabled after install"; return 1; }
  _docker_service_active || { log::error "docker.service is not active after install"; return 1; }
  _docker_socket_ok || return 1
  _docker_probe_privileged || { log::error "Docker local API probe failed after install"; return 1; }
  if _docker_user_config_present; then
    log::error "unsupported Docker daemon co-configuration detected after install"
    return 1
  fi
  if _docker_tcp_listener_present; then
    log::error "Docker TCP listener detected after install"
    return 1
  fi
  _docker_marker_write installed || return 1
  log::info "Docker Engine is installed and managed by Atlas"
}

module::verify() {
  _docker_verify_managed
}

module::update() {
  log::info "nothing to update: Docker package currency and daemon restarts are user-scheduled in RFC-0005"
  return 0
}

module::remove() {
  _docker_marker_load || return 1
  case "$_DOCKER_MARKER_STATE" in
    absent) log::info "Docker is not installed by Atlas; nothing to detach"; return 0 ;;
    detached) log::info "Docker is already detached from Atlas"; return 0 ;;
  esac
  local containers
  containers="$(_docker_run_privileged env -u DOCKER_HOST -u DOCKER_CONTEXT -u DOCKER_CONFIG -u DOCKER_TLS \
    -u DOCKER_TLS_VERIFY -u DOCKER_CERT_PATH PATH=/usr/bin:/bin \
    "$(_docker_cli)" --host "unix://$(_docker_socket)" ps -aq 2>/dev/null)" || {
      log::error "cannot inspect Docker containers; refusing to detach"; return 1; }
  if [ -n "$containers" ]; then
    log::error "Docker containers exist; refusing to detach Atlas management"
    log::error "  fix: decide what to do with user workloads manually, then re-run remove"
    return 1
  fi
  if [ "${_DOCKER_MARKER_REPO_CREATED:-0}" = "1" ] && [ -e "$(_docker_repo_file)" ]; then
    if ! _docker_repo_matches_source; then
      log::error "Docker repository file changed; refusing to remove it"
      return 1
    fi
  fi
  _docker_run_privileged systemctl disable --now docker.service || { log::error "cannot disable/stop docker.service"; return 1; }
  if [ "${_DOCKER_MARKER_REPO_CREATED:-0}" = "1" ] && [ -e "$(_docker_repo_file)" ]; then
    if [ -w "$(dirname "$(_docker_repo_file)")" ]; then
      rm -f "$(_docker_repo_file)" || { log::error "cannot remove $(_docker_repo_file)"; return 1; }
    else
      _docker_run_privileged rm -f "$(_docker_repo_file)" || { log::error "cannot remove $(_docker_repo_file)"; return 1; }
    fi
    log::info "removed Atlas-owned Docker repository file"
  fi
  _docker_marker_write detached || return 1
  log::info "detached Docker from Atlas without uninstalling packages or touching workloads"
}

module::backup() {
  log::info "nothing to back up: Docker workloads and data are user-owned; Atlas-owned install state is reconstructable"
  return 0
}

module::restore() {
  log::info "nothing to restore: reinstall Docker to reconstruct Atlas-owned install state"
  return 0
}
