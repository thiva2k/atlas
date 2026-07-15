#!/usr/bin/env bash
# desktop/ksplash activation - RFC-0037 (reversible, opt-in ksplashrc [KSplash] Theme switch)
# Reuses the RFC-0029 escrow pattern exactly as desktop/lockscreen does, just against a
# different key (ksplashrc [KSplash] Theme instead of kscreenlockerrc [Greeter] Theme),
# plus an Engine=KSplashQML precondition check unique to ksplash.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/ksplash/module.sh"
SPLASH_QML() { _ksplash_splash_qml; }
install_splash() { mkdir -p "$(dirname "$(SPLASH_QML)")"; printf "Rectangle {}" > "$(SPLASH_QML)"; }
# ksplashrc [KSplash] Theme/Engine mocked by two files: present => that value; absent => key absent.
THEME_FILE="$HOME/theme"; export THEME_FILE
ENGINE_FILE="$HOME/engine"; export ENGINE_FILE
printf org.kde.breeze.desktop > "$THEME_FILE"
printf KSplashQML > "$ENGINE_FILE"
kreadconfig6() {
  local d="" key=""
  while [ $# -gt 0 ]; do case "$1" in --default) d="$2"; shift 2 ;; --key) key="$2"; shift 2 ;; *) shift ;; esac; done
  local f; case "$key" in Theme) f="$THEME_FILE" ;; Engine) f="$ENGINE_FILE" ;; *) f="/nonexistent" ;; esac
  if [ -e "$f" ]; then cat "$f"; else printf "%s\n" "$d"; fi
}
kwriteconfig6() {
  local del=0 key="" val="" a; local -a rest=(); for a in "$@"; do rest+=("$a"); done
  local i=0; while [ $i -lt ${#rest[@]} ]; do case "${rest[$i]}" in --delete) del=1 ;; --key) key="${rest[$((i+1))]}" ;; --*) : ;; *) val="${rest[$i]}" ;; esac; i=$((i+1)); done
  local f; case "$key" in Theme) f="$THEME_FILE" ;; Engine) f="$ENGINE_FILE" ;; *) return 1 ;; esac
  if [ "$del" = 1 ]; then rm -f "$f"; else printf "%s" "$val" > "$f"; fi
  return 0
}
ACT() { _ksplash_act_marker; }
'
PRE="${PRE%$'\n'}"

# --- preconditions -------------------------------------------------------------
assert_status "activate fails when the splash package is not present" 1 bash -c "$PRE; module::activate >/dev/null 2>&1; [ ! -e \"\$(ACT)\" ]; exit 1"
assert_status "activate fails when kreadconfig6/kwriteconfig6 absent" 1 bash -c "$PRE; install_splash; command() { if [ \"\$1\" = -v ] && { [ \"\$2\" = kreadconfig6 ] || [ \"\$2\" = kwriteconfig6 ]; }; then return 1; fi; builtin command \"\$@\"; }; module::activate 2>/dev/null"
assert_status "activate fails when Engine is not KSplashQML" 1 bash -c "$PRE; install_splash; printf OtherEngine > \"\$ENGINE_FILE\"; module::activate 2>/dev/null; [ ! -e \"\$(ACT)\" ]"
assert_status "deactivate is a no-op before activation" 0 bash -c "$PRE; install_splash; module::deactivate"

# --- records prior / applies ----------------------------------------------------
assert_status "activate records prior and sets Theme to org.atlas.hud" 0 bash -c "$PRE; install_splash; module::activate >/dev/null 2>&1; [ \"\$(cat \"\$THEME_FILE\")\" = org.atlas.hud ]; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_theme=org.kde.breeze.desktop \"\$(ACT)\""

# --- idempotent ------------------------------------------------------------------
assert_status "second activate is a no-op" 0 bash -c "$PRE; install_splash; module::activate >/dev/null 2>&1; cp \"\$(ACT)\" \"\$HOME/m1\"; module::activate >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\""

# --- restores exactly --------------------------------------------------------------
assert_status "deactivate restores the recorded prior and drops prior_theme" 0 bash -c "$PRE; install_splash; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$THEME_FILE\")\" = org.kde.breeze.desktop ]; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_theme \"\$(ACT)\""

