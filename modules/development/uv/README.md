# uv

**What it does:** Installs Fedora's `uv` package and records Atlas ownership
with a marker.

**Installs / verifies:**

- `uv`
- `/usr/bin/uv`

**Depends on:** `development/python`.

Atlas owns only Fedora package intent and its install marker. Existing uv
installations are valid user-owned state until `atlas install development/uv`
writes the marker.

Atlas never manages:

- uv caches
- project virtual environments
- `pyproject.toml`
- `uv.lock`
- project dependencies
- uv-managed Python versions
- uv-installed tools
- package indexes
- credentials
- uv configuration
- shell completions
- shell startup files

Verification uses the fixed system path, not `PATH`, so pipx, Cargo,
standalone-installer, project, and shell shims do not affect Atlas's managed CLI
decision.

`update`, `backup`, and `restore` are documented no-ops. Package currency is
handled by Fedora updates, and uv project/tool/cache state is user-owned.

The `remove` hook deletes only the Atlas marker. It never uninstalls uv.
