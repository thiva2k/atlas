# RFC-0014: Fish Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-12 |
| **Phase / order** | Phase 2 — Shell foundation · module 8 of 16 |
| **Depends on** | Nothing — `MODULE_DEPENDS=()` |
| **Establishes** | The shell configuration ownership contract for Atlas |

---

## 1. Summary

Implement `modules/development/fish` as Atlas's lifecycle manager for the Fedora
Fish shell package and a minimal Atlas-owned Fish configuration snippet. Atlas
installs Fedora's `fish` package, verifies `/usr/bin/fish`, writes exactly one
isolated Fish snippet at `$XDG_CONFIG_HOME/fish/conf.d/00-atlas.fish`, and
records ownership with a strict marker.

Atlas does not change the user's login shell. It does not edit
`config.fish`, aliases, functions, completions, plugins, universal variables, or
other user-owned Fish files. Fish becomes the preferred interactive shell by
being installed and prepared; terminal/profile decisions remain user- or
desktop-owned until a separate RFC explicitly owns them.

The central rule is:

> Atlas owns one isolated Fish include file, never the user's Fish configuration.

## 2. Goals and non-goals

**Goals**

- Install Fedora's `fish` package.
- Verify the fixed system command at `/usr/bin/fish`.
- Require RPM ownership by Fedora's `fish-*` package.
- Write an isolated Atlas Fish snippet:
  `$XDG_CONFIG_HOME/fish/conf.d/00-atlas.fish`.
- Record the expected snippet hash in the marker.
- Provide idempotent `check`, `install`, `verify`, `update`, `remove`,
  `backup`, and `restore` hooks.

**Non-goals**

- Changing the login shell with `chsh`.
- Editing `/etc/shells`.
- Editing terminal emulator profiles.
- Editing `~/.config/fish/config.fish`.
- Managing aliases, functions, completions, plugins, abbreviations, or universal
  variables.
- Managing Starship prompt integration.
- Managing user environment policy beyond the Atlas snippet.

## 3. Package source and trusted command path

Atlas uses Fedora's official package repositories:

```
fish
```

Fedora describes Fish as a friendly interactive shell with syntax highlighting,
autosuggestions, and tab completions. Fish documentation says user configuration
is stored in `$XDG_CONFIG_HOME/fish/config.fish` and that `*.fish` snippets in
`$XDG_CONFIG_HOME/fish/conf.d/` are automatically executed before `config.fish`.
Atlas uses that snippet mechanism because it avoids editing the user-owned
`config.fish`.

The trusted probe uses a fixed system path:

```
/usr/bin/fish
```

The trusted probe contract is:

1. `/usr/bin/fish` exists and is executable.
2. `rpm -qf /usr/bin/fish` resolves to a `fish-*` package.
3. `/usr/bin/fish --version` succeeds and reports `fish, version ...`.

Atlas must not use `PATH` to select Fish for managed verification.

## 4. Ownership and state model

### 4.1 Atlas-owned state

| State | Atlas owns it when | Lifecycle |
|---|---|---|
| Required package intent | an Atlas marker records Fedora package source and package set | install/verify; never uninstall in `remove` |
| Fish snippet | an Atlas marker records its hash and path | create atomically, verify exact content, delete on remove |
| Installation marker | always | create atomically, validate strictly, remove narrowly |

The snippet path is:

```
${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/00-atlas.fish
```

Atlas refuses to overwrite a pre-existing snippet when no valid marker exists.
That file name is reserved for Atlas only after Atlas has created and recorded
it.

### 4.2 User-owned and external state

Atlas never owns:

- `config.fish`;
- user snippets other than `00-atlas.fish`;
- aliases, functions, completions, abbreviations, plugins, universal variables,
  or command history;
- login shell state;
- terminal emulator configuration;
- Starship prompt configuration.

### 4.3 Marker state

The marker path is:

```
$ATLAS_STATE_DIR/installed/development-fish
```

The parent directory is mode `700`; the marker is mode `600` and written
atomically. The marker records:

```
schema=1
state=installing|installed
package_source=fedora
packages=fish
config_path=<absolute Atlas Fish snippet path>
config_sha256=<expected snippet SHA-256>
```

Malformed, unreadable, mode-insecure, or inconsistent markers are broken
managed state and fail verification. An `installing` marker means Atlas started
but did not complete installation; `install` may reconcile it, but `verify` must
fail until the marker is promoted to `installed`.

There is no `detached` state. `remove` deletes only the Atlas snippet and marker
when the snippet still matches Atlas's expected content. It never uninstalls
Fish.

## 5. Lifecycle contract

### 5.1 `check`

`check` returns `0` only when the marker is valid, state is `installed`, the
trusted Fish probe passes, and the Atlas snippet matches the marker hash.

### 5.2 `install`

`install` is idempotent and follows this order:

1. Require Fedora before any mutation.
2. Validate any existing marker.
3. Refuse unsafe fixed-path conflicts before mutation:
   - `/usr/bin/fish` exists but is not executable;
   - `/usr/bin/fish` exists and is not RPM-owned by `fish-*`.
4. Refuse a pre-existing unmanaged Atlas snippet before mutation.
5. Write an `installing` marker atomically.
6. Run `os::dnf_install fish`.
7. Write the Atlas snippet atomically.
8. Validate package presence, trusted command probe, and snippet hash.
9. Promote the marker atomically to `installed`.

The Atlas snippet is intentionally minimal:

```fish
# Managed by Atlas: development/fish. Do not edit.
set -gx ATLAS_SHELL fish
```

### 5.3 `verify` and `doctor`

With no marker, `verify` returns `0`. It logs whether Fish appears absent,
present unmanaged, or whether an unmanaged `00-atlas.fish` file exists.

With a valid `installed` marker, `verify` fails only when Atlas-managed expected
state is broken: package missing, command missing, wrong RPM ownership,
non-runnable Fish, snippet missing, snippet drift, invalid marker path, or
invalid marker hash.

With an `installing` marker, `verify` fails and tells the user to rerun install
to reconcile.

Doctor recommends actions; it does not repair.

### 5.4 `update`

`update` restores the Atlas-owned snippet only when the marker is valid and the
snippet path is the expected Atlas path. It does not upgrade Fish packages or
touch user-owned Fish files.

### 5.5 `remove` hook

`remove` deletes only the Atlas snippet and marker. If the snippet has drifted,
`remove` refuses rather than deleting a file that may now contain user changes.
Repeated `remove` is a no-op.

### 5.6 `backup` and `restore`

`backup` and `restore` are documented no-op hooks returning `0`.

The managed package and Atlas snippet are reconstructable by reinstalling. User
Fish configuration is explicitly user-owned and must not be backed up or
restored by this module.

## 6. Security considerations

Shell startup files execute code in every Fish session. Atlas therefore:

- writes only one isolated snippet;
- refuses pre-existing unmanaged snippet paths;
- verifies exact content with SHA-256;
- never edits user-owned `config.fish`;
- never changes login shell or `/etc/shells`;
- never sources user-controlled paths from the Atlas snippet;
- deletes the snippet only when it still matches Atlas content.

## 7. Dependency model and future extensibility

`development/fish` has no module dependencies. `development/starship` may later
integrate with Fish through its own Atlas-owned snippet or through an explicitly
documented shell integration contract. Starship must not modify Fish-owned state
without an RFC.

## 8. Testing strategy

Pure-Bash unit tests mock DNF and RPM queries and override private helper
functions for system paths. They must cover:

- no-marker verify with Fish absent;
- no-marker verify with unmanaged Fish present;
- no-marker verify with unmanaged Atlas snippet present;
- install refuses unmanaged snippet before mutation;
- install writes `installing` before DNF and promotes only after validation;
- installed marker verifies healthy package/command/snippet state;
- `installing` marker fails verify and is repairable by install;
- malformed marker, insecure marker mode, unknown keys, missing fields;
- marker hash mismatch;
- marker path mismatch;
- missing package, missing command, non-executable command;
- wrong RPM owner for `/usr/bin/fish`;
- DNF failure leaves marker in `installing`;
- non-Fedora install refusal before mutation;
- repeated install idempotency;
- repeated verify idempotency;
- update restores Atlas snippet drift;
- doctor through runner uses verify contract;
- status reports not installed before marker and installed after marker;
- backup/restore no-op hooks;
- remove deletes only Atlas snippet and marker;
- remove refuses drifted snippet;
- remove is idempotent.

Integration/Fedora acceptance must run:

```
atlasctl install development/fish
fish --version
atlasctl verify development/fish
atlasctl doctor development/fish
atlasctl status development/fish
atlasctl install development/fish
```

The repeated install must be idempotent.

## 9. Architecture review

1. **Login shell.** Changing the login shell can break environments expecting a
   Bourne-compatible login shell. Atlas installs Fish but does not run `chsh`.
2. **User config.** Editing `config.fish` would violate the ownership model.
   Fish's `conf.d` mechanism gives Atlas an isolated file.
3. **Prompt integration.** Starship belongs to a separate module. Fish must not
   hard-code prompt behavior.
4. **Remove behavior.** Removing Fish packages may break user workflows. Remove
   is marker/snippet-only.
5. **Future shell modules.** The contract is file-based and marker-bound, so
   future shell integrations can add their own files without reaching into Fish
   internals.

No engine or module-contract change is required.

## 10. Sources

- Fedora package metadata for `fish` queried from Fedora 44 repositories.
- [Fish introduction and configuration documentation](https://fishshell.com/docs/current/index.html)
- [Fish configuration file order](https://fishshell.com/docs/current/language.html#configuration-files)
