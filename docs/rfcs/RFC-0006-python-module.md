# RFC-0006: Python Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-11 |
| **Phase / order** | Phase 2 — Language runtimes · module 5 of 16 |
| **Depends on** | Nothing — `MODULE_DEPENDS=()` |
| **Establishes** | The lifecycle pattern for Fedora-packaged language runtimes |

---

## 1. Summary

Implement `modules/development/python` as Atlas's lifecycle manager for the
Fedora system Python runtime. Atlas installs and verifies Fedora's `python3`
package and the Fedora-provided `python3-pip` package. It records ownership with
an Atlas marker and does not manage project dependencies, virtual environments,
Python version managers, pip configuration, or user-installed packages.

Python is different from Docker: a Fedora workstation commonly already has
`/usr/bin/python3` because Fedora itself uses Python. Atlas must therefore not
treat pre-existing Python as a conflict. Running `atlas install
development/python` enrolls the Fedora package intent by invoking DNF
idempotently, validating the fixed system commands, and writing a marker. Without
that marker, Python remains unmanaged and `verify` succeeds as valid pre-install
or unmanaged state.

The central rule is:

> Atlas owns the Fedora system runtime installation intent, never a user's Python
> environments, packages, or project state.

## 2. Goals and non-goals

**Goals**

- Install Fedora's `python3` package.
- Install Fedora's `python3-pip` package as the managed pip provider.
- Verify the fixed system runtime at `/usr/bin/python3`.
- Verify the fixed system pip command at `/usr/bin/pip3`.
- Record Atlas ownership through a strict marker.
- Provide idempotent `check`, `install`, `verify`, `update`, `remove`,
  `backup`, and `restore` hooks.
- Establish a small, repeatable pattern for future language runtime modules.

**Non-goals**

- Managing virtual environments.
- Managing user packages, global `pip install` state, `site-packages`, or PyPI
  credentials.
- Managing `pip.conf` or any pip policy.
- Installing or configuring `pipx`, Poetry, uv, pyenv, Conda, asdf, direnv, or
  project dependency files.
- Selecting non-Fedora Python versions or third-party repositories.
- Providing a `python` unversioned command.
- Installing Python development headers, debug builds, tkinter, test packages,
  documentation, or alternative Python interpreters.

## 3. Package source and trusted command paths

Atlas uses Fedora's official package repositories:

```
python3
python3-pip
```

Fedora's package index describes `python3` as the package providing the
`python3` executable for Python 3, and describes `python3-pip` as the Python 3
package-management tool. These are the supported package names for the module.
Atlas does not add repositories or import new RPM keys for Python.

The trusted runtime probes use fixed system paths:

```
/usr/bin/python3
/usr/bin/pip3
```

Atlas must not use `PATH` to select a Python runtime for managed verification.
That avoids accidental interaction with virtual environments, pyenv shims, Conda,
project-local wrappers, or user shell aliases. A user may use those tools freely;
they are outside this module's ownership boundary.

The trusted probe contract is:

1. `/usr/bin/python3` exists and is executable.
2. `rpm -qf /usr/bin/python3` resolves to a `python3-*` package.
3. `/usr/bin/python3 --version` succeeds and reports Python 3.
4. `/usr/bin/pip3` exists and is executable.
5. `rpm -qf /usr/bin/pip3` resolves to a `python3-pip-*` package.
6. `/usr/bin/pip3 --version` succeeds.

Atlas does not run `pip install`, `pip list`, `pip freeze`, `ensurepip`, or any
command that reads or mutates user package state.

## 4. Ownership and state model

### 4.1 Atlas-owned state

| State | Atlas owns it when | Lifecycle |
|---|---|---|
| Required package intent | an Atlas marker records Fedora package source and package set | install/verify; never uninstall in `remove` |
| Installation marker | always | create atomically, validate strictly, remove narrowly |

Atlas does not own Fedora's package database, system package files, Python's
standard library content, or `/usr/bin` paths themselves. It owns only the intent
that Fedora's packages satisfy this module.

### 4.2 User-owned and external state

Atlas never owns:

