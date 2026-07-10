### Task 8: The CLI entrypoint (`atlas`)

**Files:**
- Create: `atlas` (executable, no extension)
- Test: `tests/test_cli.sh`

**Interfaces:**
- Consumes: everything in `internal/`.
- Produces: the `atlas` executable. Resolves `ATLAS_ROOT` from its own location (following symlinks), sources the engine, sets `set -uo pipefail`, parses global flags (`-v/--verbose`, `-q/--quiet`, `--version`, `-h/--help`), takes the first non-flag as the verb and the rest as module ids, and dispatches: `help`/`version` handled locally, the seven platform verbs go to `runner::run`, no verb → help, unknown verb/option → exit `2`. Runner exit codes propagate.

- [ ] **Step 1: Write the failing test `tests/test_cli.sh`**

```bash
#!/usr/bin/env bash
ATLAS="$ATLAS_ROOT/atlas"
# point the CLI at the fixture modules so it runs without real ones
export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"

assert_status "help exits 0"          0 bash "$ATLAS" --help
assert_status "version exits 0"       0 bash "$ATLAS" --version
assert_status "unknown verb exits 2"  2 bash "$ATLAS" frobnicate
assert_status "unknown option exits 2" 2 bash "$ATLAS" --nope
assert_status "install on fixtures 0" 0 bash "$ATLAS" install core/alpha apps/beta

out="$(bash "$ATLAS" --help 2>&1)"
assert_contains "help shows usage"    "$out" "Usage: atlas"
assert_contains "help lists install"  "$out" "install"

out="$(bash "$ATLAS" --version 2>&1)"
assert_contains "version prints a number" "$out" "0.1.0"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`atlas` file not found).

- [ ] **Step 3: Implement `atlas`**

```bash
#!/usr/bin/env bash
# Atlas — workstation lifecycle manager. CLI entrypoint.
set -uo pipefail

# Resolve ATLAS_ROOT = directory of this script, following symlinks.
_src="${BASH_SOURCE[0]}"
while [ -h "$_src" ]; do
  _dir="$(cd -P "$(dirname "$_src")" >/dev/null 2>&1 && pwd)"
  _src="$(readlink "$_src")"
  case "$_src" in /*) ;; *) _src="$_dir/$_src" ;; esac
done
ATLAS_ROOT="$(cd -P "$(dirname "$_src")" >/dev/null 2>&1 && pwd)"
export ATLAS_ROOT

ATLAS_VERSION="0.1.0-dev"

source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/internal/module.sh"
source "$ATLAS_ROOT/internal/runner.sh"

usage() {
  cat <<EOF
Atlas — workstation lifecycle manager (v$ATLAS_VERSION)

Usage: atlas <command> [modules...] [options]

Commands:
  install    ensure modules are present & configured
  update     bring modules to their latest desired state
  verify     check that modules are healthy
  backup     capture irreplaceable module state
  restore    re-apply previously captured state
  doctor     diagnose the workstation
  status     show what is / isn't installed
  help       show this help
  version    show the version

Options:
  -v, --verbose   more output (debug level)
  -q, --quiet     less output (errors only)
      --version   print version and exit
  -h, --help      print this help and exit
EOF
}

main() {
  local verb="" ; local -a rest=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -v|--verbose) ATLAS_LOG_LEVEL=debug ;;
      -q|--quiet)   ATLAS_LOG_LEVEL=error ;;
      --version)    echo "$ATLAS_VERSION"; return 0 ;;
      -h|--help)    usage; return 0 ;;
      -*)           die "$ATLAS_EXIT_USAGE" "unknown option: $1" "" "run 'atlas --help'" ;;
      *)            if [ -z "$verb" ]; then verb="$1"; else rest+=("$1"); fi ;;
    esac
    shift
  done
  export ATLAS_LOG_LEVEL

  case "${verb:-help}" in
    help)    usage ;;
    version) echo "$ATLAS_VERSION" ;;
    install|update|verify|backup|restore|doctor|status)
      runner::run "$verb" "${rest[@]}" ;;
    *) die "$ATLAS_EXIT_USAGE" "unknown command: $verb" "" "run 'atlas --help'" ;;
  esac
}

main "$@"
```

- [ ] **Step 4: Make it executable and run tests**

Run: `chmod +x atlas && bash tests/run.sh`
Expected: `test_cli.sh` all `ok`; suite `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add atlas tests/test_cli.sh
git -c commit.gpgsign=false commit -m "feat(cli): add atlas entrypoint dispatching platform verbs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

