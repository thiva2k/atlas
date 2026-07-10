### Task 5: Module discovery + contract helpers (`internal/module.sh`)

**Files:**
- Create: `internal/module.sh`
- Test: `tests/test_module_discovery.sh`
- Test fixtures: `tests/fixtures/modules/core/alpha/module.sh`, `tests/fixtures/modules/apps/beta/module.sh`

**Interfaces:**
- Consumes: `log::*`, `die`, exit codes, `$ATLAS_ROOT`.
- Produces: `ATLAS_MODULES_DIR` (default `$ATLAS_ROOT/modules`); `module::discover` → prints `category/name` per module, sorted; `module::path <id>` → path to its `module.sh`; `module::has_hook <hook>` → true if `module::<hook>` is defined in the current (sourced) shell; `not_implemented <what>` → logs a warning and returns 0 (used by placeholder hooks). Dependency ordering is added in Task 6.

- [ ] **Step 1: Write the fixture modules**

`tests/fixtures/modules/core/alpha/module.sh`:

```bash
#!/usr/bin/env bash
MODULE_NAME="alpha"
MODULE_DESCRIPTION="fixture module alpha"
MODULE_DEPENDS=()
module::check()   { return 1; }
module::install() { not_implemented "alpha install"; }
module::verify()  { not_implemented "alpha verify"; }
```

`tests/fixtures/modules/apps/beta/module.sh`:

```bash
#!/usr/bin/env bash
MODULE_NAME="beta"
MODULE_DESCRIPTION="fixture module beta (depends on alpha)"
MODULE_DEPENDS=("core/alpha")
module::check()   { return 1; }
module::install() { not_implemented "beta install"; }
module::verify()  { not_implemented "beta verify"; }
```

- [ ] **Step 2: Write the failing test `tests/test_module_discovery.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"
source "$ATLAS_ROOT/internal/module.sh"

found="$(module::discover | tr '\n' ' ')"
assert_contains "discovers alpha" "$found" "core/alpha"
assert_contains "discovers beta"  "$found" "apps/beta"

assert_eq "path points at module.sh" \
  "$(module::path core/alpha)" "$ATLAS_MODULES_DIR/core/alpha/module.sh"

# has_hook works after sourcing a module
( source "$(module::path core/alpha)"
  assert_status "alpha defines install hook" 0 module::has_hook install
  assert_status "alpha lacks backup hook"    1 module::has_hook backup )

out="$(not_implemented "x" 2>&1 || true)"
assert_contains "not_implemented warns" "$out" "not yet implemented"
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`module::discover: command not found`).

- [ ] **Step 4: Implement discovery portion of `internal/module.sh`**

```bash
#!/usr/bin/env bash
[ -n "${ATLAS_MODULE_SH:-}" ] && return 0; ATLAS_MODULE_SH=1

: "${ATLAS_MODULES_DIR:=${ATLAS_ROOT:-.}/modules}"

# Placeholder-hook helper, available to modules once this file is sourced.
not_implemented() { log::warn "not yet implemented: $*"; return 0; }

# Print every module id ("category/name"), one per line, sorted.
module::discover() {
  local f id
  for f in "$ATLAS_MODULES_DIR"/*/*/module.sh; do
    [ -e "$f" ] || continue
    id="${f#"$ATLAS_MODULES_DIR"/}"
    id="${id%/module.sh}"
    printf '%s\n' "$id"
  done | sort
}

module::path() { printf '%s\n' "$ATLAS_MODULES_DIR/$1/module.sh"; }

module::has_hook() { declare -F "module::$1" >/dev/null 2>&1; }

# Dependency ordering (module::deps_of, module::resolve_order) is added in Task 6.
```

- [ ] **Step 5: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_module_discovery.sh` all `ok`; suite `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add internal/module.sh tests/test_module_discovery.sh tests/fixtures/
git -c commit.gpgsign=false commit -m "feat(internal): add module discovery and contract helpers

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

