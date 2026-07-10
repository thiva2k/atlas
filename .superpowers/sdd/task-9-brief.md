### Task 9: The eight placeholder modules

**Files:**
- Create per module: `modules/<category>/<name>/module.sh` + `README.md`
  - `modules/core/git/` (+ `config/gitconfig.template`)
  - `modules/development/docker/`
  - `modules/development/claude/`
  - `modules/development/codex/`
  - `modules/apps/brave/`
  - `modules/apps/ghostty/`
  - `modules/desktop/kde/`
  - `modules/desktop/fonts/`
- Test: `tests/test_modules.sh`

**Interfaces:**
- Consumes: the module contract; `not_implemented`.
- Produces: eight real modules with metadata + `check`/`install`/`verify` placeholder hooks (`check` returns 1 so the install path is exercised; `install`/`verify` call `not_implemented` and return 0). `modules/core/git` additionally ships a `config/` directory and declares no dependencies; `development/docker` depends on `core/git` only if genuinely needed — for v1 all `MODULE_DEPENDS=()` to keep the graph flat. Every module has a README answering the three standard questions.

- [ ] **Step 1: Write the failing test `tests/test_modules.sh`**

```bash
#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"
source "$ATLAS_ROOT/internal/error.sh"
source "$ATLAS_ROOT/internal/module.sh"   # uses real ATLAS_MODULES_DIR ($ATLAS_ROOT/modules)

expected="apps/brave apps/ghostty core/git desktop/fonts desktop/kde development/claude development/codex development/docker"
got="$(module::discover | tr '\n' ' ' | sed 's/ *$//')"
assert_eq "all eight modules discovered" "$got" "$expected"

# every module satisfies the contract: metadata + three required hooks + README
fail=0
while IFS= read -r id; do
  p="$(module::path "$id")"
  ( source "$p"
    [ -n "${MODULE_NAME:-}" ]        || exit 1
    [ -n "${MODULE_DESCRIPTION:-}" ] || exit 1
    declare -F module::check   >/dev/null || exit 1
    declare -F module::install >/dev/null || exit 1
    declare -F module::verify  >/dev/null || exit 1 ) || { fail=1; printf 'contract miss: %s\n' "$id"; }
  [ -r "${p%/module.sh}/README.md" ] || { fail=1; printf 'missing README: %s\n' "$id"; }
done < <(module::discover)
assert_eq "every module satisfies the contract + has a README" "$fail" "0"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash tests/run.sh`
Expected: FAIL (no modules under `modules/`; discovery empty).

- [ ] **Step 3: Write the git module** — `modules/core/git/module.sh`

```bash
#!/usr/bin/env bash
MODULE_NAME="git"
MODULE_DESCRIPTION="Distributed version control: installs git and applies global config."
MODULE_DEPENDS=()

module::check()   { return 1; }               # TODO: os::has_cmd git && gitconfig applied
module::install() { not_implemented "git: dnf install git + apply config/gitconfig.template"; }
module::verify()  { not_implemented "git: git --version and config sanity"; }
```

- [ ] **Step 4: Write git's config template** — `modules/core/git/config/gitconfig.template`

```ini
# Applied by the git module (placeholder — not yet wired up).
[init]
	defaultBranch = main
[pull]
	rebase = true
```

- [ ] **Step 5: Write git's README** — `modules/core/git/README.md`

```markdown
# git

**What it does:** Installs Git and applies a global configuration.

**Installs / configures:** the `git` package; a global `~/.gitconfig` derived
from `config/gitconfig.template`.

**Depends on:** nothing.

> Status: placeholder. Hooks log "not yet implemented"; real logic lands later.
```

- [ ] **Step 6: Write the remaining seven modules** (same shape; adjust name/description/paths)

For each of `development/docker`, `development/claude`, `development/codex`, `apps/brave`, `apps/ghostty`, `desktop/kde`, `desktop/fonts`, create `module.sh`:

```bash
#!/usr/bin/env bash
MODULE_NAME="<name>"
MODULE_DESCRIPTION="<one-line description>"
MODULE_DEPENDS=()

module::check()   { return 1; }
module::install() { not_implemented "<name> install"; }
module::verify()  { not_implemented "<name> verify"; }
```

Use these descriptions verbatim:
- `development/docker` → "Container runtime: installs Docker Engine and enables the service."
- `development/claude` → "Claude Code CLI: installs the CLI and restores its configuration."
- `development/codex` → "Codex CLI: installs the CLI and restores its configuration."
- `apps/brave` → "Brave browser: installs Brave via its official repository."
- `apps/ghostty` → "Ghostty terminal: installs the Ghostty terminal emulator."
- `desktop/kde` → "KDE Plasma: installs and configures the KDE Plasma desktop."
- `desktop/fonts` → "Developer fonts: installs Nerd Fonts and common typefaces."

And a `README.md` for each, following the git template (What it does / Installs-configures / Depends on / placeholder status).

- [ ] **Step 7: Run tests to verify pass**

Run: `bash tests/run.sh`
Expected: `test_modules.sh` all `ok`; suite `0 failed`.

- [ ] **Step 8: Smoke-test the whole system end-to-end**

Run: `bash atlas status && bash atlas install && bash atlas verify`
Expected: each exits 0, prints a `== atlas <verb> (8 modules) ==` step line and a `done: … ok, … skipped, … failed` summary with `0 failed`.

- [ ] **Step 9: Commit**

```bash
git add modules/ tests/test_modules.sh
git -c commit.gpgsign=false commit -m "feat(modules): add eight placeholder modules across four categories

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

