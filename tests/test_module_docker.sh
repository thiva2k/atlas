#!/usr/bin/env bash
# development/docker - RFC-0005
#
# No test touches the host Docker installation, systemd, DNF, RPM database, or
# /etc. Each case runs in a sandbox and mocks the privileged/package/runtime
# tools the module uses.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/state"; export ATLAS_STATE_DIR
TEST_DOCKER_REPO_FILE="$HOME/etc/yum.repos.d/docker-ce.repo"; export TEST_DOCKER_REPO_FILE
TEST_DOCKER_SOCKET="$HOME/run/docker.sock"; export TEST_DOCKER_SOCKET
TEST_DOCKER_DAEMON_JSON="$HOME/etc/docker/daemon.json"; export TEST_DOCKER_DAEMON_JSON
TEST_DOCKER_DROPIN_DIR="$HOME/etc/systemd/system/docker.service.d"; export TEST_DOCKER_DROPIN_DIR
TEST_DOCKER_DESKTOP_MARKER="$HOME/opt/docker-desktop"; export TEST_DOCKER_DESKTOP_MARKER
ATLAS_DOCKER_REPO_FILE="$TEST_DOCKER_REPO_FILE"; export ATLAS_DOCKER_REPO_FILE
ATLAS_DOCKER_SOCKET="$TEST_DOCKER_SOCKET"; export ATLAS_DOCKER_SOCKET
ATLAS_DOCKER_DAEMON_JSON="$TEST_DOCKER_DAEMON_JSON"; export ATLAS_DOCKER_DAEMON_JSON
ATLAS_DOCKER_DROPIN_DIR="$TEST_DOCKER_DROPIN_DIR"; export ATLAS_DOCKER_DROPIN_DIR
ATLAS_DOCKER_DESKTOP_MARKER="$TEST_DOCKER_DESKTOP_MARKER"; export ATLAS_DOCKER_DESKTOP_MARKER
ATLAS_DOCKER_CLI="docker"; export ATLAS_DOCKER_CLI
DOCKER_ARGV_LOG="$HOME/docker.argv"; export DOCKER_ARGV_LOG
DOCKER_ENV_LOG="$HOME/docker.env"; export DOCKER_ENV_LOG
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
RPMKEYS_LOG="$HOME/rpmkeys.log"; export RPMKEYS_LOG
SYSTEMCTL_LOG="$HOME/systemctl.log"; export SYSTEMCTL_LOG
SUDO_LOG="$HOME/sudo.log"; export SUDO_LOG
: > "$DOCKER_ARGV_LOG"; : > "$DOCKER_ENV_LOG"; : > "$DNF_LOG"; : > "$RPMKEYS_LOG"; : > "$SYSTEMCTL_LOG"; : > "$SUDO_LOG"
mkdir -p "$HOME/bin" "$(dirname "$TEST_DOCKER_REPO_FILE")" "$(dirname "$TEST_DOCKER_SOCKET")"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/docker/module.sh"

