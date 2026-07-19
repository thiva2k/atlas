#!/usr/bin/env bash
# development/starship activation - RFC-0031 (reversible, opt-in fish prompt wiring).
#
# Tests sandbox HOME/XDG/ATLAS state and mock Starship. No test touches the user's
# real fish config, ~/.config/fish, or shell startup files: everything is under a
# throwaway temp HOME.

PRE='
set -euo pipefail
HOME="$(mktemp -d)"; export HOME
trap "rm -rf \"$HOME\"" EXIT
XDG_CONFIG_HOME="$HOME/.config"; export XDG_CONFIG_HOME
ATLAS_CONFIG_HOME="$HOME/.config/atlas"; export ATLAS_CONFIG_HOME
ATLAS_STATE_DIR="$HOME/.local/state/atlas"; export ATLAS_STATE_DIR
STARSHIP_BIN="$HOME/bin/starship"; export STARSHIP_BIN
mkdir -p "$HOME/bin"

source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/modules/development/starship/module.sh"

os::is_fedora() { [ "${FEDORA_OK:-1}" = 1 ]; }
# Binary present iff the mock executable exists (tests toggle it explicitly).
os::has_cmd() {
  case "$1" in
    starship) [ -x "$STARSHIP_BIN" ] ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}
# Make starship "present" by default; individual tests remove it to test refusal.
: > "$STARSHIP_BIN"; chmod +x "$STARSHIP_BIN"
# Mock the starship command so config validation (module::install ->
# _starship_validate_if_present runs `starship prompt`) never depends on a real
# binary being on the host PATH. Without this the file only passes on machines
# that happen to have starship installed and fails on clean CI runners.
starship() { [ "${STARSHIP_FAIL:-0}" = 1 ] && return 1; printf "starship mock\n"; }

ACT()  { _starship_act_marker; }
SNIP() { _starship_act_snippet_file; }
BDIR() { _starship_act_backup_dir; }
SHASH() { _starship_act_snippet_hash; }
FISH00() { printf "%s\n" "$XDG_CONFIG_HOME/fish/conf.d/00-atlas.fish"; }
'
PRE="${PRE%$'\n'}"

# --- 2. requires installed -----------------------------------------------------
assert_status "activate fails when starship module is not installed" 0 \
  bash -c "$PRE; module::activate 2>/dev/null && exit 1; [ ! -e \"\$(ACT)\" ]; [ ! -e \"\$(SNIP)\" ]"

# --- 3. requires binary --------------------------------------------------------
assert_status "activate fails with guidance when starship binary is absent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$STARSHIP_BIN\"; module::activate 2>/dev/null && exit 1; [ ! -e \"\$(ACT)\" ]; [ ! -e \"\$(SNIP)\" ]"

out="$(bash -c "$PRE; module::install >/dev/null 2>&1; rm -f \"\$STARSHIP_BIN\"; module::activate 2>&1" || true)"
assert_contains "activate binary-absent message names the fix" "$out" "starship binary not found on PATH"

# --- 4. records prior (absent) and writes the snippet --------------------------
assert_status "activate from clean records absent prior and writes snippet" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; \
    grep -qxF state=active \"\$(ACT)\"; \
    grep -qxF prior_conf=__ATLAS_ABSENT__ \"\$(ACT)\"; \
    ! grep -q '^backup_ref=' \"\$(ACT)\"; \
    ! grep -q '^prior_conf_sha256=' \"\$(ACT)\"; \
    [ -f \"\$(SNIP)\" ]; \
    rec=\"\$(grep '^snippet_sha256=' \"\$(ACT)\" | cut -d= -f2)\"; \
    [ \"\$(sha256sum \"\$(SNIP)\" | awk '{print \$1}')\" = \"\$rec\" ]"

