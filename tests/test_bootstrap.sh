#!/usr/bin/env bash
BOOT="$ATLAS_ROOT/bootstrap.sh"

assert_status "bootstrap parses (bash -n)" 0 bash -n "$BOOT"
assert_status "bootstrap --help exits 0"   0 bash "$BOOT" --help

out="$(bash "$BOOT" --help 2>&1)"
assert_contains "help mentions atlas install" "$out" "atlas install"
assert_contains "help mentions atlasctl install" "$out" "atlasctl install"

_bootstrap_fake_git() {
  local dir="$1"
  mkdir -p "$dir" || return 1
  cat > "$dir/git" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
if [ "${1:-}" = "clone" ]; then
  mkdir -p "$3/.git" || exit 1
  printf '#!/usr/bin/env bash\nprintf "0.1.0-dev\\n"\n' > "$3/atlasctl" || exit 1
  chmod +x "$3/atlasctl" || exit 1
  exit 0
fi
if [ "${1:-}" = "-C" ]; then
  shift 2
fi
if [ "${1:-}" = "symbolic-ref" ] && [ "${2:-}" = "--short" ] && [ "${3:-}" = "HEAD" ]; then
  printf 'main\n'
  exit 0
fi
exit 1
EOF
  chmod +x "$dir/git" || return 1
}

home="$(mktemp -d)"
bin="$home/bin"
_bootstrap_fake_git "$bin"
ATLAS_HOME="$home/atlas" ATLAS_STATE_DIR="$home/state/atlas" HOME="$home" PATH="$bin:$PATH" \
  bash "$BOOT" >/dev/null 2>&1
marker="$home/state/atlas/installed/atlas-self"
assert_eq "bootstrap records self-management marker for fresh canonical clone" "$(grep -c '^remote_identity=github.com/thiva2k/atlas$' "$marker" 2>/dev/null)" "1"
assert_eq "bootstrap self-management marker records executable" "$(grep -c "^executable=$home/atlas/atlasctl$" "$marker" 2>/dev/null)" "1"
assert_eq "bootstrap installs managed atlasctl launcher" "$(readlink "$home/.local/bin/atlasctl" 2>/dev/null)" "$home/atlas/atlasctl"
assert_eq "bootstrap leaves atlas command namespace untouched" "$([ -e "$home/.local/bin/atlas" ] && echo yes || echo no)" "no"
assert_eq "bootstrap self-management marker records atlasctl launcher" "$(grep -c "^launcher=$home/.local/bin/atlasctl$" "$marker" 2>/dev/null)" "1"
assert_eq "bootstrap self-management marker mode is 600" "$(stat -c '%a' "$marker" 2>/dev/null)" "600"
assert_eq "bootstrap self-management marker parent mode is 700" "$(stat -c '%a' "$(dirname "$marker")" 2>/dev/null)" "700"

home="$(mktemp -d)"
bin="$home/bin"
_bootstrap_fake_git "$bin"
mkdir -p "$home/atlas/.git"
ATLAS_HOME="$home/atlas" ATLAS_STATE_DIR="$home/state/atlas" HOME="$home" PATH="$bin:$PATH" \
  bash "$BOOT" >/dev/null 2>&1
assert_eq "bootstrap does not adopt an existing checkout" "$([ -e "$home/state/atlas/installed/atlas-self" ] && echo yes || echo no)" "no"
assert_eq "bootstrap does not install launcher for existing unmanaged checkout" "$([ -e "$home/.local/bin/atlasctl" ] && echo yes || echo no)" "no"

home="$(mktemp -d)"
bin="$home/bin"
_bootstrap_fake_git "$bin"
ATLAS_REPO="https://github.com/example/atlas.git" ATLAS_HOME="$home/atlas" ATLAS_STATE_DIR="$home/state/atlas" HOME="$home" PATH="$bin:$PATH" \
  bash "$BOOT" >/dev/null 2>&1
assert_eq "bootstrap does not mark custom repositories as self-managed" "$([ -e "$home/state/atlas/installed/atlas-self" ] && echo yes || echo no)" "no"
assert_eq "bootstrap does not install launcher for custom repositories" "$([ -e "$home/.local/bin/atlasctl" ] && echo yes || echo no)" "no"

home="$(mktemp -d)"
bin="$home/bin"
_bootstrap_fake_git "$bin"
mkdir -p "$home/.local/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$home/.local/bin/atlasctl"
chmod +x "$home/.local/bin/atlasctl"
ATLAS_HOME="$home/atlas" ATLAS_STATE_DIR="$home/state/atlas" HOME="$home" PATH="$bin:$PATH" \
  bash "$BOOT" >/dev/null 2>&1
assert_eq "bootstrap does not overwrite an existing atlasctl launcher" "$(readlink "$home/.local/bin/atlasctl" 2>/dev/null || printf 'not-link')" "not-link"
assert_eq "bootstrap does not self-manage when launcher is user-owned" "$([ -e "$home/state/atlas/installed/atlas-self" ] && echo yes || echo no)" "no"

home="$(mktemp -d)"
bin="$home/bin"
_bootstrap_fake_git "$bin"
mkdir -p "$home/.local/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$home/.local/bin/atlas"
chmod +x "$home/.local/bin/atlas"
ATLAS_HOME="$home/atlas" ATLAS_STATE_DIR="$home/state/atlas" HOME="$home" PATH="$bin:$PATH" \
  bash "$BOOT" >/dev/null 2>&1
assert_eq "bootstrap allows an existing unrelated atlas command" "$([ -e "$home/state/atlas/installed/atlas-self" ] && echo yes || echo no)" "yes"
assert_eq "bootstrap keeps existing unrelated atlas command" "$(readlink "$home/.local/bin/atlas" 2>/dev/null || printf 'not-link')" "not-link"
assert_eq "bootstrap still installs atlasctl when atlas exists" "$(readlink "$home/.local/bin/atlasctl" 2>/dev/null)" "$home/atlas/atlasctl"
