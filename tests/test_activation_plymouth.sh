#!/usr/bin/env bash
# desktop/plymouth activation - RFC-0032 Rev 2
# (reversible, opt-in, privileged switch of the system default plymouth theme).
#
# Mocks model the REAL tool's write order via two temp files + a rebuild counter:
#   CONF       = what plymouthd.conf would say (written by the tool BEFORE any rebuild)
#   INITRAMFS  = what the initramfs actually boots (only a completed -R updates it)
#   REBUILDS   = number of -R rebuilds (asserts write-after-apply, not just CONF)
# The no-arg read never returns empty (prints CONF, i.e. the resolved default).
# A mutating call with no privilege (ROOT_OK!=1 and sudo denied) exits 1 ("must be root").

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
PLYMOUTH_DIR="$HOME/usr/share/plymouth/themes/atlas"; export PLYMOUTH_DIR
source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/os.sh"; source "$ATLAS_ROOT/modules/desktop/plymouth/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::is_root() { [ "${ROOT_OK:-1}" = 1 ]; }
_plymouth_theme_dir() { printf "%s\n" "$PLYMOUTH_DIR"; }
# Install-side mocks (RFC-0024/0024a): no real dnf/rpm on the test host.
DNF_LOG="$HOME/dnf.log"; export DNF_LOG
PLUGIN_STATE="$HOME/plugin_installed"; export PLUGIN_STATE
: > "$PLUGIN_STATE"
os::pkg_installed() { [ "$1" = plymouth-plugin-script ] && { [ -e "$PLUGIN_STATE" ]; return; }; return 0; }
os::dnf_install() { printf "%s\n" "$*" >> "$DNF_LOG"; for _p in "$@"; do [ "$_p" = plymouth-plugin-script ] && : > "$PLUGIN_STATE"; done; }
# --- activation mocks --------------------------------------------------------
CONF="$HOME/plymouth-conf"; export CONF; printf bgrt > "$CONF"
INITRAMFS="$HOME/plymouth-initramfs"; export INITRAMFS; printf bgrt > "$INITRAMFS"
REBUILDS="$HOME/rebuild-count"; export REBUILDS; printf 0 > "$REBUILDS"
# ROOT_OK gates os::is_root; SUDO_OK gates the sudo mock (both default to allow).
SUDO_OK="${SUDO_OK:-1}"; export SUDO_OK
_bump_rebuilds() { printf "%s" "$(( $(cat "$REBUILDS") + 1 ))" > "$REBUILDS"; }
plymouth-set-default-theme() {
  # no args -> print current default (resolved from CONF; NEVER empty)
  if [ "$#" -eq 0 ]; then cat "$CONF"; return 0; fi
  # mutating call: requires privilege. Root or an allowed sudo has already unwrapped
  # us; if not root and sudo denied, the module never reaches here — but guard anyway.
  if [ "${ROOT_OK:-1}" != 1 ] && [ "${SUDO_OK:-1}" != 1 ]; then echo "This program must be run as root" >&2; return 1; fi
  local rebuild=0 name=""
  while [ "$#" -gt 0 ]; do case "$1" in -R|--rebuild-initrd) rebuild=1 ;; -r|--reset) name="" ;; -*) ;; *) name="$1" ;; esac; shift; done
  # config write happens first (like the real tool), whether or not rebuild succeeds.
  [ -n "$name" ] && printf "%s" "$name" > "$CONF"
  if [ "$rebuild" = 1 ]; then
    # A deliberately-missing theme fails the rebuild (real tool: "does not exist").
    if [ -n "${MISSING_THEME:-}" ] && [ "$name" = "$MISSING_THEME" ]; then echo "$name does not exist" >&2; return 1; fi
    if [ "${REBUILD_FAIL:-0}" = 1 ]; then echo "initramfs rebuild failed" >&2; return 1; fi
    printf "%s" "$(cat "$CONF")" > "$INITRAMFS"; _bump_rebuilds
  fi
  return 0
}
# sudo mock: -n is the non-interactive probe; otherwise passthrough when allowed.
sudo() { case "$1" in -n) shift; [ "${SUDO_OK:-1}" = 1 ] && { "$@"; } || return 1 ;; *) [ "${SUDO_OK:-1}" = 1 ] && "$@" || return 1 ;; esac; }
ACT() { _plymouth_act_marker; }
RC() { cat "$REBUILDS"; }
'
PRE="${PRE%$'\n'}"

