#!/usr/bin/env bash
# desktop/theme activation - RFC-0029 (reversible, opt-in KDE ColorScheme switch)

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/theme/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
# KConfig ColorScheme mocked by a file: present => that scheme; absent => key absent.
SCHEME_FILE="$HOME/colorscheme"; export SCHEME_FILE
printf BreezeDark > "$SCHEME_FILE"
kreadconfig6() { local d=""; while [ $# -gt 0 ]; do case "$1" in --default) d="$2"; shift 2 ;; *) shift ;; esac; done; if [ -e "$SCHEME_FILE" ]; then cat "$SCHEME_FILE"; else printf "%s\n" "$d"; fi; }
kwriteconfig6() { local del=0 a; for a in "$@"; do [ "$a" = "--delete" ] && del=1; done; [ "$del" = 1 ] && rm -f "$SCHEME_FILE"; return 0; }
plasma-apply-colorscheme() { printf "%s" "$1" > "$SCHEME_FILE"; }
ACT() { _theme_act_marker; }
'
PRE="${PRE%$'\n'}"

# --- preconditions -------------------------------------------------------------
assert_status "activate fails when theme not installed" 1 bash -c "$PRE; module::activate >/dev/null 2>&1; [ ! -e \"\$(ACT)\" ]; exit 1"
# shadow `command -v` for the tool only (the real binary exists on a live KDE host)
assert_status "activate fails when plasma-apply-colorscheme absent" 1 bash -c "$PRE; module::install >/dev/null 2>&1; command() { if [ \"\$1\" = -v ] && [ \"\$2\" = plasma-apply-colorscheme ]; then return 1; fi; builtin command \"\$@\"; }; module::activate 2>/dev/null"
assert_status "deactivate is a no-op before activation" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::deactivate"

# --- records prior / applies ---------------------------------------------------
assert_status "activate records prior and applies Atlas" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; [ \"\$(cat \"\$SCHEME_FILE\")\" = Atlas ]; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_colorscheme=BreezeDark \"\$(ACT)\""

# --- idempotent ----------------------------------------------------------------
assert_status "second activate is a no-op" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; cp \"\$(ACT)\" \"\$HOME/m1\"; module::activate >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\""

# --- restores exactly ----------------------------------------------------------
assert_status "deactivate restores the recorded prior and drops prior_*" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$SCHEME_FILE\")\" = BreezeDark ]; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_colorscheme \"\$(ACT)\""

# --- refuse-to-clobber ---------------------------------------------------------
assert_status "activate refuses to clobber user drift and preserves prior" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; printf Oxygen > \"\$SCHEME_FILE\"; module::activate 2>/dev/null && exit 1; grep -qxF prior_colorscheme=BreezeDark \"\$(ACT)\""
assert_status "deactivate refuses to clobber user drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; printf Oxygen > \"\$SCHEME_FILE\"; module::deactivate 2>/dev/null && exit 1; [ \"\$(cat \"\$SCHEME_FILE\")\" = Oxygen ]"

# --- absent-key sentinel -------------------------------------------------------
assert_status "activate records absent sentinel when key did not exist" 0 bash -c "$PRE; rm -f \"\$SCHEME_FILE\"; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; grep -qxF prior_colorscheme=__ATLAS_ABSENT__ \"\$(ACT)\"; [ \"\$(cat \"\$SCHEME_FILE\")\" = Atlas ]"
assert_status "deactivate deletes the key when prior was absent" 0 bash -c "$PRE; rm -f \"\$SCHEME_FILE\"; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ ! -e \"\$SCHEME_FILE\" ]; grep -qxF state=inactive \"\$(ACT)\""

# --- interrupted activation is write-once (the Rev-1 data-loss scenario) --------
assert_status "interrupted activate reuses recorded prior, never launders it" 0 bash -c "$PRE; module::install >/dev/null 2>&1; _theme_act_write activating BreezeDark; printf Atlas > \"\$SCHEME_FILE\"; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_colorscheme=BreezeDark \"\$(ACT)\"; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$SCHEME_FILE\")\" = BreezeDark ]"

# --- prior scheme deleted on deactivate ----------------------------------------
assert_status "deactivate reports and keeps state when prior apply fails" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; plasma-apply-colorscheme() { return 1; }; module::deactivate 2>/dev/null && exit 1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_colorscheme=BreezeDark \"\$(ACT)\""

# --- disown then fresh prior ---------------------------------------------------
assert_status "disown (delete marker) lets activate record a fresh prior" 0 bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; rm -f \"\$(ACT)\"; printf Oxygen > \"\$SCHEME_FILE\"; module::activate >/dev/null 2>&1; grep -qxF prior_colorscheme=Oxygen \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\""

# --- interrupted deactivate finalizes (already restored, not drift) -------------
assert_status "interrupted deactivate finalizes to inactive without misreporting drift" 0 bash -c "$PRE; module::install >/dev/null 2>&1; _theme_act_write active BreezeDark; printf BreezeDark > \"\$SCHEME_FILE\"; module::deactivate >/dev/null 2>&1; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_colorscheme \"\$(ACT)\"; [ \"\$(cat \"\$SCHEME_FILE\")\" = BreezeDark ]"

# --- strict parser rejects malformed activation markers ------------------------
assert_status "load rejects prior_* under inactive state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nprior_colorscheme=BreezeDark\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _theme_act_load 2>/dev/null"
assert_status "load rejects missing prior_* under active state" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=active\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _theme_act_load 2>/dev/null"
assert_status "load rejects unknown key" 1 bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nbogus=1\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _theme_act_load 2>/dev/null"
