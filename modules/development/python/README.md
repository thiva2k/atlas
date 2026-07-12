# python

**What it does:** Installs Fedora's system Python runtime and Fedora-provided
pip package, then records Atlas ownership with a marker.

**Installs / verifies:**

- `python3`
- `python3-pip`
- `/usr/bin/python3`
- `/usr/bin/pip3`

**Depends on:** nothing.

Atlas owns only the Fedora package intent and its install marker. Existing
Fedora Python is normal on a workstation; Atlas does not infer ownership from
the runtime's presence until `atlas install development/python` writes the
marker.

Atlas never manages:

- virtual environments
- user packages
- global `pip install` state
- `pip.conf`
- `PIP_*` environment policy
- pipx
- Poetry
- uv
- pyenv
- Conda
- project dependency files
- application state

Verification uses fixed system paths, not `PATH`, so virtualenv, pyenv, Conda,
and project shims do not affect Atlas's managed-runtime decision.

`update`, `backup`, and `restore` are documented no-ops. Package currency is
handled by Fedora updates, and Python environments/packages are user-owned.

The `remove` hook deletes only the Atlas marker. It never uninstalls Python or
pip, because those packages are shared system/runtime dependencies.