# --- 1. requires installed / requires tool -------------------------------------
assert_status "activate fails when plymouth not installed; no marker, no rebuild" 1 bash -c "$PRE; module::activate >/dev/null 2>&1; [ ! -e \"\$(ACT)\" ]; [ \"\$(RC)\" = 0 ]; exit 1"
assert_status "activate fails when plugin absent (not installed)" 0 bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$PLUGIN_STATE\"; module::activate 2>/dev/null && exit 1; [ ! -e \"\$(ACT)\" ]; [ \"\$(RC)\" = 0 ]"
assert_status "activate fails when plymouth-set-default-theme absent; no marker" 0 bash -c "$PRE; module::install >/dev/null 2>&1; command() { if [ \"\$1\" = -v ] && [ \"\$2\" = plymouth-set-default-theme ]; then return 1; fi; builtin command \"\$@\"; }; module::activate 2>/dev/null && exit 1; [ ! -e \"\$(ACT)\" ]; [ \"\$(RC)\" = 0 ]"

# --- 2. records prior + applies, rebuilds exactly once, active written after -----
assert_status "activate records concrete prior, rebuilds INITRAMFS to atlas once, writes active" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_default_theme=bgrt \"\$(ACT)\"; [ \"\$(cat \"\$INITRAMFS\")\" = atlas ]; [ \"\$(cat \"\$CONF\")\" = atlas ]; [ \"\$(RC)\" = 1 ]"

# --- 3. idempotent active re-activate does NOT rebuild --------------------------
assert_status "second activate under active/atlas is a no-op; REBUILDS unchanged" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; cp \"\$(ACT)\" \"\$HOME/m1\"; module::activate >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\"; [ \"\$(RC)\" = 1 ]"

# --- 4. deactivate restores prior WITH a rebuild -------------------------------
assert_status "deactivate reselects bgrt, rebuilds INITRAMFS, writes inactive, drops prior_*" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$INITRAMFS\")\" = bgrt ]; [ \"\$(cat \"\$CONF\")\" = bgrt ]; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_default_theme \"\$(ACT)\"; [ \"\$(RC)\" = 2 ]; [ -d \"\$PLYMOUTH_DIR\" ]"

# --- 5. prior is always a concrete recorded name (fallback 'text'); restore re-runs -R
assert_status "prior recorded concretely (text), restore re-runs -R text" 0 bash -c "$PRE; printf text > \"\$CONF\"; printf text > \"\$INITRAMFS\"; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; grep -qxF prior_default_theme=text \"\$(ACT)\"; [ \"\$(cat \"\$INITRAMFS\")\" = atlas ]; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$INITRAMFS\")\" = text ]; grep -qxF state=inactive \"\$(ACT)\"; [ \"\$(RC)\" = 2 ]"

# --- 6. refuse-to-clobber: current != atlas under state=active -----------------
assert_status "activate refuses to clobber user drift; prior + REBUILDS untouched" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; printf spinner > \"\$CONF\"; module::activate 2>/dev/null && exit 1; grep -qxF prior_default_theme=bgrt \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\"; [ \"\$(cat \"\$CONF\")\" = spinner ]; [ \"\$(RC)\" = 1 ]"
assert_status "deactivate refuses to clobber user drift; state + prior untouched" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; printf spinner > \"\$CONF\"; module::deactivate 2>/dev/null && exit 1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_default_theme=bgrt \"\$(ACT)\"; [ \"\$(cat \"\$CONF\")\" = spinner ]; [ \"\$(RC)\" = 1 ]"

