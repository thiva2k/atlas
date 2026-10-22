### Task 4: OS / environment helpers (`internal/os.sh`)

**Files:**
- Create: `internal/os.sh`
- Test: `tests/test_os.sh`

**Interfaces:**
- Consumes: `log::*`, `die`, `ATLAS_EXIT_UNSUPPORTED`.
- Produces: `os::has_cmd <cmd>` (bool), `os::require_cmd <cmd>` (dies if missing), `os::is_fedora` (bool via `/etc/os-release`), `os::is_root` (bool). Placeholder install wrappers `os::dnf_install <pkgs...>` and `os::flatpak_install <pkgs...>` that only log intent for now.

- [ ] **Step 1: Write the failing test `tests/test_os.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"

assert_status "has_cmd true for bash"      0 os::has_cmd bash
assert_status "has_cmd false for nonesuch" 1 os::has_cmd this_command_does_not_exist_xyz
assert_status "require_cmd dies on missing" 5 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"; os::require_cmd nope_xyz'

out="$(os::dnf_install git curl 2>&1 || true)"
assert_contains "dnf_install logs intent" "$out" "git curl"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`os::has_cmd: command not found`).

- [ ] **Step 3: Implement `internal/os.sh`**

```bash
#!/usr/bin/env bash
[ -n "${ATLAS_OS_SH:-}" ] && return 0; ATLAS_OS_SH=1

os::has_cmd() { command -v "$1" >/dev/null 2>&1; }

os::require_cmd() {
  os::has_cmd "$1" && return 0
  die "$ATLAS_EXIT_UNSUPPORTED" \
    "required command not found: $1" \
    "Atlas needs '$1' on PATH to continue" \
    "install '$1' and re-run"
}

os::is_fedora() {
  [ -r /etc/os-release ] || return 1
  grep -qi '^ID=fedora$' /etc/os-release
}

os::is_root() { [ "$(id -u)" -eq 0 ]; }

# --- placeholder installers (real logic lands with the modules that need them) ---
os::dnf_install()     { log::info "would dnf install: $*"; }
os::flatpak_install() { log::info "would flatpak install: $*"; }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_os.sh` all `ok`; suite `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add internal/os.sh tests/test_os.sh
git -c commit.gpgsign=false commit -m "feat(internal): add OS detection and install placeholder helpers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

