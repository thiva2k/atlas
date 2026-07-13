# RFC-0013: Node.js Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-12 |
| **Phase / order** | Phase 2 — JavaScript runtime · module 7 of 16 |
| **Depends on** | Nothing — `MODULE_DEPENDS=()` |
| **Establishes** | The lifecycle pattern for versioned Fedora language runtime packages |

---

## 1. Summary

Implement `modules/development/node` as Atlas's lifecycle manager for the
Fedora-packaged Node.js LTS runtime. On Fedora 44, Atlas targets Node.js 24
because upstream Node.js lists 24.x as Active LTS and Fedora packages it as the
versioned `nodejs24` family.

Atlas installs and verifies Fedora's Node.js 24 runtime, the unversioned
`/usr/bin/node` symlink package, Fedora's Node.js 24 npm package, and the
unversioned `/usr/bin/npm` symlink package. Atlas records ownership with a strict
marker and never manages JavaScript projects, global packages, npm credentials,
or alternative runtimes.

The central rule is:

> Atlas owns Node.js runtime availability through Fedora packages, never npm
> package state or JavaScript project state.

## 2. Goals and non-goals

**Goals**

- Install Fedora's `nodejs24` package.
- Install Fedora's `nodejs24-bin` package for `/usr/bin/node`.
- Install Fedora's `nodejs24-npm` package.
- Install Fedora's `nodejs24-npm-bin` package for `/usr/bin/npm`.
- Verify fixed system commands at `/usr/bin/node` and `/usr/bin/npm`.
- Require RPM ownership by the expected Fedora package families.
- Record Atlas ownership through a strict marker.
- Provide idempotent `check`, `install`, `verify`, `update`, `remove`,
  `backup`, and `restore` hooks.

**Non-goals**

- Managing pnpm, bun, yarn, corepack, nvm, fnm, Volta, asdf, or Deno.
- Managing global npm packages.
- Managing npm configuration, registries, tokens, credentials, or cache.
- Managing project dependencies, `node_modules`, `package.json`,
  `package-lock.json`, workspaces, or scripts.
- Installing Node.js from NodeSource, tarballs, npm, nvm, fnm, Volta, or upstream
  release archives.
- Enabling shell completions or editing shell startup files.
- Installing development headers, docs, full ICU data, or alternate Node majors.

## 3. Package source and trusted command paths

Atlas uses Fedora's official package repositories:

```
nodejs24
nodejs24-bin
nodejs24-npm
nodejs24-npm-bin
```

Fedora describes `nodejs24` as the JavaScript runtime, `nodejs24-bin` as the
unversioned runtime symlink package, `nodejs24-npm` as Node.js Package Manager,
and `nodejs24-npm-bin` as the unversioned npm symlink package. The upstream
Node.js Release Working Group lists 24.x as Active LTS, codenamed Krypton, with
end-of-life on 2028-04-30.

The trusted runtime probes use fixed system paths:

```
/usr/bin/node
/usr/bin/npm
```

Atlas must not use `PATH` to select Node.js or npm for managed verification.
User-installed Node.js from nvm, fnm, Volta, asdf, project shims, or local
wrappers is valid user-owned state. It does not become Atlas-managed unless the
Atlas marker exists and the fixed Fedora paths satisfy the managed contract.

The trusted probe contract is:

1. `/usr/bin/node` exists and is executable.
2. `rpm -qf /usr/bin/node` resolves to a `nodejs24-bin-*` package.
3. `/usr/bin/node --version` succeeds and reports `v24.*`.
4. `/usr/bin/npm` exists and is executable.
5. `rpm -qf /usr/bin/npm` resolves to a `nodejs24-npm-bin-*` package.
6. `/usr/bin/npm --version` succeeds.

Atlas does not run `npm install`, `npm list`, `npm config`, `npm audit`,
`corepack`, `npx`, or any command that reads or mutates user package/project
state.

## 4. Ownership and state model

### 4.1 Atlas-owned state