_docker_repo_file() { printf "%s\n" "$TEST_DOCKER_REPO_FILE"; }
_docker_socket() { printf "%s\n" "$TEST_DOCKER_SOCKET"; }
_docker_cli() { printf "%s\n" "docker"; }
_docker_daemon_json() { printf "%s\n" "$TEST_DOCKER_DAEMON_JSON"; }
_docker_dropin_dir() { printf "%s\n" "$TEST_DOCKER_DROPIN_DIR"; }
_docker_desktop_marker() { printf "%s\n" "$TEST_DOCKER_DESKTOP_MARKER"; }

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::dnf_install() { printf "%s\n" "$*" >> "$DNF_LOG"; RPM_INSTALLED="${RPM_INSTALLED:-} $*"; export RPM_INSTALLED; }
rpm() {
  case "${1:-}" in
    -q)
      case "${2:-}" in
        -f)
          [ "${3:-}" = "$(_docker_cli)" ] || return 1
          if [ "${DOCKER_CLI_RPM_OWNER:-docker-ce-cli}" = docker-ce-cli ]; then
            printf "docker-ce-cli-99.0.0-1.fc99.x86_64\n"
            return 0
          fi
          printf "%s-99.0.0-1.fc99.x86_64\n" "${DOCKER_CLI_RPM_OWNER:-unknown}"
          return 0
          ;;
        *) case " ${RPM_INSTALLED:-} " in *" $2 "*) return 0 ;; *) return 1 ;; esac ;;
      esac
      ;;
    -qf)
      [ "${2:-}" = "$(_docker_cli)" ] || return 1
      if [ "${DOCKER_CLI_RPM_OWNER:-docker-ce-cli}" = docker-ce-cli ]; then
        printf "docker-ce-cli-99.0.0-1.fc99.x86_64\n"
        return 0
      fi
      printf "%s-99.0.0-1.fc99.x86_64\n" "${DOCKER_CLI_RPM_OWNER:-unknown}"
      return 0
      ;;
  esac
  return 1
}
rpmkeys() {
  printf "%s\n" "$*" >> "$RPMKEYS_LOG"
  case "$*" in
    *"--root "*"--import "*)
      [ "${KEY_SOURCE_VALID:-1}" = 1 ]
      return
      ;;
    *"--root "*"--list"*)
      if [ "${KEY_SOURCE_VALID:-1}" = 1 ]; then
        printf "060a61c51b558a7f742b77aac52feb6b621e9f35 Docker Release (CE rpm) <docker@docker.com> public key\n"
      else
        printf "ffffffffffffffffffffffffffffffffffffffff Bad Key <bad@example.com> public key\n"
      fi
      return 0
      ;;
    "--list")
      [ "${KEY_PRESENT:-0}" = 1 ] && printf "060a61c51b558a7f742b77aac52feb6b621e9f35 Docker Release (CE rpm) <docker@docker.com> public key\n"
      return 0
      ;;
    "--import "*)
      [ "${2:-}" = "$(_docker_key_source)" ] || return 1
      KEY_PRESENT=1
      export KEY_PRESENT
      return 0
      ;;
  esac
  return 1
}
systemctl() {
  printf "%s\n" "$*" >> "$SYSTEMCTL_LOG"
  if [ "${1:-}" = "--user" ]; then
    [ "${ROOTLESS_ACTIVE:-0}" = 1 ] && return 0 || return 3
  fi
  case "$*" in
    "is-enabled --quiet docker.service") [ "${SERVICE_ENABLED:-0}" = 1 ] ;;
    "is-active --quiet docker.service") [ "${SERVICE_ACTIVE:-0}" = 1 ] ;;
    "enable --now docker.service") SERVICE_ENABLED=1; SERVICE_ACTIVE=1; export SERVICE_ENABLED SERVICE_ACTIVE ;;
    "disable --now docker.service") SERVICE_ENABLED=0; SERVICE_ACTIVE=0; export SERVICE_ENABLED SERVICE_ACTIVE ;;
    "cat docker.service") [ "${DOCKER_UNIT_EXISTS:-0}" = 1 ] ;;
    "list-unit-files docker.service") [ "${DOCKER_UNIT_EXISTS:-0}" = 1 ] ;;
    "is-active --quiet containerd.service") [ "${CONTAINERD_ACTIVE:-0}" = 1 ] ;;
    "is-active --quiet crio.service") [ "${CRIO_ACTIVE:-0}" = 1 ] ;;
    "is-active --quiet kubelet.service") [ "${KUBELET_ACTIVE:-0}" = 1 ] ;;
    *) return 1 ;;
  esac
}
sudo() {
  printf "%s\n" "$*" >> "$SUDO_LOG"
  if [ "${1:-}" = "-n" ]; then
    shift
    [ "${SUDO_READY:-0}" = 1 ] || return 1
  fi
  "$@"
}
groups() { printf "%s\n" "${GROUPS_OUT:-atlas}"; }
_docker_socket_ok() { [ "${SOCKET_OK:-1}" = 1 ]; }
_docker_cli_present() { return 0; }
_docker_unmanaged_docker_present() { [ "${UNMANAGED_DOCKER:-0}" = 1 ]; }
_docker_fixed_env() {
  unset DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG DOCKER_TLS DOCKER_TLS_VERIFY DOCKER_CERT_PATH
  "$@"
}
_docker_probe_direct() { _docker_fixed_env "$(_docker_cli)" --host "unix://$(_docker_socket)" version >/dev/null 2>&1; }
_docker_probe_sudo_noninteractive() { sudo -n "$(_docker_cli)" --host "unix://$(_docker_socket)" version >/dev/null 2>&1; }
_docker_probe_privileged() { _docker_fixed_env "$(_docker_cli)" --host "unix://$(_docker_socket)" version >/dev/null 2>&1; }
_docker_run_privileged() {
  if [ "${1:-}" = "env" ]; then
    while [ "$#" -gt 0 ]; do
      case "${1:-}" in
        env) shift ;;
        -u) shift 2 ;;
        PATH=*) shift ;;
        *) break ;;
      esac
    done
  fi
  "$@"
}
docker() {
  printf "%s\n" "$*" >> "$DOCKER_ARGV_LOG"
  local n v
  for n in DOCKER_HOST DOCKER_CONTEXT DOCKER_CONFIG DOCKER_TLS DOCKER_TLS_VERIFY DOCKER_CERT_PATH; do
    v="${!n-}"
    [ -n "$v" ] && printf "%s=%s\n" "$n" "$v" >> "$DOCKER_ENV_LOG"
  done
  case "$*" in
    *"compose version"*) [ "${COMPOSE_OK:-1}" = 1 ] ;;
    *"ps -aq"*) [ "${PS_RC:-0}" = 0 ] || return "$PS_RC"; printf "%s" "${CONTAINERS:-}" ;;
    *"version"*) [ "${API_OK:-1}" = 1 ] ;;
    *) return 0 ;;
  esac
}
true
'
PRE="${PRE%$'\n'}"

