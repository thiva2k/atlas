### Task 2: Shared `atlas.env` reader (`internal/env.sh`)

**Files:**
- Create: `internal/env.sh`
- Modify: `atlas` (source `internal/env.sh` alongside the other engine files)
- Test: `tests/test_env.sh` (new)

**Interfaces:**
- Produces: `env::get <NAME>` — echoes the user-supplied value of `NAME`, resolved from the environment variable `NAME` first, then a `NAME=value` line in `${ATLAS_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/atlas}/atlas.env` (one layer of surrounding quotes stripped; `#` comments and blank lines ignored; last matching line wins). Prints nothing and returns 1 when unset in both. This is the standard source of user-specific config for all modules.

- [ ] **Step 1: Write the failing test `tests/test_env.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/env.sh"

# sandbox a config home with an atlas.env
sandbox="$(mktemp -d)"
export ATLAS_CONFIG_HOME="$sandbox"
printf '# a comment\nATLAS_GIT_USER_NAME="Ada Lovelace"\nATLAS_GIT_USER_EMAIL=ada@example.com\n' > "$sandbox/atlas.env"

# value read from atlas.env (quotes stripped)
assert_eq "env::get reads a quoted value from atlas.env" \
  "$(unset ATLAS_GIT_USER_NAME; env::get ATLAS_GIT_USER_NAME)" "Ada Lovelace"
assert_eq "env::get reads an unquoted value from atlas.env" \
  "$(unset ATLAS_GIT_USER_EMAIL; env::get ATLAS_GIT_USER_EMAIL)" "ada@example.com"

# environment variable wins over the file
assert_eq "env var overrides atlas.env" \
  "$(ATLAS_GIT_USER_EMAIL='env@x' env::get ATLAS_GIT_USER_EMAIL)" "env@x"

# missing key -> non-zero, empty output
assert_status "missing key returns non-zero" 1 env::get ATLAS_DEFINITELY_MISSING_XYZ
assert_eq     "missing key prints nothing"   "$(env::get ATLAS_DEFINITELY_MISSING_XYZ 2>/dev/null)" ""

# comment lines are ignored (no key named '# a comment')
rm -rf "$sandbox"; unset ATLAS_CONFIG_HOME
```

- [ ] **Step 2: Run it — confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`env::get: command not found` / `internal/env.sh` missing).

- [ ] **Step 3: Implement `internal/env.sh`**

```bash
#!/usr/bin/env bash
[ -n "${ATLAS_ENV_SH:-}" ] && return 0; ATLAS_ENV_SH=1

: "${ATLAS_CONFIG_HOME:=${XDG_CONFIG_HOME:-$HOME/.config}/atlas}"

# env::get <NAME> — echo the user-supplied value of NAME.
# Resolution order: environment variable NAME, then NAME=value in atlas.env.
# Prints nothing and returns 1 if NAME is set in neither.
env::get() {
  local name="$1"
  if [ -n "${!name:-}" ]; then
    printf '%s\n' "${!name}"
    return 0
  fi
  local file="${ATLAS_CONFIG_HOME}/atlas.env"
  [ -r "$file" ] || return 1
  local line val=""
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    case "$line" in
      \#*) continue ;;
      "$name="*) val="${line#*=}" ;;
    esac
  done < "$file"
  [ -n "$val" ] || return 1
  # strip one layer of surrounding double or single quotes
  val="${val%\"}"; val="${val#\"}"
  val="${val%\'}"; val="${val#\'}"
  printf '%s\n' "$val"
}
```

- [ ] **Step 4: Wire it into the `atlas` entrypoint**

In `atlas`, find the engine-sourcing block:
```bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/internal/module.sh"
source "$ATLAS_ROOT/internal/runner.sh"
```
Add the `env.sh` source after `os.sh` (so module hooks running in the runner's subshell inherit `env::get`):
```bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/os.sh"
source "$ATLAS_ROOT/internal/env.sh"
source "$ATLAS_ROOT/internal/module.sh"
source "$ATLAS_ROOT/internal/runner.sh"
```

- [ ] **Step 5: Run tests — confirm pass**

Run: `bash tests/run.sh`
Expected: `test_env.sh` all `ok`; suite = 54 + 5 = **59 passed, 0 failed**. Also confirm `bash atlas --help` still exits 0 (entrypoint still sources cleanly).

- [ ] **Step 6: Commit**

```bash
git add internal/env.sh atlas tests/test_env.sh
git -c commit.gpgsign=false commit -m "feat(env): add atlas.env reader for user-specific config

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

