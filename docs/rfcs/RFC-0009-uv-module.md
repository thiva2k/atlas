# RFC-0009: uv Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-12 |
| **Phase / order** | Phase 2 — Python tooling · module 6 of 16 |
| **Depends on** | `development/python` |
| **Establishes** | The lifecycle pattern for language-adjacent package-manager CLIs |

---

## 1. Summary

Implement `modules/development/uv` as Atlas's lifecycle manager for the Fedora
packaged `uv` command. Atlas installs and verifies the Fedora `uv` package,
records ownership with a strict marker, and depends on `development/python` so a
fresh workstation has the Python runtime foundation before uv is enrolled.

uv can manage projects, environments, tools, package indexes, caches, and Python
versions. Atlas does not manage any of that state in this module. The module
only makes the uv CLI available and verifies the fixed system command that Atlas
installed.

The central rule is:

> Atlas owns uv availability through Fedora packaging, never the Python projects
> or environments uv may later create for the user.

## 2. Goals and non-goals

**Goals**

- Install Fedora's `uv` package.
- Verify the fixed system command at `/usr/bin/uv`.
- Require RPM ownership by the Fedora `uv` package for managed verification.
- Record Atlas ownership through a strict marker.
- Depend on `development/python`.
- Provide idempotent `check`, `install`, `verify`, `update`, `remove`,
  `backup`, and `restore` hooks.

**Non-goals**

- Managing uv caches.
- Managing project virtual environments.
- Managing project dependencies, `pyproject.toml`, `uv.lock`, or workspace
  files.
- Managing Python versions installed by uv.
- Managing uv tools installed by the user.
- Managing package indexes, credentials, TLS settings, or uv configuration.
- Installing uv through curl-piped standalone installers, PyPI, pipx, Cargo, or
  GitHub release binaries.
- Enabling shell completions or editing shell startup files.

## 3. Package source and trusted command path

Atlas uses Fedora's official package repositories:

```
uv
```

Fedora's package index describes `uv` as a fast Python package and project
manager written in Rust. uv's official installation documentation supports
installation through a package manager and documents a standalone installer that
can modify shell profiles unless explicitly disabled. Atlas chooses Fedora's
package because it preserves Fedora's RPM trust chain, avoids curl-piped runtime
installation, avoids shell profile mutation, and keeps updates under Fedora's
package-management policy.

The trusted probe uses a fixed system path:

```
/usr/bin/uv
```

Atlas must not use `PATH` to select uv for managed verification. User-installed
uv binaries in `~/.local/bin`, pipx, Cargo, project tool directories, or shell
shims are valid user-owned state. They do not become Atlas-managed unless the
Atlas marker exists and the fixed Fedora path satisfies the managed contract.

The trusted probe contract is:

1. `/usr/bin/uv` exists and is executable.
2. `rpm -qf /usr/bin/uv` resolves to a `uv-*` package.
3. `/usr/bin/uv --version` succeeds and reports `uv ...`.

Atlas does not run `uv sync`, `uv tool`, `uv python install`, `uv cache`, `uv
pip`, or any command that reads or mutates user project or package state.

## 4. Ownership and state model

### 4.1 Atlas-owned state

| State | Atlas owns it when | Lifecycle |
|---|---|---|
| Required package intent | an Atlas marker records Fedora package source and package set | install/verify; never uninstall in `remove` |
| Installation marker | always | create atomically, validate strictly, remove narrowly |

Atlas does not own Fedora's package database, package files, uv's upstream
project behavior, or `/usr/bin` itself. It owns only the intent that Fedora's
`uv` package satisfies this module.

### 4.2 User-owned and external state

Atlas never owns:

- uv caches;
- uv-created virtual environments;
- `.venv`, `uv.lock`, `pyproject.toml`, workspace files, or project dependency
  state;
- uv-managed Python installations;
- uv-installed tools;
- package indexes, credentials, TLS settings, or authentication state;
- user uv configuration;
- shell completions or shell startup files.

The presence of those resources does not make uv broken. Atlas ignores them
unless a future RFC defines a separate module.

### 4.3 Marker state

The marker path is:

```
$ATLAS_STATE_DIR/installed/development-uv
```

The parent directory is mode `700`; the marker is mode `600` and written
atomically. The marker records:

```
schema=1
state=installing|installed
package_source=fedora
packages=uv
depends=development/python
```

Malformed, unreadable, mode-insecure, or inconsistent markers are broken
managed state and fail verification. An `installing` marker means Atlas started
but did not complete installation; `install` may reconcile it, but `verify` must
fail until the marker is promoted to `installed`.

There is no `detached` state. `remove` deletes only the marker and leaves the
Fedora package installed. A later install can re-enroll by repeating the same
DNF and verification flow.

## 5. Lifecycle contract

### 5.1 `check`

`check` returns `0` only when the marker is valid, state is `installed`, and the
trusted uv probe passes. A no-marker machine returns non-zero so `install` can
enroll the CLI. An `installing` marker returns non-zero so `install` repairs and
promotes only after validation.

### 5.2 `install`

`install` is idempotent and follows this order:

1. Require Fedora before any mutation.
2. Validate any existing marker.
3. Refuse unsafe fixed-path conflicts before mutation:
   - `/usr/bin/uv` exists but is not executable;
   - `/usr/bin/uv` exists and is not RPM-owned by `uv-*`.
4. Write an `installing` marker atomically.
5. Run `os::dnf_install uv`.
6. Validate package presence and trusted command probe.
7. Promote the marker atomically to `installed`.