MOD_READY='
RPM_INSTALLED="docker-ce docker-ce-cli containerd.io docker-compose-plugin"; export RPM_INSTALLED
KEY_PRESENT=1; export KEY_PRESENT
SERVICE_ENABLED=1; SERVICE_ACTIVE=1; export SERVICE_ENABLED SERVICE_ACTIVE
mkdir -p "$(dirname "$ATLAS_DOCKER_REPO_FILE")"
cp "$_DOCKER_MODULE_DIR/config/docker-ce.repo" "$ATLAS_DOCKER_REPO_FILE"
'
MOD_READY="${MOD_READY%$'\n'}"

out="$(bash -c '
set -euo pipefail
export ATLAS_DOCKER_REPO_FILE=/tmp/evil-repo
export ATLAS_DOCKER_SOCKET=/tmp/evil.sock
export ATLAS_DOCKER_CLI=/tmp/evil-docker
export ATLAS_DOCKER_DAEMON_JSON=/tmp/evil-daemon.json
export ATLAS_DOCKER_DROPIN_DIR=/tmp/evil-dropins
export ATLAS_DOCKER_DESKTOP_MARKER=/tmp/evil-desktop
source "$ATLAS_ROOT/modules/development/docker/module.sh"
printf "%s\n" "$(_docker_repo_file)" "$(_docker_socket)" "$(_docker_cli)" "$(_docker_daemon_json)" "$(_docker_dropin_dir)" "$(_docker_desktop_marker)"
')"
assert_eq "docker production paths ignore ATLAS_DOCKER overrides" "$out" "/etc/yum.repos.d/docker-ce.repo
/var/run/docker.sock
/usr/bin/docker
/etc/docker/daemon.json
/etc/systemd/system/docker.service.d
/opt/docker-desktop"

assert_status "docker CLI helper accepts docker-ce-cli RPM ownership" 0 \
  bash -c '
    set -euo pipefail
    HOME="$(mktemp -d)"; trap "rm -rf \"$HOME\"" EXIT
    source "$ATLAS_ROOT/internal/os.sh"
    source "$ATLAS_ROOT/modules/development/docker/module.sh"
    _docker_cli() { printf "%s\n" "$HOME/docker"; }
    : > "$HOME/docker"; chmod +x "$HOME/docker"
    rpm() { [ "${1:-}" = -qf ] && [ "${2:-}" = "$HOME/docker" ] && printf "docker-ce-cli-99.0.0-1.fc99.x86_64\n"; }
    _docker_cli_present
  '