| State | Atlas owns it when | Lifecycle |
|---|---|---|
| Required package intent | an Atlas marker records Fedora package source and package set | install/verify; never uninstall in `remove` |
| Installation marker | always | create atomically, validate strictly, remove narrowly |

Atlas does not own Fedora's package database, package files, npm's global store,
or `/usr/bin` itself. It owns only the intent that Fedora's Node.js 24 package
family satisfies this module.

### 4.2 User-owned and external state

Atlas never owns:

- pnpm, bun, yarn, corepack, nvm, fnm, Volta, asdf, Deno, or alternate runtimes;
- global npm packages;
- npm cache, config, registries, tokens, or credentials;
- `node_modules`, `package.json`, `package-lock.json`, workspaces, or scripts;
- user shell startup files and completions.

The presence of those resources does not make Node.js broken. Atlas ignores them
unless a future RFC defines a separate module.

### 4.3 Marker state

The marker path is:

```
$ATLAS_STATE_DIR/installed/development-node
```

The parent directory is mode `700`; the marker is mode `600` and written
atomically. The marker records:

```
schema=1
state=installing|installed
package_source=fedora
node_major=24
packages=nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin
```

Malformed, unreadable, mode-insecure, or inconsistent markers are broken
managed state and fail verification. An `installing` marker means Atlas started
but did not complete installation; `install` may reconcile it, but `verify` must
fail until the marker is promoted to `installed`.

There is no `detached` state. `remove` deletes only the marker and leaves Fedora
packages installed. A later install can re-enroll by repeating the same DNF and
verification flow.

## 5. Lifecycle contract

### 5.1 `check`

`check` returns `0` only when the marker is valid, state is `installed`, and the
trusted Node.js/npm probes pass. A no-marker machine returns non-zero so
`install` can enroll the runtime.

### 5.2 `install`

`install` is idempotent and follows this order:

1. Require Fedora before any mutation.
2. Validate any existing marker.
3. Refuse unsafe fixed-path conflicts before mutation:
   - `/usr/bin/node` exists but is not executable;
   - `/usr/bin/node` exists and is not RPM-owned by `nodejs24-bin-*`;
   - `/usr/bin/npm` exists but is not executable;
   - `/usr/bin/npm` exists and is not RPM-owned by `nodejs24-npm-bin-*`.
4. Write an `installing` marker atomically.
5. Run `os::dnf_install nodejs24 nodejs24-bin nodejs24-npm nodejs24-npm-bin`.
6. Validate package presence and trusted command probes.
7. Promote the marker atomically to `installed`.

The preflight deliberately does not inspect `node` or `npm` on `PATH`.
User-selected runtimes and package managers are outside this module.

### 5.3 `verify` and `doctor`

The current runner dispatches `atlasctl doctor` to `module::verify`; RFC-0013
preserves that contract and does not add a new engine hook.

With no marker, `verify` returns `0`. It logs whether system Node.js appears
absent or present but unmanaged.

With a valid `installed` marker, `verify` fails only when Atlas-managed expected
state is broken: package set missing, trusted command path missing, wrong RPM
ownership, non-runnable Node.js, non-runnable npm, wrong Node major, or invalid
marker.

With an `installing` marker, `verify` fails and tells the user to rerun install
to reconcile.

Doctor should report:

- marker state;
- Fedora package intent;
- `/usr/bin/node` availability and version;
- `/usr/bin/npm` availability and version;
- unmanaged/no-marker state;
- common misconfigurations such as replaced system binaries.

Doctor recommends actions; it does not repair.

### 5.4 `update`

`update` is a documented no-op. Node.js package currency is Fedora's update
policy. Atlas does not run npm self-updates or switch Node major versions
implicitly.

### 5.5 `remove` hook

`remove` deletes only Atlas's marker. It never uninstalls Node.js or npm, because
they may be used by user workflows after Atlas detaches. Repeated `remove` is a
no-op.

If the marker is malformed or insecure, `remove` refuses rather than guessing
which state to delete.

### 5.6 `backup` and `restore`

`backup` and `restore` are documented no-op hooks returning `0`.

