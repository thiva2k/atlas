### Task 2: Logging engine (`internal/log.sh`)

**Files:**
- Create: `internal/log.sh`
- Test: `tests/test_log.sh`

**Interfaces:**
- Produces: `log::debug|info|warn|error|step <msg...>`. Honors `ATLAS_LOG_LEVEL` (`debug|info|warn|error`, default `info`). Writes user output to **stderr**, colored only when stderr is a TTY. Always appends a plain line to `$ATLAS_STATE_DIR/logs/atlas-<YYYYMMDD>.log`. Scope tag comes from `ATLAS_LOG_SCOPE` (default `atlas`). Format: `<ISO-8601-ts>  <LEVEL>  [<scope>]  <msg>`.

- [ ] **Step 1: Write the failing test `tests/test_log.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"

# info is emitted at default level
out="$(ATLAS_LOG_LEVEL=info log::info "hello" 2>&1 1>/dev/null)"
assert_contains "info line has level"   "$out" "INFO"
assert_contains "info line has message" "$out" "hello"
assert_contains "info line has scope"   "$out" "[atlas]"

# debug is suppressed when the floor is info
out="$(ATLAS_LOG_LEVEL=info log::debug "quiet" 2>&1 1>/dev/null)"
assert_eq "debug suppressed at info level" "$out" ""

# scope override is honored
out="$(ATLAS_LOG_SCOPE=git log::info "scoped" 2>&1 1>/dev/null)"
assert_contains "scope override applies" "$out" "[git]"

# every call persists to the logfile
logf="$ATLAS_STATE_DIR/logs/atlas-$(date +%Y%m%d).log"
log::warn "persist-me" 2>/dev/null
assert_contains "logfile captured the line" "$(cat "$logf")" "persist-me"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`internal/log.sh` does not exist / `log::info: command not found`).

- [ ] **Step 3: Implement `internal/log.sh`**

```bash
#!/usr/bin/env bash
[ -n "${ATLAS_LOG_SH:-}" ] && return 0; ATLAS_LOG_SH=1

: "${ATLAS_LOG_LEVEL:=info}"
: "${ATLAS_STATE_DIR:=${XDG_STATE_HOME:-$HOME/.local/state}/atlas}"

_log_level_num() {
  case "$1" in
    debug) echo 0 ;; info) echo 1 ;; warn) echo 2 ;; error) echo 3 ;; *) echo 1 ;;
  esac
}

_log_file() {
  local dir="$ATLAS_STATE_DIR/logs"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s/atlas-%s.log' "$dir" "$(date +%Y%m%d)"
}

_log_emit() { # <level> <color> <msg>
  local level="$1" color="$2" msg="$3"
  local ts scope line
  ts="$(date +%Y-%m-%dT%H:%M:%S)"
  scope="${ATLAS_LOG_SCOPE:-atlas}"
  line="$ts  $(printf '%s' "$level" | tr '[:lower:]' '[:upper:]')  [$scope]  $msg"
  printf '%s\n' "$line" >> "$(_log_file)" 2>/dev/null || true
  if [ "$(_log_level_num "$level")" -ge "$(_log_level_num "$ATLAS_LOG_LEVEL")" ]; then
    if [ -t 2 ] && [ -n "$color" ]; then
      printf '%b%s%b\n' "$color" "$line" '\033[0m' >&2
    else
      printf '%s\n' "$line" >&2
    fi
  fi
}

log::debug() { _log_emit debug '\033[2m'    "$*"; }
log::info()  { _log_emit info  ''           "$*"; }
log::warn()  { _log_emit warn  '\033[33m'   "$*"; }
log::error() { _log_emit error '\033[31m'   "$*"; }
log::step()  { _log_emit info  '\033[1;36m' "== $* =="; }
```

- [ ] **Step 4: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: the `test_log.sh` block shows all `ok`, suite still `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add internal/log.sh tests/test_log.sh
git -c commit.gpgsign=false commit -m "feat(internal): add reusable logging engine

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