assert_status "docker CLI helper rejects missing RPM ownership" 1 \
  bash -c '
    set -euo pipefail
    HOME="$(mktemp -d)"; trap "rm -rf \"$HOME\"" EXIT
    source "$ATLAS_ROOT/internal/os.sh"
    source "$ATLAS_ROOT/modules/development/docker/module.sh"
    _docker_cli() { printf "%s\n" "$HOME/docker"; }
    : > "$HOME/docker"; chmod +x "$HOME/docker"
    rpm() { return 1; }
    _docker_cli_present
  '

assert_status "docker CLI helper rejects non-RPM replacement owner" 1 \
  bash -c '
    set -euo pipefail
    HOME="$(mktemp -d)"; trap "rm -rf \"$HOME\"" EXIT
    source "$ATLAS_ROOT/internal/os.sh"
    source "$ATLAS_ROOT/modules/development/docker/module.sh"
    _docker_cli() { printf "%s\n" "$HOME/docker"; }
    : > "$HOME/docker"; chmod +x "$HOME/docker"
    rpm() { [ "${1:-}" = -qf ] && printf "evil-docker-1.0-1.fc99.x86_64\n"; }
    _docker_cli_present
  '

assert_status "docker TCP detector reports normal unix-socket-only state as clean" 1 \
  bash -c "$PRE; _docker_proc_net_files() { printf \"%s\n\" \"\$HOME/proc/net/tcp\"; }; _docker_proc_dirs() { printf \"%s\n\" \"\$HOME/proc/42\"; }; mkdir -p \"\$HOME/proc/net\" \"\$HOME/proc/42/fd\"; printf \"  sl  local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode\n\" > \"\$HOME/proc/net/tcp\"; printf \"dockerd\n\" > \"\$HOME/proc/42/comm\"; _docker_tcp_listener_present"

assert_status "docker TCP detector reports exposed dockerd TCP listener" 0 \
  bash -c "$PRE; _docker_proc_net_files() { printf \"%s\n\" \"\$HOME/proc/net/tcp\"; }; _docker_proc_dirs() { printf \"%s\n\" \"\$HOME/proc/42\"; }; mkdir -p \"\$HOME/proc/net\" \"\$HOME/proc/42/fd\"; printf \"  sl  local_address rem_address st tx_queue rx_queue tr tm->when retrnsmt uid timeout inode\n   0: 0100007F:0943 00000000:0000 0A 00000000:00000000 00:00000000 00000000 0 0 12345 1 0000000000000000\n\" > \"\$HOME/proc/net/tcp\"; printf \"dockerd\n\" > \"\$HOME/proc/42/comm\"; ln -s \"socket:[12345]\" \"\$HOME/proc/42/fd/3\"; _docker_tcp_listener_present"

assert_status "docker verify passes before install (not installed)" 0 \
  bash -c "$PRE; module::verify"

out="$(bash -c "$PRE; UNMANAGED_DOCKER=1; export UNMANAGED_DOCKER; module::verify" 2>&1)"
assert_contains "docker verify treats existing unmanaged Docker as user-owned" "$out" "present but not installed by Atlas"

assert_status "docker check fails before install" 1 \
  bash -c "$PRE; module::check"

assert_status "docker verify fails on malformed marker" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_docker_marker)\")\"; printf \"state=installed\n\" > \"\$(_docker_marker)\"; module::verify"

assert_status "docker verify fails when marker mode is not 600" 1 \
  bash -c "$PRE; _docker_marker_write installed; chmod 644 \"\$(_docker_marker)\"; module::verify"

assert_status "docker verify fails when marker repo hash mismatches Atlas source" 1 \
  bash -c "$PRE; mkdir -p \"\$(dirname \"\$(_docker_marker)\")\"; printf \"schema=1\nstate=installed\nmode=rootful-system\npackage_source=docker-ce-stable\nrepo_created=1\nrepo_sha256=0000000000000000000000000000000000000000000000000000000000000000\n\" > \"\$(_docker_marker)\"; chmod 600 \"\$(_docker_marker)\"; module::verify"

assert_status "docker verify fails when managed repo is missing" 1 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; rm -f \"\$ATLAS_DOCKER_REPO_FILE\"; module::verify"

assert_status "docker verify fails when a managed package is missing" 1 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; RPM_INSTALLED=\"docker-ce docker-ce-cli containerd.io\"; module::verify"

