### Task 1: Real `os::dnf_install` package primitive

**Files:**
- Modify: `internal/os.sh` (replace the `os::dnf_install` placeholder with a real implementation)
- Test: `tests/test_os_dnf.sh` (new)

**Interfaces:**
- Produces: `os::dnf_install <pkg>...` — installs packages via dnf, idempotent (dnf is a no-op if already present), uses `sudo` only when not root, logs intent, returns non-zero on failure. Requires `dnf` (dies exit 5 via `os::require_cmd` if absent). `os::flatpak_install` is left as-is for now.

- [ ] **Step 1: Write the failing test `tests/test_os_dnf.sh`**

```bash
#!/usr/bin/env bash
# os::dnf_install is tested by shadowing `dnf` and `sudo` with shell FUNCTIONS
# (functions take precedence over PATH, so no real package manager is touched —
# safe on Fedora and non-Fedora alike). Each case runs in a child bash so the
# stubs never leak into the suite shell.

# success: dnf install is invoked with the packages, returns 0
out="$(bash -c '
  source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"
  dnf()  { printf "dnf-called: %s\n" "$*"; return 0; }
  sudo() { "$@"; }
  os::dnf_install git curl
' 2>/dev/null)"; rc=$?
assert_eq       "dnf_install returns 0 on success"      "$rc" "0"
assert_contains "dnf_install runs dnf install for pkgs" "$out" "dnf-called: install -y git curl"

# failure: dnf exits non-zero -> os::dnf_install returns non-zero
assert_status "dnf_install propagates dnf failure" 1 bash -c '
  source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"
  dnf()  { return 1; }
  sudo() { "$@"; }
  os::dnf_install git
'

# no args is a harmless no-op (exit 0)
assert_status "dnf_install no-op on empty args" 0 bash -c '
  source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"
  os::dnf_install
'
```

- [ ] **Step 2: Run it — confirm it fails**

Run: `bash tests/run.sh`
Expected: `test_os_dnf.sh` fails — the placeholder `os::dnf_install` only logs "would dnf install", so `dnf-called:` never appears and the failure case returns 0 instead of 1.

- [ ] **Step 3: Replace the placeholder in `internal/os.sh`**

Find:
```bash
# --- placeholder installers (real logic lands with the modules that need them) ---
os::dnf_install()     { log::info "would dnf install: $*"; }
os::flatpak_install() { log::info "would flatpak install: $*"; }
```
Replace with:
```bash
# Install one or more packages via dnf. Idempotent (dnf is a no-op for
# already-installed packages). Uses sudo only when not already root.
os::dnf_install() {
  [ "$#" -gt 0 ] || return 0
  os::require_cmd dnf
  local sudo=""
  os::is_root || sudo="sudo"
  log::info "installing packages: $*"
  if ! $sudo dnf install -y "$@"; then
    log::error "dnf install failed: $*"
    return 1
  fi
}

# flatpak install placeholder (promoted when the first flatpak module lands).
os::flatpak_install() { log::info "would flatpak install: $*"; }
```

- [ ] **Step 4: Run tests — confirm pass**

Run: `bash tests/run.sh`
Expected: `test_os_dnf.sh` all `ok`; suite total = 51 + 3 = **54 passed, 0 failed**.

- [ ] **Step 5: Commit**

```bash
git add internal/os.sh tests/test_os_dnf.sh
git -c commit.gpgsign=false commit -m "feat(os): make os::dnf_install a real idempotent package primitive

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