The managed runtime is reconstructable from Fedora packages and the marker is
reconstructable by reinstalling. npm config, credentials, caches, global
packages, and project dependency state are explicitly user-owned and must not be
backed up or restored by this module.

## 6. Security considerations

Node.js and npm can execute arbitrary project scripts and fetch code from package
registries. Atlas keeps probes minimal and non-mutating:

- fixed `/usr/bin` paths only;
- no `PATH`-selected runtime;
- no `npm install`, `npm list`, `npm audit`, or `npm config`;
- no `corepack`, `npx`, pnpm, or bun invocation;
- no registry or credential reads;
- no cache cleanup;
- no project or global package inspection.

RPM ownership checks protect against trusting replaced `/usr/bin/node` or
`/usr/bin/npm` as Atlas-managed runtime. Atlas does not add repositories or
weaken Fedora's package trust chain.

## 7. Dependency model and future extensibility

`development/node` has no Atlas module dependencies. It exists to provide a
JavaScript runtime for developer tooling. pnpm is intentionally out of scope and
requires its own RFC/module if Atlas later manages it.

Future modules may depend on `development/node` only when they actually require
Node.js. Claude Code and Codex should depend on the runtimes they need, not on
Node.js by convention.

The Node LTS major is encoded in the marker. Moving Atlas to a newer LTS major
is a future architectural decision and should be handled as an RFC erratum or
new RFC because it changes package intent.

## 8. Testing strategy

Pure-Bash unit tests mock DNF and RPM queries and override private helper
functions for system paths. They must cover:

- no-marker verify with Node.js absent;
- no-marker verify with unmanaged Node.js present;
- no Atlas module dependency;
- install writes `installing` before DNF and promotes only after validation;
- installed marker verifies healthy package/command state;
- `installing` marker fails verify and is repairable by install;
- malformed marker, insecure marker mode, unknown keys, missing fields;
- missing package, missing command, non-executable command;
- wrong RPM owner for `/usr/bin/node`;
- wrong RPM owner for `/usr/bin/npm`;
- wrong Node major;
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
- hostile Node/npm environment does not affect trusted probes.

Integration/Fedora acceptance must run:

```
atlasctl install development/node
node --version
npm --version
atlasctl verify development/node
atlasctl doctor development/node
atlasctl status development/node
atlasctl install development/node
```

The repeated install must be idempotent.

## 9. Architecture review

The architecture review challenged the areas most likely to leak ownership:

1. **LTS major selection.** Node 24 is Active LTS upstream and Fedora 44 packages
   it as `nodejs24`. Encoding the major avoids accidental adoption of a future
   package-major switch.
2. **npm boundary.** Fedora packages npm with the Node major, so Atlas installs
   and verifies npm availability. It does not manage npm configuration, global
   packages, cache, credentials, or project dependencies.
3. **Alternative runtimes.** pnpm, bun, yarn, corepack, nvm, fnm, Volta, asdf,
   and Deno are separate ownership boundaries. Their presence must not affect
   this module.
4. **Project state.** JavaScript projects are user-owned. Atlas never invokes
   commands that would run package lifecycle scripts or touch dependencies.
5. **Update behavior.** Fedora package updates own package currency. Atlas does
   not switch Node majors or run npm self-updates.

No engine or module-contract change is required.

## 10. Implementation roadmap

1. Add the module skeleton and README.
2. Add failing regression tests for the complete §8 matrix.
3. Implement strict marker parsing/writing.
4. Implement fixed-path package/command probes.
5. Implement lifecycle hooks.
6. Update module inventory tests, RFC index, docs, and changelog.
7. Run syntax checks, `git diff --check`, module tests, implementation review,
   and Fedora acceptance.

## 11. Sources

- [Node.js Release Working Group schedule](https://github.com/nodejs/Release#release-schedule)
- [Node.js Release schedule JSON](https://raw.githubusercontent.com/nodejs/Release/main/schedule.json)
- Fedora package metadata for `nodejs24`, `nodejs24-bin`, `nodejs24-npm`, and
  `nodejs24-npm-bin` queried from Fedora 44 repositories.