assert_status "docker verify fails when compose is broken" 1 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; COMPOSE_OK=0; export COMPOSE_OK; module::verify"

assert_status "docker verify fails when service is inactive" 1 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; SERVICE_ACTIVE=0; export SERVICE_ACTIVE; module::verify"

assert_status "docker verify fails on unsupported daemon.json after install" 1 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; mkdir -p \"\$(dirname \"\$ATLAS_DOCKER_DAEMON_JSON\")\"; : > \"\$ATLAS_DOCKER_DAEMON_JSON\"; module::verify"

out="$(bash -c "$PRE; _docker_marker_write installed; $MOD_READY; SUDO_READY=0; API_OK=0; export SUDO_READY API_OK; module::verify" 2>&1)"
assert_contains "docker verify warns rather than fails when socket auth is unavailable" "$out" "sudo is not already authorized"

assert_status "docker verify fails when authorized API probe fails" 1 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; SUDO_READY=1; API_OK=0; export SUDO_READY API_OK; module::verify"

assert_status "docker verify passes when managed state is healthy" 0 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; module::verify"

assert_status "docker legacy TCP test flag no longer affects production verify" 0 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; ATLAS_DOCKER_TEST_TCP_LISTENER=1; export ATLAS_DOCKER_TEST_TCP_LISTENER; module::verify"

assert_status "docker detached marker verifies without health assertions" 0 \
  bash -c "$PRE; _docker_marker_write detached; SOCKET_OK=0; SERVICE_ACTIVE=0; module::verify"

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$DNF_LOG\"")"
assert_eq "docker install uses exact package set" "$out" "docker-ce docker-ce-cli containerd.io docker-compose-plugin"

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; grep '^--import ' \"\$RPMKEYS_LOG\"")"
assert_eq "docker install imports only the bundled RPM key" "$out" "--import $ATLAS_ROOT/modules/development/docker/config/docker.asc"

assert_status "docker install refuses a bundled RPM key hash mismatch before dnf" 1 \
  bash -c "$PRE; printf \"bad key\n\" > \"\$HOME/bad-key.asc\"; _docker_key_source() { printf \"%s\n\" \"\$HOME/bad-key.asc\"; }; module::install >/dev/null 2>&1 || rc=\$?; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$SYSTEMCTL_LOG\"")"
assert_contains "docker install enables and starts docker.service" "$out" "enable --now docker.service"

out="$(bash -c "$PRE; export DOCKER_HOST=tcp://evil.example:2375 DOCKER_CONTEXT=evil DOCKER_CONFIG=/tmp/evil DOCKER_TLS=1 DOCKER_TLS_VERIFY=1 DOCKER_CERT_PATH=/tmp/certs; module::install >/dev/null 2>&1; cat \"\$DOCKER_ENV_LOG\"")"
assert_eq "docker probes ignore hostile Docker environment" "$out" ""

argv="$(bash -c "$PRE; module::install >/dev/null 2>&1; cat \"\$DOCKER_ARGV_LOG\"")"
assert_eq "docker install never invokes workload commands" \
  "$(printf '%s\n' "$argv" | grep -Ec '(^| )(run|pull|build|prune|system prune|up)( |$)' || true)" "0"

assert_status "docker install promotes marker only after validation" 1 \
  bash -c "$PRE; COMPOSE_OK=0; export COMPOSE_OK; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_docker_marker)\"; exit \"\${rc:-0}\""

assert_status "docker install refuses post-install daemon config before promotion" 1 \
  bash -c "$PRE; _docker_probe_privileged() { mkdir -p \"\$(dirname \"\$ATLAS_DOCKER_DAEMON_JSON\")\"; : > \"\$ATLAS_DOCKER_DAEMON_JSON\"; return 0; }; module::install >/dev/null 2>&1 || rc=\$?; grep -qxF state=installing \"\$(_docker_marker)\"; exit \"\${rc:-0}\""

assert_status "docker install refuses unmanaged repo without creating marker" 1 \
  bash -c "$PRE; printf \"user repo\n\" > \"\$ATLAS_DOCKER_REPO_FILE\"; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_docker_marker)\" ]; exit \"\${rc:-0}\""

