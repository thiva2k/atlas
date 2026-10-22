### Task 6: Dependency resolution / topological order (`internal/module.sh`)

**Files:**
- Modify: `internal/module.sh` (append `module::deps_of` and `module::resolve_order`)
- Test: `tests/test_module_order.sh`
- Test fixture: `tests/fixtures/modules/core/cyc_a/module.sh`, `tests/fixtures/modules/core/cyc_b/module.sh`

**Interfaces:**
- Consumes: `module::path`, `die`, `ATLAS_EXIT_DEPENDENCY`.
- Produces: `module::deps_of <id>` → prints each declared dependency id (reads `MODULE_DEPENDS` by sourcing the module in a subshell); `module::resolve_order <id...>` → prints the input ids plus their transitive deps in dependency-first order; a dependency **cycle** causes `die` with exit `3`.

- [ ] **Step 1: Write the cycle fixtures**

`tests/fixtures/modules/core/cyc_a/module.sh`:

```bash
#!/usr/bin/env bash
MODULE_NAME="cyc_a"
MODULE_DESCRIPTION="cycle fixture a"
MODULE_DEPENDS=("core/cyc_b")
module::check()   { return 1; }
module::install() { not_implemented "cyc_a"; }
module::verify()  { not_implemented "cyc_a"; }
```

`tests/fixtures/modules/core/cyc_b/module.sh`:

```bash
#!/usr/bin/env bash
MODULE_NAME="cyc_b"
MODULE_DESCRIPTION="cycle fixture b"
MODULE_DEPENDS=("core/cyc_a")
module::check()   { return 1; }
module::install() { not_implemented "cyc_b"; }
module::verify()  { not_implemented "cyc_b"; }
```

- [ ] **Step 2: Write the failing test `tests/test_module_order.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"
source "$ATLAS_ROOT/internal/module.sh"

assert_eq "beta declares its dep" "$(module::deps_of apps/beta)" "core/alpha"

# resolving beta pulls in alpha first
order="$(module::resolve_order apps/beta | tr '\n' ' ')"
assert_eq "dependency comes before dependent" "$order" "core/alpha apps/beta "

# a cycle is a fatal dependency error (exit 3)
assert_status "cycle detected as exit 3" 3 \
  bash -c 'source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; export ATLAS_MODULES_DIR="$ATLAS_ROOT/tests/fixtures/modules"; source "$ATLAS_ROOT/internal/module.sh"; module::resolve_order core/cyc_a'
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (`module::deps_of: command not found`).

- [ ] **Step 4: Append dependency resolution to `internal/module.sh`**

```bash
# --- dependency resolution -------------------------------------------------

# Print a module's declared dependencies (one per line), read in isolation.
module::deps_of() {
  local id="$1" p; p="$(module::path "$id")"
  [ -r "$p" ] || return 0
  ( set +u
    MODULE_DEPENDS=()
    # shellcheck source=/dev/null
    source "$p"
    local d
    for d in "${MODULE_DEPENDS[@]}"; do
      [ -n "$d" ] && printf '%s\n' "$d"
    done )
}

# Print ids + transitive deps in dependency-first order. Cycle => exit 3.
module::resolve_order() {
  local -a input=("$@")
  local -A _state=()          # unset | temp | done
  local -a _order=()

  _module_visit() {
    local id="$1" d
    case "${_state[$id]:-}" in
      done) return 0 ;;
      temp) die "$ATLAS_EXIT_DEPENDENCY" \
              "dependency cycle detected at '$id'" \
              "two or more modules depend on each other in a loop" \
              "break the loop by editing a module's MODULE_DEPENDS" ;;
    esac
    _state[$id]=temp
    while IFS= read -r d; do
      [ -n "$d" ] && _module_visit "$d"
    done < <(module::deps_of "$id")
    _state[$id]=done
    _order+=("$id")
  }

  local id
  for id in "${input[@]}"; do _module_visit "$id"; done
  printf '%s\n' "${_order[@]}"
}
```

- [ ] **Step 5: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_module_order.sh` all `ok`; suite `0 failed`.

- [ ] **Step 6: Commit**

```bash
git add internal/module.sh tests/test_module_order.sh tests/fixtures/
git -c commit.gpgsign=false commit -m "feat(internal): resolve module dependencies with cycle detection

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

