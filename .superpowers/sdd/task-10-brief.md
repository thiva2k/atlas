### Task 10: Bootstrap script (`bootstrap.sh`)

**Files:**
- Create: `bootstrap.sh`
- Test: `tests/test_bootstrap.sh`

**Interfaces:**
- Produces: `bootstrap.sh` — the zero-dependency first touch on a fresh machine. It ensures Git is present (logs the `dnf install git` it would run if missing), ensures the repo is present at `${ATLAS_HOME:-$HOME/atlas}` (clones if absent, otherwise leaves it), and hands off by printing the next command (`atlas install`). For v1 it must be **syntactically valid**, support `--help`, and must not perform destructive actions when run in a repo that already exists. Actual `dnf`/`git clone` calls are guarded behind a presence check so running it in CI/tests is safe.

- [ ] **Step 1: Write the failing test `tests/test_bootstrap.sh`**

```bash
#!/usr/bin/env bash
BOOT="$ATLAS_ROOT/bootstrap.sh"

assert_status "bootstrap parses (bash -n)" 0 bash -n "$BOOT"
assert_status "bootstrap --help exits 0"   0 bash "$BOOT" --help

out="$(bash "$BOOT" --help 2>&1)"
assert_contains "help mentions atlas install" "$out" "atlas install"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`bootstrap.sh` not found).

- [ ] **Step 3: Implement `bootstrap.sh`**

```bash
#!/usr/bin/env bash
# Atlas bootstrap — the only thing you run on a truly fresh machine.
# Ensures Git, fetches Atlas, and hands off to `atlas install`.
set -uo pipefail

ATLAS_REPO="${ATLAS_REPO:-https://github.com/thiva2k/atlas.git}"
ATLAS_HOME="${ATLAS_HOME:-$HOME/atlas}"

usage() {
  cat <<EOF
Atlas bootstrap

Prepares a fresh machine, then hands off to Atlas:
  1. ensure Git is installed
  2. clone Atlas into $ATLAS_HOME (if not already there)
  3. run:  cd $ATLAS_HOME && ./atlas install

Usage: bootstrap.sh [--help]
EOF
}

main() {
  case "${1:-}" in -h|--help) usage; return 0 ;; esac

  if ! command -v git >/dev/null 2>&1; then
    echo "git not found — installing (requires sudo)…"
    if command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y git
    else
      echo "no dnf available; install git manually and re-run" >&2
      return 1
    fi
  fi

  if [ ! -d "$ATLAS_HOME/.git" ]; then
    echo "cloning Atlas into $ATLAS_HOME…"
    git clone "$ATLAS_REPO" "$ATLAS_HOME"
  else
    echo "Atlas already present at $ATLAS_HOME — leaving it as is."
  fi

  echo
  echo "Bootstrap complete. Next:"
  echo "  cd $ATLAS_HOME && ./atlas install"
}

main "$@"
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_bootstrap.sh` all `ok`; suite `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add bootstrap.sh tests/test_bootstrap.sh
git -c commit.gpgsign=false commit -m "feat(bootstrap): add zero-dependency bootstrap entrypoint

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