assert_status "docker install refuses rootless Docker before mutation" 1 \
  bash -c "$PRE; ROOTLESS_ACTIVE=1; export ROOTLESS_ACTIVE; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_docker_marker)\" ]; exit \"\${rc:-0}\""

assert_status "docker install refuses non-Fedora before repair mutation" 1 \
  bash -c "$PRE; _docker_marker_write installing; FEDORA_OK=0; export FEDORA_OK; module::install >/dev/null 2>&1 || rc=\$?; [ ! -s \"\$DNF_LOG\" ]; exit \"\${rc:-0}\""

assert_status "docker install refuses container runtime conflicts before mutation" 1 \
  bash -c "$PRE; RPM_INSTALLED=containerd; export RPM_INSTALLED; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_docker_marker)\" ]; exit \"\${rc:-0}\""

assert_status "docker install refuses inactive existing docker.service before mutation" 1 \
  bash -c "$PRE; DOCKER_UNIT_EXISTS=1; export DOCKER_UNIT_EXISTS; module::install >/dev/null 2>&1 || rc=\$?; [ ! -e \"\$(_docker_marker)\" ]; exit \"\${rc:-0}\""

assert_status "docker managed repair refuses daemon.json before mutation from installed marker" 1 \
  bash -c "$PRE; _docker_marker_write installed; printf \"sentinel repo\n\" > \"\$ATLAS_DOCKER_REPO_FILE\"; cp \"\$(_docker_marker)\" \"\$HOME/marker.before\"; cp \"\$ATLAS_DOCKER_REPO_FILE\" \"\$HOME/repo.before\"; marker_inode=\$(stat -c %i \"\$(_docker_marker)\"); mkdir -p \"\$(dirname \"\$ATLAS_DOCKER_DAEMON_JSON\")\"; : > \"\$ATLAS_DOCKER_DAEMON_JSON\"; module::install >/dev/null 2>&1 || rc=\$?; [ \"\$(stat -c %i \"\$(_docker_marker)\")\" = \"\$marker_inode\" ]; cmp -s \"\$HOME/marker.before\" \"\$(_docker_marker)\"; cmp -s \"\$HOME/repo.before\" \"\$ATLAS_DOCKER_REPO_FILE\"; [ ! -s \"\$DNF_LOG\" ]; [ ! -s \"\$RPMKEYS_LOG\" ]; ! grep -q \"enable --now docker.service\" \"\$SYSTEMCTL_LOG\"; exit \"\${rc:-0}\""

assert_status "docker managed repair refuses daemon.json before mutation from installing marker" 1 \
  bash -c "$PRE; _docker_marker_write installing; printf \"sentinel repo\n\" > \"\$ATLAS_DOCKER_REPO_FILE\"; cp \"\$(_docker_marker)\" \"\$HOME/marker.before\"; cp \"\$ATLAS_DOCKER_REPO_FILE\" \"\$HOME/repo.before\"; marker_inode=\$(stat -c %i \"\$(_docker_marker)\"); mkdir -p \"\$(dirname \"\$ATLAS_DOCKER_DAEMON_JSON\")\"; : > \"\$ATLAS_DOCKER_DAEMON_JSON\"; module::install >/dev/null 2>&1 || rc=\$?; [ \"\$(stat -c %i \"\$(_docker_marker)\")\" = \"\$marker_inode\" ]; cmp -s \"\$HOME/marker.before\" \"\$(_docker_marker)\"; cmp -s \"\$HOME/repo.before\" \"\$ATLAS_DOCKER_REPO_FILE\"; [ ! -s \"\$DNF_LOG\" ]; [ ! -s \"\$RPMKEYS_LOG\" ]; ! grep -q \"enable --now docker.service\" \"\$SYSTEMCTL_LOG\"; exit \"\${rc:-0}\""