assert_status "activate writes no backup file when prior was absent" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; [ ! -d \"\$(BDIR)\" ] || [ -z \"\$(ls -A \"\$(BDIR)\")\" ]"

# --- 5. idempotent -------------------------------------------------------------
assert_status "second activate is a byte-for-byte no-op" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; \
    cp \"\$(ACT)\" \"\$HOME/m1\"; cp \"\$(SNIP)\" \"\$HOME/s1\"; \
    module::activate >/dev/null 2>&1; \
    cmp -s \"\$HOME/m1\" \"\$(ACT)\"; cmp -s \"\$HOME/s1\" \"\$(SNIP)\"; \
    grep -qxF state=active \"\$(ACT)\""

# --- 6. real record-verbatim backup/restore (F1) -------------------------------
# Seed the path with arbitrary pre-existing bytes (a stand-in for the live
# hand-written snippet). Assert Atlas backs them up verbatim to a uniquely-named
# sibling, installs its own snippet, then restores those exact bytes on deactivate.
assert_status "activate backs up a pre-existing file verbatim to a unique sibling" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; \
    mkdir -p \"\$(dirname \"\$(SNIP)\")\"; \
    printf 'user wiring line 1\nuser wiring line 2\n' > \"\$(SNIP)\"; \
    live=\"\$(sha256sum \"\$(SNIP)\" | awk '{print \$1}')\"; \
    cp \"\$(SNIP)\" \"\$HOME/orig\"; \
    module::activate >/dev/null 2>&1; \
    grep -qxF prior_conf=present \"\$(ACT)\"; \
    grep -qxF \"prior_conf_sha256=\$live\" \"\$(ACT)\"; \
    bref=\"\$(grep '^backup_ref=' \"\$(ACT)\" | cut -d= -f2)\"; \
    [ -f \"\$(BDIR)/\$bref\" ]; \
    cmp -s \"\$HOME/orig\" \"\$(BDIR)/\$bref\"; \
    [ \"\$(sha256sum \"\$(SNIP)\" | awk '{print \$1}')\" = \"\$(SHASH)\" ]"

assert_status "deactivate restores the pre-existing bytes verbatim and removes backup" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; \
    mkdir -p \"\$(dirname \"\$(SNIP)\")\"; \
    printf 'user wiring line 1\nuser wiring line 2\n' > \"\$(SNIP)\"; \
    live=\"\$(sha256sum \"\$(SNIP)\" | awk '{print \$1}')\"; \
    cp \"\$(SNIP)\" \"\$HOME/orig\"; \
    module::activate >/dev/null 2>&1; \
    bref=\"\$(grep '^backup_ref=' \"\$(ACT)\" | cut -d= -f2)\"; \
    module::deactivate >/dev/null 2>&1; \
    cmp -s \"\$HOME/orig\" \"\$(SNIP)\"; \
    [ \"\$(sha256sum \"\$(SNIP)\" | awk '{print \$1}')\" = \"\$live\" ]; \
    [ ! -e \"\$(BDIR)/\$bref\" ]; \
    grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_conf \"\$(ACT)\""

# --- 7. restores exactly (deletes snippet when prior absent), leaves 00-atlas --
assert_status "deactivate deletes the snippet when prior was absent and spares 00-atlas.fish" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; \
    mkdir -p \"\$(dirname \"\$(SNIP)\")\"; printf '# fish 00\n' > \"\$(FISH00)\"; \
    module::activate >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; \
    [ ! -e \"\$(SNIP)\" ]; [ -f \"\$(FISH00)\" ]; \
    grep -qxF state=inactive \"\$(ACT)\"; \
    ! grep -q prior_conf \"\$(ACT)\"; ! grep -q snippet_sha256 \"\$(ACT)\""

# --- 8. activate refuse-to-clobber under state=active, edited snippet ----------
assert_status "activate refuses an edited active snippet, preserves state and file" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; \
    printf 'edited by user\n' > \"\$(SNIP)\"; cp \"\$(SNIP)\" \"\$HOME/edited\"; \
    module::activate 2>/dev/null && exit 1; \
    grep -qxF state=active \"\$(ACT)\"; cmp -s \"\$HOME/edited\" \"\$(SNIP)\""

# --- 9. activate refuse-to-clobber under state=active, removed snippet ---------
assert_status "activate refuses a removed active snippet, does not silently rewrite" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; \
    rm -f \"\$(SNIP)\"; \
    module::activate 2>/dev/null && exit 1; \
    grep -qxF state=active \"\$(ACT)\"; [ ! -e \"\$(SNIP)\" ]"

# --- 10. foreign file during activating (F2a) ----------------------------------
assert_status "activate refuses a foreign file appearing in the activating window" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; \
    d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; chmod 700 \"\$d\"; \
    printf 'schema=1\nstate=activating\nprior_conf=__ATLAS_ABSENT__\nsnippet_sha256=%s\n' \"\$(SHASH)\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; \
    mkdir -p \"\$(dirname \"\$(SNIP)\")\"; printf 'brand new foreign file\n' > \"\$(SNIP)\"; cp \"\$(SNIP)\" \"\$HOME/foreign\"; \
    module::activate 2>/dev/null && exit 1; \
    cmp -s \"\$HOME/foreign\" \"\$(SNIP)\"; \
    grep -qxF prior_conf=__ATLAS_ABSENT__ \"\$(ACT)\""

# --- 11. deactivate under state=activating guards the delete (F2b) -------------
assert_status "deactivate under activating refuses to remove an unowned file" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; \
    d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; chmod 700 \"\$d\"; \
    printf 'schema=1\nstate=activating\nprior_conf=__ATLAS_ABSENT__\nsnippet_sha256=%s\n' \"\$(SHASH)\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; \
    mkdir -p \"\$(dirname \"\$(SNIP)\")\"; printf 'not the atlas snippet\n' > \"\$(SNIP)\"; cp \"\$(SNIP)\" \"\$HOME/notsnip\"; \
    module::deactivate 2>/dev/null && exit 1; \
    cmp -s \"\$HOME/notsnip\" \"\$(SNIP)\"; grep -qxF state=activating \"\$(ACT)\""

# --- 12. template change after activation does not break deactivate (F3) -------
assert_status "deactivate survives a template upgrade by matching recorded hash" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; \
    _starship_act_snippet_content() { printf 'ENTIRELY NEW TEMPLATE BYTES\n'; }; \
    module::deactivate >/dev/null 2>&1; \
    [ ! -e \"\$(SNIP)\" ]; grep -qxF state=inactive \"\$(ACT)\""

assert_status "activate is still an idempotent no-op after a template change" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; \
    cp \"\$(ACT)\" \"\$HOME/m1\"; cp \"\$(SNIP)\" \"\$HOME/s1\"; \
    _starship_act_snippet_content() { printf 'ENTIRELY NEW TEMPLATE BYTES\n'; }; \
    module::activate >/dev/null 2>&1; \
    cmp -s \"\$HOME/m1\" \"\$(ACT)\"; cmp -s \"\$HOME/s1\" \"\$(SNIP)\""

# --- 13. interrupted activation is write-once (verbatim prior) -----------------
assert_status "interrupted activate reuses the recorded prior/backup, never relaunders" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; \
    printf 'REAL prior bytes\n' > \"\$HOME/prior\"; \
    P=\"\$(sha256sum \"\$HOME/prior\" | awk '{print \$1}')\"; \
    mkdir -p \"\$(BDIR)\"; chmod 700 \"\$(BDIR)\"; \
    cp \"\$HOME/prior\" \"\$(BDIR)/AAAAAA.prior\"; chmod 600 \"\$(BDIR)/AAAAAA.prior\"; \
    d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; chmod 700 \"\$d\"; \
    printf 'schema=1\nstate=activating\nprior_conf=present\nprior_conf_sha256=%s\nbackup_ref=AAAAAA.prior\nsnippet_sha256=%s\n' \"\$P\" \"\$(SHASH)\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; \
    mkdir -p \"\$(dirname \"\$(SNIP)\")\"; _starship_act_snippet_content > \"\$(SNIP)\"; chmod 644 \"\$(SNIP)\"; \
    module::activate >/dev/null 2>&1; \
    grep -qxF state=active \"\$(ACT)\"; \
    grep -qxF \"prior_conf_sha256=\$P\" \"\$(ACT)\"; grep -qxF backup_ref=AAAAAA.prior \"\$(ACT)\"; \
    module::deactivate >/dev/null 2>&1; cmp -s \"\$HOME/prior\" \"\$(SNIP)\""

# --- 14. interrupted deactivate finalizes (prior absent) -----------------------
assert_status "interrupted deactivate (prior absent, snippet deleted) finalizes" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::activate >/dev/null 2>&1; \
    rm -f \"\$(SNIP)\"; \
    module::deactivate >/dev/null 2>&1; \
    grep -qxF state=inactive \"\$(ACT)\"; ! grep -q prior_conf \"\$(ACT)\"; ! grep -q snippet_sha256 \"\$(ACT)\""

# --- 15. interrupted deactivate finalizes (prior present) — B1 -----------------
assert_status "interrupted deactivate (prior present, prior bytes on disk) finalizes without false drift" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; \
    mkdir -p \"\$(dirname \"\$(SNIP)\")\"; printf 'the users prior wiring\n' > \"\$(SNIP)\"; \
    cp \"\$(SNIP)\" \"\$HOME/prior\"; \
    module::activate >/dev/null 2>&1; \
    bref=\"\$(grep '^backup_ref=' \"\$(ACT)\" | cut -d= -f2)\"; \
    cp \"\$HOME/prior\" \"\$(SNIP)\"; \
    module::deactivate >/dev/null 2>&1; \
    grep -qxF state=inactive \"\$(ACT)\"; cmp -s \"\$HOME/prior\" \"\$(SNIP)\"; [ ! -e \"\$(BDIR)/\$bref\" ]"

# --- 15a. crash after state write, orphan backup inert -------------------------
assert_status "deactivate on inactive is a no-op and never touches an orphan backup" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; \
    d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; chmod 700 \"\$d\"; \
    printf 'schema=1\nstate=inactive\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; \
    mkdir -p \"\$(BDIR)\"; chmod 700 \"\$(BDIR)\"; printf 'orphan bytes\n' > \"\$(BDIR)/ZZZZZZ.prior\"; \
    module::deactivate >/dev/null 2>&1; \
    grep -qxF state=inactive \"\$(ACT)\"; [ -f \"\$(BDIR)/ZZZZZZ.prior\" ]; \
    grep -qxF 'orphan bytes' \"\$(BDIR)/ZZZZZZ.prior\""

# --- 16. refuse on a symlink / non-regular path --------------------------------
assert_status "activate refuses a symlink at the snippet path and writes no record" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; \
    mkdir -p \"\$(dirname \"\$(SNIP)\")\"; ln -s \"\$HOME/target\" \"\$(SNIP)\"; \
    module::activate 2>/dev/null && exit 1; \
    [ ! -e \"\$(ACT)\" ]; [ -L \"\$(SNIP)\" ]"

# --- 17. disown-then-reactivate never destroys the orphan backup — B2 ----------
assert_status "disown-then-reactivate mints a new unique backup and preserves the orphan" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; \
    mkdir -p \"\$(dirname \"\$(SNIP)\")\"; printf 'true pre-atlas config\n' > \"\$(SNIP)\"; \
    cp \"\$(SNIP)\" \"\$HOME/orig\"; \
    module::activate >/dev/null 2>&1; \
    B1=\"\$(grep '^backup_ref=' \"\$(ACT)\" | cut -d= -f2)\"; [ -f \"\$(BDIR)/\$B1\" ]; \
    rm -f \"\$(ACT)\"; \
    module::activate >/dev/null 2>&1; \
    B2=\"\$(grep '^backup_ref=' \"\$(ACT)\" | cut -d= -f2)\"; \
    [ -n \"\$B2\" ]; [ \"\$B1\" != \"\$B2\" ]; \
    [ -f \"\$(BDIR)/\$B1\" ]; cmp -s \"\$HOME/orig\" \"\$(BDIR)/\$B1\"; \
    grep -qxF state=active \"\$(ACT)\"; \
    cp \"\$(BDIR)/\$B2\" \"\$HOME/b2bytes\"; \
    module::deactivate >/dev/null 2>&1; \
    cmp -s \"\$HOME/b2bytes\" \"\$(SNIP)\"; [ ! -e \"\$(BDIR)/\$B2\" ]; \
    [ -f \"\$(BDIR)/\$B1\" ]; cmp -s \"\$HOME/orig\" \"\$(BDIR)/\$B1\""

# --- 18. non-default config path guard -----------------------------------------
assert_status "activate refuses when managed config does not resolve under ~/.config/atlas/starship" 0 \
  bash -c "$PRE; ATLAS_CONFIG_HOME=\"\$HOME/elsewhere\"; export ATLAS_CONFIG_HOME; \
    module::install >/dev/null 2>&1; \
    module::activate 2>/dev/null && exit 1; \
    [ ! -e \"\$(ACT)\" ]; [ ! -e \"\$(SNIP)\" ]"

# --- 19. strict parser ---------------------------------------------------------
assert_status "parser rejects prior_conf under inactive" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nprior_conf=present\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects snippet_sha256 under inactive" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; H=\$(printf abc | sha256sum | awk '{print \$1}'); printf 'schema=1\nstate=inactive\nsnippet_sha256=%s\n' \"\$H\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects missing prior_conf under active" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; H=\$(printf abc | sha256sum | awk '{print \$1}'); printf 'schema=1\nstate=active\nsnippet_sha256=%s\n' \"\$H\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects missing snippet_sha256 under active" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=active\nprior_conf=__ATLAS_ABSENT__\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects prior_conf_sha256 under __ATLAS_ABSENT__" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; H=\$(printf abc | sha256sum | awk '{print \$1}'); printf 'schema=1\nstate=active\nprior_conf=__ATLAS_ABSENT__\nprior_conf_sha256=%s\nsnippet_sha256=%s\n' \"\$H\" \"\$H\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects backup_ref under __ATLAS_ABSENT__" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; H=\$(printf abc | sha256sum | awk '{print \$1}'); printf 'schema=1\nstate=active\nprior_conf=__ATLAS_ABSENT__\nbackup_ref=x.prior\nsnippet_sha256=%s\n' \"\$H\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects missing prior_conf_sha256 under present" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; H=\$(printf abc | sha256sum | awk '{print \$1}'); printf 'schema=1\nstate=active\nprior_conf=present\nbackup_ref=x.prior\nsnippet_sha256=%s\n' \"\$H\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects missing backup_ref under present" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; H=\$(printf abc | sha256sum | awk '{print \$1}'); printf 'schema=1\nstate=active\nprior_conf=present\nprior_conf_sha256=%s\nsnippet_sha256=%s\n' \"\$H\" \"\$H\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects invalid snippet_sha256" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=active\nprior_conf=__ATLAS_ABSENT__\nsnippet_sha256=deadbeef\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects invalid prior_conf_sha256" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; H=\$(printf abc | sha256sum | awk '{print \$1}'); printf 'schema=1\nstate=active\nprior_conf=present\nprior_conf_sha256=nothex\nbackup_ref=x.prior\nsnippet_sha256=%s\n' \"\$H\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects backup_ref containing a slash" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; H=\$(printf abc | sha256sum | awk '{print \$1}'); printf 'schema=1\nstate=active\nprior_conf=present\nprior_conf_sha256=%s\nbackup_ref=a/b\nsnippet_sha256=%s\n' \"\$H\" \"\$H\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects backup_ref that is dot-dot" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; H=\$(printf abc | sha256sum | awk '{print \$1}'); printf 'schema=1\nstate=active\nprior_conf=present\nprior_conf_sha256=%s\nbackup_ref=..\nsnippet_sha256=%s\n' \"\$H\" \"\$H\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects out-of-range prior_conf value" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; H=\$(printf abc | sha256sum | awk '{print \$1}'); printf 'schema=1\nstate=active\nprior_conf=maybe\nsnippet_sha256=%s\n' \"\$H\" > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects an unknown key" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\nbogus=1\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects an unknown state" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=weird\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects a wrong schema" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=2\nstate=inactive\n' > \"\$(ACT)\"; chmod 600 \"\$(ACT)\"; _starship_act_load 2>/dev/null"
assert_status "parser rejects a marker whose mode is not 600" 1 \
  bash -c "$PRE; d=\"\$(dirname \"\$(ACT)\")\"; mkdir -p \"\$d\"; printf 'schema=1\nstate=inactive\n' > \"\$(ACT)\"; chmod 644 \"\$(ACT)\"; _starship_act_load 2>/dev/null"

# --- 20. deactivate is a no-op before activation -------------------------------
assert_status "deactivate before activation is a no-op that writes nothing" 0 \
  bash -c "$PRE; module::install >/dev/null 2>&1; module::deactivate >/dev/null 2>&1; [ ! -e \"\$(ACT)\" ]; [ ! -e \"\$(SNIP)\" ]"
