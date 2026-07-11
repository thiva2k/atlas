# Authoring a Module

A module is a self-contained capability. Adding one needs **no** change to the
runner — discovery is automatic.

## 1. Create the directory

```
modules/<category>/<name>/
```

Categories in v1: `core`, `development`, `apps`, `desktop`. The category is the
directory — nothing declares it.

## 2. Write `module.sh`

```bash
#!/usr/bin/env bash
MODULE_NAME="example"
MODULE_DESCRIPTION="One line: what this capability is."
MODULE_DEPENDS=()            # e.g. ("core/git"); ids are "category/name"

# Required hooks --------------------------------------------------------------

# 0 = already present & configured (install is skipped); non-0 = work needed.
module::check() {
  os::has_cmd example
}

# Make it so. Safe to run repeatedly.
module::install() {
  os::dnf_install example
}

# 0 = healthy, or not installed by Atlas yet; non-0 = installed but broken.
module::verify() {
  os::has_cmd example
}

# Optional hooks: module::update, module::remove, module::backup, module::restore
```

## 3. Add `config/` (optional)

Any files the module owns live in `config/` beside it — never in a shared
top-level directory.

## 4. Write `README.md`

Answer three questions: what it does, what it installs/configures, what it
depends on.

## 5. Test it

```bash
bash atlas status <category>/<name>
bash atlas install <category>/<name>
bash tests/run.sh
```

That's the whole contract. `verify` must distinguish a valid pre-install state
from a broken installed state: a fresh workstation that Atlas has not touched is
not a failure, but Atlas-managed state that is missing, corrupt, or no longer
runnable is. If you ever feel the need to reach into another module's internals,
the contract is missing something — extend the contract instead.