assert_status "docker managed repair refuses systemd drop-ins before mutation from installed marker" 1 \
  bash -c "$PRE; _docker_marker_write installed; printf \"sentinel repo\n\" > \"\$ATLAS_DOCKER_REPO_FILE\"; cp \"\$(_docker_marker)\" \"\$HOME/marker.before\"; cp \"\$ATLAS_DOCKER_REPO_FILE\" \"\$HOME/repo.before\"; marker_inode=\$(stat -c %i \"\$(_docker_marker)\"); mkdir -p \"\$ATLAS_DOCKER_DROPIN_DIR\"; module::install >/dev/null 2>&1 || rc=\$?; [ \"\$(stat -c %i \"\$(_docker_marker)\")\" = \"\$marker_inode\" ]; cmp -s \"\$HOME/marker.before\" \"\$(_docker_marker)\"; cmp -s \"\$HOME/repo.before\" \"\$ATLAS_DOCKER_REPO_FILE\"; [ ! -s \"\$DNF_LOG\" ]; [ ! -s \"\$RPMKEYS_LOG\" ]; ! grep -q \"enable --now docker.service\" \"\$SYSTEMCTL_LOG\"; exit \"\${rc:-0}\""

assert_status "docker managed repair refuses systemd drop-ins before mutation from installing marker" 1 \
  bash -c "$PRE; _docker_marker_write installing; printf \"sentinel repo\n\" > \"\$ATLAS_DOCKER_REPO_FILE\"; cp \"\$(_docker_marker)\" \"\$HOME/marker.before\"; cp \"\$ATLAS_DOCKER_REPO_FILE\" \"\$HOME/repo.before\"; marker_inode=\$(stat -c %i \"\$(_docker_marker)\"); mkdir -p \"\$ATLAS_DOCKER_DROPIN_DIR\"; module::install >/dev/null 2>&1 || rc=\$?; [ \"\$(stat -c %i \"\$(_docker_marker)\")\" = \"\$marker_inode\" ]; cmp -s \"\$HOME/marker.before\" \"\$(_docker_marker)\"; cmp -s \"\$HOME/repo.before\" \"\$ATLAS_DOCKER_REPO_FILE\"; [ ! -s \"\$DNF_LOG\" ]; [ ! -s \"\$RPMKEYS_LOG\" ]; ! grep -q \"enable --now docker.service\" \"\$SYSTEMCTL_LOG\"; exit \"\${rc:-0}\""

assert_status "docker detached reinstall allows Atlas-left Docker CE packages" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; module::install >/dev/null 2>&1; module::verify"

assert_status "docker repeated install is idempotent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; cp \"\$(_docker_marker)\" \"\$HOME/marker1\"; module::install >/dev/null 2>&1; module::verify; grep -qxF state=installed \"\$(_docker_marker)\"; cmp -s \"\$HOME/marker1\" \"\$(_docker_marker)\""

for hook in update backup restore; do
  assert_status "docker $hook is a documented no-op" 0 \
    bash -c "$PRE; module::$hook"
done

assert_status "docker remove is a no-op when never installed" 0 \
  bash -c "$PRE; module::remove"

assert_status "docker remove refuses when containers exist" 1 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; CONTAINERS=abc123; export CONTAINERS; module::remove"

assert_status "docker remove detaches without uninstalling packages" 0 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; module::remove >/dev/null 2>&1; grep -qxF state=detached \"\$(_docker_marker)\"; [ ! -e \"\$ATLAS_DOCKER_REPO_FILE\" ]; [ ! -s \"\$DNF_LOG\" ]"

assert_status "docker remove refuses changed repo before stopping service" 1 \
  bash -c "$PRE; _docker_marker_write installed; $MOD_READY; printf \"changed\n\" > \"\$ATLAS_DOCKER_REPO_FILE\"; module::remove >/dev/null 2>&1 || rc=\$?; ! grep -q \"disable --now docker.service\" \"\$SYSTEMCTL_LOG\"; exit \"\${rc:-0}\""

argv="$(bash -c "$PRE; module::install >/dev/null 2>&1; module::remove >/dev/null 2>&1; cat \"\$DOCKER_ARGV_LOG\"")"
assert_eq "docker remove never mutates workloads" \
  "$(printf '%s\n' "$argv" | grep -Ec '(^| )(rm|rmi|volume|network|prune|stop|kill|compose up)( |$)' || true)" "0"

assert_status "docker runner verify succeeds before install" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run verify development/docker"

assert_status "docker runner doctor uses verify contract" 0 \
  bash -c "$PRE; set +e; set -uo pipefail; source \"\$ATLAS_ROOT/internal/module.sh\"; source \"\$ATLAS_ROOT/internal/runner.sh\"; runner::run doctor development/docker"