# --- refuse-to-clobber -------------------------------------------------------------
assert_status "activate refuses to clobber user drift and preserves prior" 0 bash -c "$PRE; install_splash; module::activate >/dev/null 2>&1; printf org.kde.breezedark.desktop > \"\$THEME_FILE\"; module::activate 2>/dev/null && exit 1; grep -qxF prior_theme=org.kde.breeze.desktop \"\$(ACT)\""
assert_status "deactivate refuses to clobber user drift" 0 bash -c "$PRE; install_splash; module::activate >/dev/null 2>&1; printf org.kde.breezedark.desktop > \"\$THEME_FILE\"; module::deactivate 2>/dev/null && exit 1; [ \"\$(cat \"\$THEME_FILE\")\" = org.kde.breezedark.desktop ]"

# --- absent-key sentinel -------------------------------------------------------------
assert_status "activate records absent sentinel when Theme key did not exist" 0 bash -c "$PRE; rm -f \"\$THEME_FILE\"; install_splash; module::activate >/dev/null 2>&1; grep -qxF prior_theme=__ATLAS_ABSENT__ \"\$(ACT)\"; [ \"\$(cat \"\$THEME_FILE\")\" = org.atlas.hud ]"
assert_status "deactivate deletes the Theme key when prior was absent" 0 bash -c "$PRE; rm -f \"\$THEME_FILE\"; install_splash; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ ! -e \"\$THEME_FILE\" ]; grep -qxF state=inactive \"\$(ACT)\""

# --- interrupted activation is write-once (never launders Atlas into the escrow) ---
assert_status "interrupted activate reuses recorded prior, never launders it" 0 bash -c "$PRE; install_splash; _ksplash_act_write activating org.kde.breeze.desktop; printf org.atlas.hud > \"\$THEME_FILE\"; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_theme=org.kde.breeze.desktop \"\$(ACT)\"; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$THEME_FILE\")\" = org.kde.breeze.desktop ]"

# --- interrupted deactivate finalizes (already restored, not drift) ------------------
assert_status "interrupted deactivate finalizes to inactive without misreporting drift" 0 bash -c "$PRE; install_splash; _ksplash_act_write active org.kde.breeze.desktop; printf org.kde.breeze.desktop > \"\$THEME_FILE\"; module::deactivate >/dev/null 2>&1; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_theme \"\$(ACT)\"; [ \"\$(cat \"\$THEME_FILE\")\" = org.kde.breeze.desktop ]"

# --- prior theme write failure on deactivate leaves state unchanged ------------------
assert_status "deactivate reports and keeps state when prior write fails" 0 bash -c "$PRE; install_splash; module::activate >/dev/null 2>&1; kwriteconfig6() { return 1; }; module::deactivate 2>/dev/null && exit 1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_theme=org.kde.breeze.desktop \"\$(ACT)\""

# --- disown then fresh prior ---------------------------------------------------------
assert_status "disown (delete marker) lets activate record a fresh prior" 0 bash -c "$PRE; install_splash; module::activate >/dev/null 2>&1; rm -f \"\$(ACT)\"; printf org.kde.breezedark.desktop > \"\$THEME_FILE\"; module::activate >/dev/null 2>&1; grep -qxF prior_theme=org.kde.breezedark.desktop \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\""

# --- strict marker parser rejections --------------------------------------------------
assert_status "load rejects prior_theme under inactive state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nprior_theme=org.kde.breeze.desktop\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _ksplash_act_load 2>/dev/null"
assert_status "load rejects missing prior_theme under active state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=active\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _ksplash_act_load 2>/dev/null"
assert_status "load rejects unknown key" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nbogus=1\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _ksplash_act_load 2>/dev/null"
assert_status "load rejects an unsupported schema" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=2\nstate=inactive\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _ksplash_act_load 2>/dev/null"
assert_status "load rejects an invalid state value" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=bogus\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _ksplash_act_load 2>/dev/null"
assert_status "load rejects marker mode != 600" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\n' > \"\$(ACT)\"; chmod 644 \"\$(ACT)\"; _ksplash_act_load 2>/dev/null"
