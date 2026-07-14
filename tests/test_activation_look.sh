#!/usr/bin/env bash
# desktop/{icons,cursor,fonts} activation - RFC-0030 (KDE look activation).
#
# Mirrors tests/test_activation.sh: throwaway HOME, mocked KDE tools as shell
# functions backed by a temp file per key, stubbed os::is_fedora. No real Plasma
# and no live config mutation — every kreadconfig6/kwriteconfig6/plasma-changeicons
# is a mock over a temp file. assert_status expects the exit code of the whole
# bash -c body; refusals are structured as `hook 2>/dev/null && exit 1; <assert>`.

# =============================================================================
# desktop/cursor  (kcminputrc [Mouse] cursorTheme -> Adwaita; no apply tool)
# =============================================================================
CUR_PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/cursor/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::pkg_installed() { return 0; }
os::dnf_install() { return 0; }
# [Mouse] cursorTheme mocked by a file: present => that value; absent => key absent.
KEY_FILE="$HOME/cursortheme"; export KEY_FILE
printf breeze_cursors > "$KEY_FILE"
kreadconfig6() { local d=""; while [ $# -gt 0 ]; do case "$1" in --default) d="$2"; shift 2 ;; *) shift ;; esac; done; if [ -e "$KEY_FILE" ]; then cat "$KEY_FILE"; else printf "%s\n" "$d"; fi; }
kwriteconfig6() { local del=0 a val=""; for a in "$@"; do [ "$a" = "--delete" ] && del=1; done; val="${@: -1}"; if [ "$del" = 1 ]; then rm -f "$KEY_FILE"; else printf "%s" "$val" > "$KEY_FILE"; fi; return 0; }
ACT() { _cursor_act_marker; }
'
CUR_PRE="${CUR_PRE%$'\n'}"

assert_status "cursor: activate fails when not installed" 1 bash -c "$CUR_PRE; module::activate >/dev/null 2>&1; [ ! -e \"\$(ACT)\" ]; exit 1"
assert_status "cursor: activate fails when kwriteconfig6 absent" 1 bash -c "$CUR_PRE; module::install >/dev/null 2>&1; command() { if [ \"\$1\" = -v ] && { [ \"\$2\" = kwriteconfig6 ] || [ \"\$2\" = kreadconfig6 ]; }; then return 1; fi; builtin command \"\$@\"; }; module::activate 2>/dev/null"
assert_status "cursor: deactivate is a no-op before activation" 0 bash -c "$CUR_PRE; module::install >/dev/null 2>&1; module::deactivate"
# records prior + applies Adwaita, and succeeds with NO plasma-apply-cursortheme / qdbus6 present
assert_status "cursor: activate records prior and applies Adwaita (no live-apply tool)" 0 bash -c "$CUR_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; [ \"\$(cat \"\$KEY_FILE\")\" = Adwaita ]; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_cursortheme=breeze_cursors \"\$(ACT)\""
# reports 'applies at next login'
assert_status "cursor: activate reports applies at next login" 0 bash -c "$CUR_PRE; module::install >/dev/null 2>&1; out=\"\$(module::activate 2>&1)\"; case \"\$out\" in *'next login'*) exit 0 ;; *) exit 1 ;; esac"
assert_status "cursor: second activate is a byte-identical no-op" 0 bash -c "$CUR_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; cp \"\$(ACT)\" \"\$HOME/m1\"; module::activate >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\""
assert_status "cursor: deactivate restores prior exactly and drops prior_*" 0 bash -c "$CUR_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$KEY_FILE\")\" = breeze_cursors ]; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_cursortheme \"\$(ACT)\""
assert_status "cursor: absent sentinel recorded when key did not exist" 0 bash -c "$CUR_PRE; rm -f \"\$KEY_FILE\"; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; grep -qxF prior_cursortheme=__ATLAS_ABSENT__ \"\$(ACT)\"; [ \"\$(cat \"\$KEY_FILE\")\" = Adwaita ]"
assert_status "cursor: deactivate deletes the key when prior was absent" 0 bash -c "$CUR_PRE; rm -f \"\$KEY_FILE\"; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ ! -e \"\$KEY_FILE\" ]; grep -qxF state=inactive \"\$(ACT)\""
assert_status "cursor: activate refuses to clobber user drift and preserves prior" 0 bash -c "$CUR_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; printf Oxygen > \"\$KEY_FILE\"; module::activate 2>/dev/null && exit 1; grep -qxF prior_cursortheme=breeze_cursors \"\$(ACT)\""
assert_status "cursor: deactivate refuses to clobber user drift" 0 bash -c "$CUR_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; printf Oxygen > \"\$KEY_FILE\"; module::deactivate 2>/dev/null && exit 1; [ \"\$(cat \"\$KEY_FILE\")\" = Oxygen ]"
assert_status "cursor: interrupted activate reuses recorded prior, never launders it" 0 bash -c "$CUR_PRE; module::install >/dev/null 2>&1; _cursor_act_write activating breeze_cursors; printf Adwaita > \"\$KEY_FILE\"; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_cursortheme=breeze_cursors \"\$(ACT)\"; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$KEY_FILE\")\" = breeze_cursors ]"
assert_status "cursor: interrupted deactivate finalizes without misreporting drift" 0 bash -c "$CUR_PRE; module::install >/dev/null 2>&1; _cursor_act_write active breeze_cursors; printf breeze_cursors > \"\$KEY_FILE\"; module::deactivate >/dev/null 2>&1; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_cursortheme \"\$(ACT)\"; [ \"\$(cat \"\$KEY_FILE\")\" = breeze_cursors ]"

# =============================================================================
# desktop/icons  (kdeglobals [Icons] Theme -> Papirus-Dark; tool via override)
# =============================================================================
ICO_PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
KEY_FILE="$HOME/icontheme"; export KEY_FILE
printf breeze > "$KEY_FILE"
CHANGE_LOG="$HOME/changeicons.log"; export CHANGE_LOG
# temp executable standing in for /usr/libexec/plasma-changeicons: records argv,
# writes the given name verbatim into the backing key (never validates).
CHANGE="$HOME/plasma-changeicons"; export CHANGE
printf "%s\n" "#!/usr/bin/env bash" "printf %s \"\$1\" > \"$KEY_FILE\"" "printf %s\\\\n \"\$*\" >> \"$CHANGE_LOG\"" > "$CHANGE"
chmod +x "$CHANGE"
ATLAS_ICONS_CHANGEICONS="$CHANGE"; export ATLAS_ICONS_CHANGEICONS
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/icons/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
os::pkg_installed() { return 0; }
os::dnf_install() { return 0; }
kreadconfig6() { local d=""; while [ $# -gt 0 ]; do case "$1" in --default) d="$2"; shift 2 ;; *) shift ;; esac; done; if [ -e "$KEY_FILE" ]; then cat "$KEY_FILE"; else printf "%s\n" "$d"; fi; }
kwriteconfig6() { local del=0 a val=""; for a in "$@"; do [ "$a" = "--delete" ] && del=1; done; val="${@: -1}"; if [ "$del" = 1 ]; then rm -f "$KEY_FILE"; else printf "%s" "$val" > "$KEY_FILE"; fi; return 0; }
ACT() { _icons_act_marker; }
'
ICO_PRE="${ICO_PRE%$'\n'}"

assert_status "icons: activate fails when not installed" 1 bash -c "$ICO_PRE; module::activate >/dev/null 2>&1; [ ! -e \"\$(ACT)\" ]; exit 1"
assert_status "icons: activate fails when ATLAS_ICONS_CHANGEICONS is non-executable" 1 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; ATLAS_ICONS_CHANGEICONS=\"\$HOME/nope\"; _ICONS_CHANGEICONS=\"\$HOME/nope\"; module::activate 2>/dev/null"
assert_status "icons: activate records prior, applies Papirus-Dark, invokes tool mock" 0 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; [ \"\$(cat \"\$KEY_FILE\")\" = Papirus-Dark ]; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_icontheme=breeze \"\$(ACT)\"; grep -q Papirus-Dark \"\$CHANGE_LOG\""
assert_status "icons: activate never runs real /usr/libexec (only the override mock's log has entries)" 0 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; [ -s \"\$CHANGE_LOG\" ]; [ \"\$_ICONS_CHANGEICONS\" = \"\$CHANGE\" ]"
assert_status "icons: activate reports applies live or on next login" 0 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; out=\"\$(module::activate 2>&1)\"; case \"\$out\" in *'next login'*) exit 0 ;; *) exit 1 ;; esac"
assert_status "icons: second activate is a byte-identical no-op" 0 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; cp \"\$(ACT)\" \"\$HOME/m1\"; module::activate >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\""
assert_status "icons: deactivate restores prior via the tool and drops prior_*" 0 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$KEY_FILE\")\" = breeze ]; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_icontheme \"\$(ACT)\""
assert_status "icons: absent sentinel recorded when key did not exist" 0 bash -c "$ICO_PRE; rm -f \"\$KEY_FILE\"; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; grep -qxF prior_icontheme=__ATLAS_ABSENT__ \"\$(ACT)\"; [ \"\$(cat \"\$KEY_FILE\")\" = Papirus-Dark ]"
assert_status "icons: deactivate deletes the key (kwriteconfig6 --delete) when prior was absent" 0 bash -c "$ICO_PRE; rm -f \"\$KEY_FILE\"; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ ! -e \"\$KEY_FILE\" ]; grep -qxF state=inactive \"\$(ACT)\""
assert_status "icons: activate refuses to clobber user drift and preserves prior" 0 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; printf Oxygen > \"\$KEY_FILE\"; module::activate 2>/dev/null && exit 1; grep -qxF prior_icontheme=breeze \"\$(ACT)\""
assert_status "icons: deactivate refuses to clobber user drift" 0 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; printf Oxygen > \"\$KEY_FILE\"; module::deactivate 2>/dev/null && exit 1; [ \"\$(cat \"\$KEY_FILE\")\" = Oxygen ]"
assert_status "icons: interrupted activate reuses recorded prior, never launders it" 0 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; _icons_act_write activating breeze; printf Papirus-Dark > \"\$KEY_FILE\"; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(ACT)\"; grep -qxF prior_icontheme=breeze \"\$(ACT)\"; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$KEY_FILE\")\" = breeze ]"
assert_status "icons: interrupted deactivate finalizes without misreporting drift" 0 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; _icons_act_write active breeze; printf breeze > \"\$KEY_FILE\"; module::deactivate >/dev/null 2>&1; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_icontheme \"\$(ACT)\"; [ \"\$(cat \"\$KEY_FILE\")\" = breeze ]"
# Honest restore of a removed prior: the tool writes whatever name it is given;
# restore SUCCEEDS at writing the recorded selection — there is no tool-error path.
assert_status "icons: honest restore of a removed-package prior always succeeds" 0 bash -c "$ICO_PRE; module::install >/dev/null 2>&1; _icons_act_write active Some-Removed-Theme; printf Papirus-Dark > \"\$KEY_FILE\"; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$KEY_FILE\")\" = Some-Removed-Theme ]; grep -qxF state=inactive \"\$(ACT)\""

# =============================================================================
# desktop/fonts  (kdeglobals [General] font + fixed; two-key per-key resumable)
# =============================================================================
FON_PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_DATA_HOME="$HOME/.local/share"; export XDG_DATA_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/desktop/fonts/module.sh"
os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
# Two backing files, keyed by --key font vs --key fixed.
FONT_GENERAL_FILE="$HOME/font_general"; export FONT_GENERAL_FILE
FONT_FIXED_FILE="$HOME/font_fixed"; export FONT_FIXED_FILE
printf "Noto Sans,10,-1,5,50,0,0,0,0,0" > "$FONT_GENERAL_FILE"
printf "Hack,10,-1,5,50,0,0,0,0,0" > "$FONT_FIXED_FILE"
_fon_file() { local k="$1"; case "$k" in font) printf "%s" "$FONT_GENERAL_FILE" ;; fixed) printf "%s" "$FONT_FIXED_FILE" ;; esac; }
kreadconfig6() { local d="" key=""; while [ $# -gt 0 ]; do case "$1" in --default) d="$2"; shift 2 ;; --key) key="$2"; shift 2 ;; *) shift ;; esac; done; local f; f="$(_fon_file "$key")"; if [ -e "$f" ]; then cat "$f"; else printf "%s\n" "$d"; fi; }
kwriteconfig6() { local del=0 key="" a val=""; local -a args=("$@"); for a in "$@"; do [ "$a" = "--delete" ] && del=1; done; while [ $# -gt 0 ]; do case "$1" in --key) key="$2"; shift 2 ;; *) shift ;; esac; done; val="${args[@]: -1}"; local f; f="$(_fon_file "$key")"; if [ "$del" = 1 ]; then rm -f "$f"; else printf "%s" "$val" > "$f"; fi; return 0; }
# seed a valid install marker WITHOUT network download.
_fon_install() { _fonts_marker_write installed; }
ACT() { _fonts_act_marker; }
GEN="Inter,10,-1,5,50,0,0,0,0,0"
FIX="JetBrainsMono Nerd Font,10,-1,5,50,0,0,0,0,0"
'
FON_PRE="${FON_PRE%$'\n'}"

assert_status "fonts: activate fails when not installed" 1 bash -c "$FON_PRE; module::activate >/dev/null 2>&1; [ ! -e \"\$(ACT)\" ]; exit 1"
assert_status "fonts: activate fails when kwriteconfig6 absent" 1 bash -c "$FON_PRE; _fon_install >/dev/null 2>&1; command() { if [ \"\$1\" = -v ] && { [ \"\$2\" = kwriteconfig6 ] || [ \"\$2\" = kreadconfig6 ]; }; then return 1; fi; builtin command \"\$@\"; }; module::activate 2>/dev/null"
assert_status "fonts: deactivate is a no-op before activation" 0 bash -c "$FON_PRE; _fon_install >/dev/null 2>&1; module::deactivate"
# records BOTH priors, both keys hold their Atlas descriptors, applies at next login
assert_status "fonts: activate records both priors and applies both Atlas descriptors" 0 bash -c "$FON_PRE; _fon_install >/dev/null 2>&1; module::activate >/dev/null 2>&1; [ \"\$(cat \"\$FONT_GENERAL_FILE\")\" = \"\$GEN\" ]; [ \"\$(cat \"\$FONT_FIXED_FILE\")\" = \"\$FIX\" ]; grep -qxF state=active \"\$(ACT)\"; grep -qxF 'prior_font_general=Noto Sans,10,-1,5,50,0,0,0,0,0' \"\$(ACT)\"; grep -qxF 'prior_font_fixed=Hack,10,-1,5,50,0,0,0,0,0' \"\$(ACT)\""
assert_status "fonts: activate reports applies at next login" 0 bash -c "$FON_PRE; _fon_install >/dev/null 2>&1; out=\"\$(module::activate 2>&1)\"; case \"\$out\" in *'next login'*) exit 0 ;; *) exit 1 ;; esac"
assert_status "fonts: second activate is a byte-identical no-op" 0 bash -c "$FON_PRE; _fon_install >/dev/null 2>&1; module::activate >/dev/null 2>&1; cp \"\$(ACT)\" \"\$HOME/m1\"; module::activate >/dev/null 2>&1; cmp -s \"\$HOME/m1\" \"\$(ACT)\"; grep -qxF state=active \"\$(ACT)\""
assert_status "fonts: deactivate restores both priors exactly and drops prior_*" 0 bash -c "$FON_PRE; _fon_install >/dev/null 2>&1; module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$FONT_GENERAL_FILE\")\" = 'Noto Sans,10,-1,5,50,0,0,0,0,0' ]; [ \"\$(cat \"\$FONT_FIXED_FILE\")\" = 'Hack,10,-1,5,50,0,0,0,0,0' ]; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_font \"\$(ACT)\""
# independent sentinels: font set, fixed absent -> restore general, delete fixed
assert_status "fonts: independent absent sentinels round-trip per key" 0 bash -c "$FON_PRE; rm -f \"\$FONT_FIXED_FILE\"; _fon_install >/dev/null 2>&1; module::activate >/dev/null 2>&1; grep -qxF 'prior_font_general=Noto Sans,10,-1,5,50,0,0,0,0,0' \"\$(ACT)\"; grep -qxF prior_font_fixed=__ATLAS_ABSENT__ \"\$(ACT)\"; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$FONT_GENERAL_FILE\")\" = 'Noto Sans,10,-1,5,50,0,0,0,0,0' ]; [ ! -e \"\$FONT_FIXED_FILE\" ]; grep -qxF state=inactive \"\$(ACT)\""
# interrupted-activate write-once: both keys at Atlas, state=activating -> reuse priors
assert_status "fonts: interrupted activate reuses recorded priors, never launders them" 0 bash -c "$FON_PRE; _fon_install >/dev/null 2>&1; _fonts_act_write activating 'Noto Sans,10,-1,5,50,0,0,0,0,0' 'Hack,10,-1,5,50,0,0,0,0,0'; printf %s \"\$GEN\" > \"\$FONT_GENERAL_FILE\"; printf %s \"\$FIX\" > \"\$FONT_FIXED_FILE\"; module::activate >/dev/null 2>&1; grep -qxF state=active \"\$(ACT)\"; grep -qxF 'prior_font_general=Noto Sans,10,-1,5,50,0,0,0,0,0' \"\$(ACT)\"; grep -qxF 'prior_font_fixed=Hack,10,-1,5,50,0,0,0,0,0' \"\$(ACT)\"; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$FONT_GENERAL_FILE\")\" = 'Noto Sans,10,-1,5,50,0,0,0,0,0' ]; [ \"\$(cat \"\$FONT_FIXED_FILE\")\" = 'Hack,10,-1,5,50,0,0,0,0,0' ]"
# THE Rev-1 data-loss hole: state=active, font at prior (restored), fixed at Atlas (not).
# deactivate must FINISH: skip font (case 2), restore fixed (case 1), end inactive, lose neither prior.
assert_status "fonts: one-key-restored interrupted deactivate finishes both, no prior lost" 0 bash -c "$FON_PRE; _fon_install >/dev/null 2>&1; _fonts_act_write active 'Noto Sans,10,-1,5,50,0,0,0,0,0' 'Hack,10,-1,5,50,0,0,0,0,0'; printf %s 'Noto Sans,10,-1,5,50,0,0,0,0,0' > \"\$FONT_GENERAL_FILE\"; printf %s \"\$FIX\" > \"\$FONT_FIXED_FILE\"; module::deactivate >/dev/null 2>&1; [ \"\$(cat \"\$FONT_GENERAL_FILE\")\" = 'Noto Sans,10,-1,5,50,0,0,0,0,0' ]; [ \"\$(cat \"\$FONT_FIXED_FILE\")\" = 'Hack,10,-1,5,50,0,0,0,0,0' ]; grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_font \"\$(ACT)\""
# mixed drift refuse (case 3): one key at Atlas, other at a genuine third value.
# deactivate refuses BEFORE touching either key; activate refuses to re-record.
assert_status "fonts: mixed drift -> deactivate refuses before touching either key" 0 bash -c "$FON_PRE; _fon_install >/dev/null 2>&1; module::activate >/dev/null 2>&1; printf %s 'Comic Sans,10,-1,5,50,0,0,0,0,0' > \"\$FONT_FIXED_FILE\"; module::deactivate 2>/dev/null && exit 1; [ \"\$(cat \"\$FONT_GENERAL_FILE\")\" = \"\$GEN\" ]; [ \"\$(cat \"\$FONT_FIXED_FILE\")\" = 'Comic Sans,10,-1,5,50,0,0,0,0,0' ]; grep -qxF 'prior_font_general=Noto Sans,10,-1,5,50,0,0,0,0,0' \"\$(ACT)\""
assert_status "fonts: mixed drift -> activate refuses to re-record over existing prior" 0 bash -c "$FON_PRE; _fon_install >/dev/null 2>&1; module::activate >/dev/null 2>&1; printf %s 'Comic Sans,10,-1,5,50,0,0,0,0,0' > \"\$FONT_FIXED_FILE\"; module::activate 2>/dev/null && exit 1; [ \"\$(cat \"\$FONT_FIXED_FILE\")\" = 'Comic Sans,10,-1,5,50,0,0,0,0,0' ]; grep -qxF 'prior_font_fixed=Hack,10,-1,5,50,0,0,0,0,0' \"\$(ACT)\""
# strict parser: a marker with only ONE prior_* under active must be rejected.
assert_status "fonts: parser rejects a marker with only one prior_* under active" 1 bash -c "$FON_PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; chmod 700 \"\$d\"; printf 'schema=1\nstate=active\nprior_font_general=X\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _fonts_act_load 2>/dev/null"
assert_status "fonts: parser rejects prior_* under inactive" 1 bash -c "$FON_PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; chmod 700 \"\$d\"; printf 'schema=1\nstate=inactive\nprior_font_general=X\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _fonts_act_load 2>/dev/null"
