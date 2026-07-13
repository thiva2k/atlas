# RFC-0015: pnpm Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-12 |
| **Phase / order** | Phase 2 — JavaScript tooling · follows `development/node` |
| **Depends on** | `development/node` |
| **Establishes** | The lifecycle pattern for language package-manager CLIs that depend on a managed runtime |

---

## 1. Summary

Implement `modules/development/pnpm` as Atlas's lifecycle manager for the
Fedora-packaged `pnpm` command. Atlas installs and verifies Fedora's `pnpm`
package, records ownership with a strict marker, and depends on
`development/node` so the JavaScript runtime foundation is present before pnpm
is enrolled.

pnpm is a JavaScript package manager. It creates and mutates project dependency
trees, lockfiles, caches, stores, and package-manager configuration. Atlas does
not manage any of that state in this module. This module only makes the pnpm CLI
available and verifies the fixed system command that Atlas installed.

The central rule is:

> Atlas owns pnpm availability through Fedora packaging, never JavaScript project
> dependency state or pnpm's user/project configuration.

## 2. Goals and non-goals

**Goals**

- Install Fedora's `pnpm` package.
- Verify the fixed system command at `/usr/bin/pnpm`.
- Require RPM ownership by Fedora's `pnpm` package for managed verification.
- Record Atlas ownership through a strict marker.
- Depend on `development/node`.
- Provide idempotent `check`, `install`, `verify`, `update`, `remove`,
  `backup`, and `restore` hooks.

**Non-goals**

- Managing `node_modules`.
- Managing `pnpm-lock.yaml`, `package.json`, workspaces, or scripts.
- Managing the pnpm content-addressable store.
- Managing pnpm caches.
- Managing global pnpm packages.
- Managing pnpm configuration, registries, credentials, TLS settings, or npmrc
  files.
- Running `pnpm install`, `pnpm update`, `pnpm store`, `pnpm setup`, or
  `pnpm self-update`.
- Enabling Corepack or using Corepack to install pnpm.
- Installing pnpm through npm, curl-piped standalone scripts, upstream tarballs,
  or GitHub release binaries.
- Editing shell startup files or enabling shell completions.

## 3. Package source and trusted command path

Atlas uses Fedora's official package repositories:

```
pnpm
```

Fedora packages `pnpm` as a subpackage of `nodejs-pnpm` and describes it as a
fast, disk-space-efficient package manager for NodeJS. On the Fedora 44
workstation used for Atlas validation, DNF exposes `pnpm` from Fedora/updates.

The trusted probe uses a fixed system path:

```
/usr/bin/pnpm
```

Atlas must not use `PATH` to select pnpm for managed verification.
User-installed pnpm binaries in `~/.local/bin`, npm global prefixes, Corepack
shims, project tool directories, or shell shims are valid user-owned state. They
do not become Atlas-managed unless the Atlas marker exists and the fixed Fedora
path satisfies the managed contract.

The trusted probe contract is:

1. `/usr/bin/pnpm` exists and is executable.
2. `rpm -qf /usr/bin/pnpm` resolves to a `pnpm-*` package.
3. `/usr/bin/pnpm --version` succeeds and reports a version.

Atlas does not run project-affecting pnpm commands or commands that inspect
registries, stores, caches, credentials, or dependency trees.

## 4. Ownership and state model

### 4.1 Atlas-owned state

| State | Atlas owns it when | Lifecycle |
|---|---|---|
| Required package intent | an Atlas marker records Fedora package source and package set | install/verify; never uninstall in `remove` |
| Installation marker | always | create atomically, validate strictly, remove narrowly |

Atlas does not own Fedora's package database, package files, pnpm's store,
pnpm's cache, npm configuration, or `/usr/bin` itself. It owns only the intent
that Fedora's `pnpm` package satisfies this module.

### 4.2 User-owned and external state

Atlas never owns:

- `node_modules`;
- `pnpm-lock.yaml`, `package.json`, workspaces, scripts, or project dependency
  state;
- the pnpm content-addressable store;
- pnpm caches;
- global pnpm packages;
- pnpm, npm, or registry configuration;
- npm tokens, registry credentials, TLS settings, or authentication state;
- Corepack state and shims;
- shell completions or shell startup files.

The presence of those resources does not make pnpm broken. Atlas ignores them
unless a future RFC defines a separate module.

### 4.3 Marker state

The marker path is:

```
$ATLAS_STATE_DIR/installed/development-pnpm
```

The parent directory is mode `700`; the marker is mode `600` and written
atomically. The marker records:

```
schema=1
state=installing|installed
package_source=fedora
packages=pnpm
depends=development/node
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
trusted pnpm probe passes. A no-marker machine returns non-zero so `install` can
enroll the CLI. An `installing` marker returns non-zero so `install` repairs and
promotes only after validation.

### 5.2 `install`

`install` is idempotent and follows this order:

1. Require Fedora before any mutation.
2. Validate any existing marker.
3. Refuse unsafe fixed-path conflicts before mutation:
   - `/usr/bin/pnpm` exists but is not executable;
   - `/usr/bin/pnpm` exists and is not RPM-owned by `pnpm-*`.
4. Write an `installing` marker atomically.
5. Run `os::dnf_install pnpm`.
6. Validate package presence and trusted command probe.
7. Promote the marker atomically to `installed`.

The preflight deliberately does not inspect `pnpm` on `PATH`. User-selected pnpm
installations are outside this module.

### 5.3 `verify` and `doctor`

The current runner dispatches `atlasctl doctor` to `module::verify`; RFC-0015
preserves that contract and does not add a new engine hook.

With no marker, `verify` returns `0`. It logs whether system pnpm appears absent
or present but unmanaged.

With a valid `installed` marker, `verify` fails only when Atlas-managed expected
state is broken: package missing, trusted command path missing, wrong RPM
ownership, non-runnable pnpm, unexpected version output, or invalid marker.

With an `installing` marker, `verify` fails and tells the user to rerun install
to reconcile.

Doctor should report:

- marker state;
- Fedora package intent;
- `/usr/bin/pnpm` availability and version;
- unmanaged/no-marker state;
- common misconfigurations such as a replaced system binary or Corepack shim at
  `/usr/bin/pnpm`.

Doctor recommends actions; it does not repair.

### 5.4 `update`

`update` is a documented no-op. pnpm package currency is Fedora's update policy.
Atlas does not run `pnpm self-update`, because Fedora-packaged pnpm is managed
by DNF.

### 5.5 `remove` hook

`remove` deletes only Atlas's marker. It never uninstalls `pnpm`, because pnpm
may be used by user workflows after Atlas detaches. Repeated `remove` is a
no-op.

If the marker is malformed or insecure, `remove` refuses rather than guessing
which state to delete.

### 5.6 `backup` and `restore`

`backup` and `restore` are documented no-op hooks returning `0`.

The managed CLI is reconstructable from Fedora packages and the marker is
reconstructable by reinstalling. pnpm stores, caches, global packages,
configuration, credentials, lockfiles, and project dependency state are
explicitly user-owned and must not be backed up or restored by this module.

## 6. Security considerations

pnpm can execute project lifecycle scripts, fetch packages from registries, and
mutate dependency state. Atlas keeps probes minimal and non-mutating:

- fixed `/usr/bin/pnpm` path only;
- no `PATH`-selected runtime;
- no `pnpm install`, `pnpm update`, `pnpm store`, `pnpm setup`, or
  `pnpm self-update`;
- no Corepack enablement;
- no registry, npmrc, credential, cache, or store reads;
- no shell startup edits;
- RPM ownership validation for the trusted command.

Atlas chooses Fedora packaging over npm/global installers and standalone scripts
because Fedora preserves RPM provenance, avoids shell profile mutation, avoids
downloading executable installers at runtime, and keeps updates under the
system package manager.

## 7. Dependency and interaction model

`development/pnpm` depends on `development/node`. Node.js provides the managed
runtime foundation; pnpm provides a separate package-manager CLI. This split is
intentional:

- `development/node` never becomes a package-manager module.
- `development/pnpm` never becomes a runtime module.
- npm remains bundled with the Node module only because Fedora packages it with
  the Node.js runtime family.
- Corepack remains user-owned unless a future RFC explicitly defines otherwise.

The module does not depend on `development/uv`, Docker, Fish, Starship, Claude,
or Codex.

## 8. Testing and validation matrix

Unit tests must cover:

- no-marker verify success when pnpm is absent;
- no-marker verify success when pnpm is present but unmanaged;
- `check` failure before marker;
- declared dependency on `development/node`;
- malformed, insecure, unknown-key, and installing markers;
- missing package;
- missing, non-executable, wrong-owner, and non-runnable `/usr/bin/pnpm`;
- exact DNF package set;
- marker written as `installing` before DNF;
- marker promoted only after validation;
- DNF failure leaves `installing`;
- non-Fedora install refusal before mutation;
- fixed-path preflight refusal before mutation;
- hostile `PATH` shims ignored;
- hostile pnpm/npm/node/Corepack environment ignored for probes;
- repeated install and repeated verify idempotency;
- `update`, `backup`, and `restore` no-ops;
- `remove` deletes only marker and never invokes DNF;
- runner `status` and `doctor` behavior.

Real Fedora validation must include:

```
atlasctl install development/pnpm
pnpm --version
atlasctl verify development/pnpm
atlasctl doctor development/pnpm
atlasctl status development/pnpm
atlasctl install development/pnpm
```

The second install must perform no work.

## 9. Architecture review

- **Ownership boundary:** marker-based package intent only; all pnpm project,
  store, cache, registry, and configuration state remains user-owned.
- **Security:** fixed path, RPM ownership, Fedora packaging, and no
  project-affecting pnpm commands.
- **Idempotency:** `check` requires both marker and healthy trusted path;
  `install` can repair an interrupted marker; repeated `remove` is safe.
- **Future extensibility:** future modules may manage Corepack or package-manager
  policy, but this module deliberately does not create that abstraction.
- **Interaction with Node.js:** dependency is explicit and one-way; pnpm consumes
  the Node runtime contract without reaching into Node internals.

No engine or runner changes are required.