# --- 7. interrupted-activate re-runs -R atlas (write-once + write-after-apply) ---
# Seed: state=activating, prior=bgrt, CONF=atlas but INITRAMFS still bgrt (tool wrote
# config then died before the rebuild). Resume must reuse bgrt, re-run -R atlas, settle.
assert_status "resumed activating reuses prior, re-runs -R atlas (REBUILDS bumps), settles active" 0 bash -c "$PRE; module::install >/dev/null 2>&1; _plymouth_act_write activating bgrt; printf atlas > \"\$CONF\"; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_default_theme=bgrt \"\$(ACT)\"; [ \"\$(cat \"\$INITRAMFS\")\" = atlas ]; [ \"\$(RC)\" = 1 ]; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$INITRAMFS\")\" = bgrt ]; [ \"\$(RC)\" = 2 ]"

# --- 8. interrupted-deactivate re-runs -R prior to earn inactive (no no-rebuild) --
# Seed: state=active, prior=bgrt, CONF=bgrt but INITRAMFS still atlas (restore's config
# write landed, rebuild/state write lost). Must re-run -R bgrt, then write inactive.
assert_status "interrupted deactivate re-rebuilds to bgrt then writes inactive (current==prior)" 0 bash -c "$PRE; module::install >/dev/null 2>&1; _plymouth_act_write active bgrt; printf bgrt > \"\$CONF\"; printf atlas > \"\$INITRAMFS\"; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$INITRAMFS\")\" = bgrt ]; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_default_theme \"\$(ACT)\"; [ \"\$(RC)\" = 1 ]"

# --- 9. no-privilege refuse-before-state ---------------------------------------
assert_status "activate refuses BEFORE writing state when root+sudo unavailable" 0 bash -c "$PRE; module::install >/dev/null 2>&1; ROOT_OK=0; SUDO_OK=0; module::activate 2>/dev/null && exit 1; [ ! -e \"\$(ACT)\" ]; [ \"\$(RC)\" = 0 ]"
assert_status "deactivate on active refuses with state unchanged when no privilege" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; ROOT_OK=0; SUDO_OK=0; module::deactivate 2>/dev/null && exit 1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_default_theme=bgrt \"\$(ACT)\"; [ \"\$(RC)\" = 1 ]"

# --- 9b. mid-run rebuild failure never leaves a lying terminal state ------------
assert_status "activate rebuild failure leaves state=activating, prior preserved" 0 bash -c "$PRE; module::install >/dev/null 2>&1; REBUILD_FAIL=1; module::activate 2>/dev/null && exit 1; grep -qxF state=activating \"\$(ACT)\"; grep -qxF prior_default_theme=bgrt \"\$(ACT)\"; [ \"\$(RC)\" = 0 ]"
assert_status "deactivate rebuild failure leaves state=active, prior preserved" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; REBUILD_FAIL=1; module::deactivate 2>/dev/null && exit 1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_default_theme=bgrt \"\$(ACT)\"; [ \"\$(RC)\" = 1 ]"

# --- 10. prior-theme-deleted on deactivate: -R <prior> fails -> state unchanged --
assert_status "deactivate with deleted prior theme reports, leaves state=active" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; MISSING_THEME=bgrt; module::deactivate 2>/dev/null && exit 1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_default_theme=bgrt \"\$(ACT)\"; [ \"\$(RC)\" = 1 ]"

# --- 11. disown: delete marker -> fresh activate records current default --------
assert_status "disown (delete marker) lets activate record a fresh prior" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; rm -f \"\$(ACT)\"; printf spinner > \"\$CONF\"; printf spinner > \"\$INITRAMFS\"; module::activate >/dev/null 2>&1; grep -qxF prior_default_theme=spinner \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\"; [ \"\$(cat \"\$INITRAMFS\")\" = atlas ]"

# --- 12. strict parser rejects malformed activation markers --------------------
assert_status "load rejects prior_default_theme under inactive state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nprior_default_theme=bgrt\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _plymouth_act_load 2>/dev/null"
assert_status "load rejects missing prior_default_theme under active state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=active\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _plymouth_act_load 2>/dev/null"
assert_status "load rejects empty prior_default_theme under activating state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=activating\nprior_default_theme=\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _plymouth_act_load 2>/dev/null"
assert_status "load rejects unknown key" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nbogus=1\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _plymouth_act_load 2>/dev/null"
assert_status "load rejects unknown state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=bogus\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _plymouth_act_load 2>/dev/null"