- virtual environments;
- user packages in global, user, project, or virtualenv locations;
- `pip.conf`, `PIP_*` environment variables, indexes, credentials, or caches;
- `pipx`, Poetry, uv, pyenv, Conda, asdf, direnv, tox, nox, or project tooling;
- project dependency manifests and lockfiles;
- application source code or runtime data.

The presence of any of those tools does not make Python broken. Atlas ignores
them unless a future RFC defines a separate module.

### 4.3 Marker state

The marker path is:

```
$ATLAS_STATE_DIR/installed/development-python
```

The parent directory is mode `700`; the marker is mode `600` and written
atomically. The marker records:

```
schema=1
state=installing|installed
package_source=fedora
packages=python3 python3-pip
```

Malformed, unreadable, mode-insecure, or inconsistent markers are broken
managed state and fail verification. An `installing` marker means Atlas started
but did not complete the installation; `install` may reconcile it, but `verify`
must fail until the marker is promoted to `installed`.

There is no `detached` state. `remove` deletes only the marker and leaves Fedora
packages installed. A later install can re-enroll by repeating the same DNF and
verification flow.

## 5. Lifecycle contract

### 5.1 `check`

`check` returns `0` only when the marker is valid, state is `installed`, and the
trusted runtime probes pass. A no-marker machine returns non-zero so `install`
can enroll the runtime. An `installing` marker returns non-zero so `install`
repairs and promotes only after validation.

### 5.2 `install`

`install` is idempotent and follows this order:

1. Require Fedora before any mutation.
2. Validate any existing marker.
3. Refuse unsafe system-path conflicts before mutation:
   - `/usr/bin/python3` exists but is not executable;
   - `/usr/bin/python3` exists and is not RPM-owned by `python3-*`;
   - `/usr/bin/pip3` exists but is not executable;
   - `/usr/bin/pip3` exists and is not RPM-owned by `python3-pip-*`.
4. Write an `installing` marker atomically.
5. Run `os::dnf_install python3 python3-pip`.
6. Validate package presence and trusted command probes.
7. Promote the marker atomically to `installed`.

The preflight deliberately does not inspect `python3` or `pip3` on `PATH`.
User-selected runtimes are outside the module. The preflight only protects the
fixed system paths Atlas will later trust.

### 5.3 `verify` and `doctor`

The current runner dispatches `atlas doctor` to `module::verify`; RFC-0006
preserves that contract and does not add a new engine hook.

With no marker, `verify` returns `0`. It logs whether system Python appears
absent or present but unmanaged.

With a valid `installed` marker, `verify` fails only when Atlas-managed expected
state is broken: package set missing, trusted command path missing, wrong RPM
ownership, non-runnable Python, non-runnable pip, or invalid marker.

With an `installing` marker, `verify` fails and tells the user to rerun install
to reconcile. This keeps `verify` from reporting a partially completed runtime
as healthy.

Doctor should report:

- marker state;
- Fedora package intent;
- `/usr/bin/python3` availability and version;
- `/usr/bin/pip3` availability and version;
- unmanaged/no-marker state;
- common misconfigurations such as replaced system binaries.

Doctor recommends actions; it does not repair.

### 5.4 `update`

`update` is a documented no-op. Python package currency is Fedora's update
policy and may affect system tooling and projects. Atlas does not run package
upgrades or change interpreter versions implicitly.

### 5.5 `remove` hook

The platform still has no `atlas remove` verb, but the module hook is specified
for future use.

`remove` deletes only Atlas's marker. It never uninstalls `python3` or
`python3-pip`, because those packages are shared OS/runtime dependencies and may
be required by Fedora or user workflows. Repeated `remove` is a no-op.

If the marker is malformed or insecure, `remove` refuses rather than guessing
which state to delete.

### 5.6 `backup` and `restore`

`backup` and `restore` are documented no-op hooks returning `0`.

The managed runtime is reconstructable from Fedora packages and the marker is
reconstructable by reinstalling. User packages, virtual environments, caches,
and project dependency state are explicitly user-owned and must not be backed up
or restored by this module.

## 6. Security considerations

Python execution can load arbitrary project code and user packages, so Atlas
keeps probes minimal and non-mutating:

- fixed `/usr/bin` paths only;
- no `PATH`-selected runtime;
- no `python -m pip install`;
- no `ensurepip`;
- no reading package indexes or credentials;
- no pip configuration writes;
- no virtualenv activation or inspection;
- no global user package changes.

RPM ownership checks protect against trusting a replaced `/usr/bin/python3` or
`/usr/bin/pip3` as Atlas-managed runtime. Atlas does not add external package
repositories or weaken Fedora's package trust chain.

## 7. Dependency model and future extensibility

`development/python` has no Atlas module dependencies. It is a foundational
runtime for future modules, especially `development/uv`.

Future modules should depend on `development/python` only when they actually need
the managed Fedora runtime. The intended boundaries are:

- `development/uv` may depend on this module but owns uv installation and uv
  configuration separately.
- Node.js/pnpm must not depend on Python unless their implementation requires it.
- Claude Code and Codex should depend on the runtime modules they actually need,
  not on Python by convention.

Additional Python capabilities require separate RFCs or modules:

- `python3-devel` for native extension builds;
- `pipx` for isolated Python applications;
- Poetry or uv for dependency/project management;
- pyenv/Conda for alternate interpreters.

## 8. Testing strategy

Pure-Bash unit tests mock DNF and RPM queries and override private helper
functions for system paths. They must cover:

- no-marker verify with Python absent;
- no-marker verify with unmanaged Python present;
- install writes `installing` before DNF and promotes only after validation;
- installed marker verifies healthy package/command state;
- `installing` marker fails verify and is repairable by install;
- malformed marker, insecure marker mode, unknown keys, missing fields;
- missing package, missing command, non-executable command;
- wrong RPM owner for `/usr/bin/python3`;
- wrong RPM owner for `/usr/bin/pip3`;
- DNF failure leaves marker in `installing`;
- non-Fedora install refusal before mutation;
- repeated install idempotency;
- repeated verify idempotency;
- doctor through runner uses verify contract;
- status reports not installed before marker and installed after marker;
- update/backup/restore no-op hooks;
- remove deletes only marker and never invokes DNF;
- remove is idempotent;
- hostile `PATH` or virtualenv-like `python3` does not affect trusted probes.

Integration/Fedora acceptance must run:

```
atlas install development/python
/usr/bin/python3 --version
/usr/bin/pip3 --version
atlas verify development/python
atlas doctor development/python
atlas install development/python
```

The repeated install must be idempotent.

## 9. Architecture review

The architecture review challenged the areas most likely to leak ownership:

1. **Pre-existing Fedora Python.** Refusing it would make a normal Fedora
   workstation unmanageable. The RFC therefore allows install to enroll Fedora's
   package intent while still refusing to infer ownership during verify.
2. **PATH-selected Python.** Using `command -v python3` would accidentally verify
   pyenv, Conda, or virtualenv shims. The RFC requires fixed `/usr/bin` probes.
3. **pip ownership.** Pip is included only as Fedora's `python3-pip` package and
   only as a command probe. Python package management is out of scope.
4. **Remove behavior.** Uninstalling Python is unsafe on Fedora and could break
   the OS or user tooling. Remove is marker-only.
5. **uv interaction.** Python remains runtime-only. uv owns its own installer,
   configuration, cache policy, and project behavior in a future RFC.
6. **Docker interaction.** There is none beyond sharing the marker-based package
   module pattern. Python must not inspect containers, Docker images, or Compose
   projects.
7. **Future runtime modules.** The pattern is intentionally smaller than Docker:
   strict marker, fixed trusted command paths, RPM ownership, no user package
   state, no repo/key management unless the runtime truly needs it.

No engine or module-contract change is required.

## 10. Implementation roadmap

1. Add the module skeleton and README.
2. Add failing regression tests for the complete §8 matrix.
3. Implement strict marker parsing/writing.
4. Implement fixed-path package/command probes.
5. Implement lifecycle hooks.
6. Update module inventory tests, RFC index, docs, and changelog.
7. Run syntax checks, `git diff --check`, full suite, implementation review, and
   Fedora acceptance.

## 11. Sources

- [Fedora package: python3](https://packages.fedoraproject.org/pkgs/python3.14/python3/)
- [Fedora package: python3-pip](https://packages.fedoraproject.org/pkgs/python-pip/python3-pip/)