The preflight deliberately does not inspect `uv` on `PATH`. User-selected uv
installations are outside this module.

### 5.3 `verify` and `doctor`

The current runner dispatches `atlasctl doctor` to `module::verify`; RFC-0009
preserves that contract and does not add a new engine hook.

With no marker, `verify` returns `0`. It logs whether system uv appears absent
or present but unmanaged.

With a valid `installed` marker, `verify` fails only when Atlas-managed expected
state is broken: package missing, trusted command path missing, wrong RPM
ownership, non-runnable uv, or invalid marker.

With an `installing` marker, `verify` fails and tells the user to rerun install
to reconcile.

Doctor should report:

- marker state;
- Fedora package intent;
- `/usr/bin/uv` availability and version;
- unmanaged/no-marker state;
- common misconfigurations such as a replaced system binary.

Doctor recommends actions; it does not repair.

### 5.4 `update`

`update` is a documented no-op. uv package currency is Fedora's update policy.
Atlas does not run `uv self update`, because Fedora-packaged uv is managed by
DNF and uv documents self-updates as installer-specific behavior for standalone
installations.

### 5.5 `remove` hook

`remove` deletes only Atlas's marker. It never uninstalls `uv`, because uv may
be used by user workflows after Atlas detaches. Repeated `remove` is a no-op.

If the marker is malformed or insecure, `remove` refuses rather than guessing
which state to delete.

### 5.6 `backup` and `restore`

`backup` and `restore` are documented no-op hooks returning `0`.

The managed CLI is reconstructable from Fedora packages and the marker is
reconstructable by reinstalling. uv caches, environments, tools, and project
state are explicitly user-owned and must not be backed up or restored by this
module.

## 6. Security considerations

uv can execute project build backends, resolve dependencies from indexes, manage
tools, and install Python versions. Atlas keeps probes minimal and non-mutating:

- fixed `/usr/bin/uv` path only;
- no `PATH`-selected uv;
- no standalone curl installer;
- no `uv self update`;
- no shell completion writes;
- no package index access;
- no credential reads;
- no cache cleanup;
- no project or virtualenv inspection.

RPM ownership checks protect against trusting a replaced `/usr/bin/uv` as the
Atlas-managed CLI. Atlas does not add repositories or weaken Fedora's package
trust chain.

## 7. Dependency model and future extensibility

`development/uv` depends on `development/python` because Atlas's workstation
contract treats Python as the foundation for modern Python tooling. uv itself is
packaged as a Rust binary, but the dependency keeps workstation lifecycle order
predictable and ensures users have a managed system Python runtime before using
uv.

Future modules should not assume ownership of uv-created state unless a separate
RFC defines that boundary. Potential future modules include:

- Python project defaults;
- organization package-index policy;
- uv tool provisioning;
- shell completion integration.

Those are intentionally outside RFC-0009.

## 8. Testing strategy

Pure-Bash unit tests mock DNF and RPM queries and override private helper
functions for system paths. They must cover:

- no-marker verify with uv absent;
- no-marker verify with unmanaged uv present;
- module dependency on `development/python`;
- install writes `installing` before DNF and promotes only after validation;
- installed marker verifies healthy package/command state;
- `installing` marker fails verify and is repairable by install;
- malformed marker, insecure marker mode, unknown keys, missing fields;
- missing package, missing command, non-executable command;
- wrong RPM owner for `/usr/bin/uv`;
- DNF failure leaves marker in `installing`;
- non-Fedora install refusal before mutation;
- repeated install idempotency;
- repeated verify idempotency;
- doctor through runner uses verify contract;
- status reports not installed before marker and installed after marker;
- update/backup/restore no-op hooks;
- remove deletes only marker and never invokes DNF;
- remove is idempotent;
- hostile `PATH` does not affect trusted probes;
- uv project/cache/config environment does not affect trusted probes.

Integration/Fedora acceptance must run:

```
atlasctl install development/uv
uv --version
atlasctl verify development/uv
atlasctl doctor development/uv
atlasctl status development/uv
atlasctl install development/uv
```

The repeated install must be idempotent.

## 9. Architecture review

The architecture review challenged the areas most likely to leak ownership:

1. **Installer choice.** The standalone installer is convenient but downloads and
   executes code at runtime and may modify shell profiles. Fedora packaging is
   slower to adopt releases but provides deterministic RPM ownership and avoids
   shell mutation.
2. **Project state.** uv's core value is project and environment management, but
   Atlas cannot safely own arbitrary project files or virtual environments. This
   RFC limits Atlas to CLI availability.
3. **uv-managed Python versions.** uv can install Python interpreters, but Atlas
   already owns the Fedora system runtime through `development/python`. uv-managed
   interpreters remain user-owned unless a future RFC says otherwise.
4. **Shell integration.** Completion generation belongs to a shell/completion
   contract, not the uv module. This avoids hidden edits to user shell files.
5. **Update behavior.** `uv self update` is for standalone installs. Fedora
   package currency remains Fedora's responsibility.
6. **Future tooling.** uv tools, package-index policy, and project defaults are
   separate concerns. Keeping this module small makes it safe as a foundation.

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

- [Fedora package: uv](https://packages.fedoraproject.org/pkgs/uv/uv/)
- [uv installation documentation](https://docs.astral.sh/uv/getting-started/installation/)
- [uv projects documentation](https://docs.astral.sh/uv/concepts/projects/)
