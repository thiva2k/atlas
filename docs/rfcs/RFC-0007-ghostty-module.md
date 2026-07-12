# RFC-0007: Ghostty Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-11 |
| **Phase / order** | Phase 2 - Developer desktop apps - module 6 of 16 |
| **Depends on** | Nothing - `MODULE_DEPENDS=()` |
| **Establishes** | The lifecycle pattern for developer-facing desktop applications |

## 1. Summary

Implement `modules/development/ghostty` as Atlas's reference developer
terminal. Atlas installs Ghostty from the Fedora COPR package source documented
by Ghostty, records Atlas ownership with a marker, creates an isolated
Atlas-managed Ghostty configuration when safe, selects a theme and font
references, enables Ghostty's own shell integration, and verifies only state
Atlas created.

The central rule is:

> Atlas owns Ghostty's installation intent and Atlas-created configuration, not
> the user's terminal workflows.

`development/ghostty` replaces the placeholder `apps/ghostty`. Ghostty is a
desktop application, but in Atlas it is also a developer substrate: shells,
prompts, editors, multiplexers, and project workflows run inside it. The
`development/` category makes those future dependencies and ownership
boundaries explicit without changing the engine or module contract.

## 2. Goals and non-goals

**Goals**

- Install Ghostty on Fedora using the documented Fedora COPR source.
- Manage the COPR repository only as required to install Ghostty.
- Create Atlas-owned Ghostty config and theme files when Atlas can do so without
  overwriting a user file.
- Reference developer fonts by family name only; font installation belongs to
  `desktop/fonts`.
- Enable Ghostty's own shell integration without editing shell configuration.
- Record ownership with an Atlas marker.
- Verify installed binary health, desktop launcher presence, managed config,
  managed theme, and marker consistency.
- Provide idempotent `check`, `install`, `verify`, `update`, `remove`,
  `backup`, and `restore` hooks.

**Non-goals**

- Managing Fish, Zsh, Bash, shell startup files, aliases, environment variables,
  keybindings, prompt configuration, or Starship.
- Installing fonts or asserting that a referenced font is present.
- Managing user-created themes or user workflow-specific Ghostty settings.
- Managing project-specific terminal state.
- Building Ghostty from source, installing AppImages/Snaps/Terra packages, or
  using `--nogpgcheck`.
- Launching GUI windows during verification.

## 3. Package source and repository management

Ghostty's upstream Linux install page says the project officially distributes
macOS binaries and relies on distributions and community maintainers for Linux.
For Fedora, the documented package path is the `scottames/ghostty` Fedora COPR:

```
dnf copr enable scottames/ghostty
dnf install ghostty
```

Atlas uses that source because Fedora does not provide a base-repository
Ghostty package in the documented upstream install path. This is a narrower
trust decision than arbitrary community binaries: it uses Fedora COPR and normal
DNF/RPM package verification. Atlas must not use Terra's documented
`--nogpgcheck` path because that weakens package signature checking.

`install` may install `dnf-plugins-core` if the `dnf copr` subcommand is missing.
It then enables the COPR repository with:

```
dnf -y copr enable scottames/ghostty
```

The expected COPR repo file is:

```
/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:scottames:ghostty.repo
```

Atlas validates that this repo is enabled, names the expected COPR id, has a
`baseurl`, and keeps `gpgcheck=1`. Atlas records that repository intent in the
marker, but does not own Fedora's RPM database or package files.

## 4. Configuration ownership

Ghostty loads `$XDG_CONFIG_HOME/ghostty/config.ghostty` before the legacy
`$XDG_CONFIG_HOME/ghostty/config`. Ghostty also supports `config-file`, and
those includes are processed after the containing file. Atlas uses this to keep
configuration isolated:

```
$XDG_CONFIG_HOME/ghostty/config.ghostty      # Atlas-owned primary file
$XDG_CONFIG_HOME/ghostty/themes/atlas-reference
```

The Atlas primary file:

- selects the Atlas theme;
- references preferred developer font families;
- enables Ghostty's own shell integration;
- includes `?user.ghostty` last as an optional user override file.

The optional override path is:

```
$XDG_CONFIG_HOME/ghostty/user.ghostty
```

Atlas never creates, edits, deletes, or verifies `user.ghostty`. It is the
documented customization seam for the user. Because `config-file` is processed
after the Atlas file, user settings in `user.ghostty` override Atlas defaults.

If `config.ghostty` already exists before Atlas has a marker, Atlas refuses to
claim configuration ownership. It may not overwrite, parse, or adopt that file
silently. If only the legacy `config` exists, Atlas may create
`config.ghostty`; Ghostty will load the legacy file later, so user settings
still override Atlas defaults.

After Atlas has a marker, `config.ghostty` and `themes/atlas-reference` are
managed files. `install` and `update` may rewrite them only if the marker is
valid and the paths are regular files or absent. Symlinks, directories, or
special files at managed paths are broken managed state and verification
failures.

## 5. Marker state

The marker path is:

```
$ATLAS_STATE_DIR/installed/development-ghostty
```

The parent directory is mode `700`; the marker is mode `600` and written
atomically. It records:

```
schema=1
state=installing|installed|detached
package_source=copr:scottames/ghostty
repo_file=/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:scottames:ghostty.repo
config_path=<absolute Atlas primary config path>
theme_path=<absolute Atlas theme path>
config_sha256=<hash of Atlas source config>
theme_sha256=<hash of Atlas source theme>
```

The marker is the only ownership signal. Existing `ghostty` on `PATH`, an
existing desktop file, or a Ghostty config directory does not imply Atlas
ownership.

`detached` means Atlas removed its configuration and stopped asserting package
health, but left Ghostty and the COPR repository in place. This preserves
provenance after a future `remove` platform verb becomes available.

## 6. Lifecycle contract

### 6.1 `check`

`check` returns `0` only when the marker is valid, state is `installed`, Ghostty
is runnable, the desktop launcher exists, the COPR repository remains enabled
with `gpgcheck=1`, and Atlas-managed config/theme files match the module
sources. A no-marker machine returns non-zero so `install` can decide whether it
is safe to enroll Ghostty.

### 6.2 `install`

`install` is idempotent:

1. Require Fedora before mutation.
2. Load and validate any existing marker.
3. If no marker exists, refuse an existing `config.ghostty` or unmanaged Ghostty
   install instead of adopting it silently.
4. Write an `installing` marker before durable mutation.
5. Ensure `dnf copr` is available, enable the `scottames/ghostty` COPR, and
   install `ghostty`.
6. Write Atlas config and theme files atomically.
7. Validate binary health, desktop launcher presence, repo health, and managed
   config/theme hashes.
8. Promote the marker to `installed`.

An interrupted install leaves an `installing` marker. A later install may
reconcile and promote it only after all checks pass.

### 6.3 `verify` and `doctor`

The runner maps `doctor` to `verify`, so this module uses the existing contract.

With no marker, `verify` returns `0` and reports whether Ghostty appears absent
or user-owned. With a `detached` marker, it returns `0` and warns that Atlas is
not asserting Ghostty health. With an `installing` or `installed` marker,
verification fails when managed state is broken.

Verification checks:

- marker validity and mode;
- `ghostty --version`;
- package ownership when RPM metadata is available;
- desktop launcher existence;
- COPR repo id, enabled state, and `gpgcheck=1`;
- Atlas config and theme files are regular files matching Atlas source.

It does not launch Ghostty, inspect shell startup files, check font presence, or
assert Starship/Fish/Zsh/Bash configuration.

### 6.4 `update`

`update` re-applies the latest Atlas config/theme and validates the managed
state. It does not upgrade packages; package currency remains Fedora/DNF policy.

### 6.5 `remove`

The platform still has no `atlas remove` verb, but the hook is specified for the
future.

`remove` deletes only Atlas-owned `config.ghostty` and
`themes/atlas-reference` when they still match Atlas source. It then writes a
`detached` marker. It never uninstalls Ghostty, disables/removes the COPR repo,
or deletes user files such as `user.ghostty`, legacy `config`, or user themes.

If a managed file has drifted, `remove` refuses rather than deleting a file that
may now contain user edits.

### 6.6 `backup` and `restore`

`backup` and `restore` are documented no-op hooks returning `0`.

Atlas-owned Ghostty state is reconstructable from the repository and module
sources. User Ghostty configuration, themes, keybindings, and workflows are
user-owned and must not be copied by this module.

## 7. Dependency model and future extensibility

`development/ghostty` has no Atlas module dependencies. It references fonts by
family name but does not depend on `desktop/fonts`; Ghostty works with its own
defaults when fonts are missing.

Future relationships:

- `desktop/fonts` may install the referenced font families, but Ghostty must not
  inspect that module's internals.
- A future `development/starship` module owns prompt installation and
  configuration. Ghostty only provides terminal shell integration.
- Future Fish/Zsh/Bash modules own shell setup. Ghostty must not edit shell
  startup files.
- Future desktop app modules should reuse this pattern: marker-only ownership,
  no silent adoption, Atlas-owned config fragments, user override seams, and
  non-GUI verification.

## 8. Backup, restore, idempotency, and security

Every durable write is atomic: same-directory temp file, mode set, then `mv`.
Package and repository operations are retried safely by DNF. Managed files are
rewritten from source only under a valid marker or during first enrollment.

Atlas never weakens Fedora security defaults:

- no `--nogpgcheck`;
- no downloaded shell installer;
- no source build during workstation install;
- no shell startup edits;
- no user keybinding or workflow rewrites;
- no deletion of unmanaged Ghostty files.

## 9. Validation matrix

Required test coverage:

- clean Fedora pre-install verifies successfully;
- unmanaged Ghostty install verifies as user-owned and install refuses adoption;
- Atlas-managed install writes marker, package intent, config, theme, and
  validates Ghostty;
- repeated install is idempotent;
- repeated verify is idempotent;
- doctor follows verify;
- remove hook detaches and preserves user files;
- config drift fails verify and refuses remove;
- user override file is preserved;
- package/COPR failures leave `installing` state;
- unsupported non-Fedora install fails before mutation;
- desktop launcher missing fails managed verify;
- repo `gpgcheck=0` fails managed verify;
- hostile shell environment does not change verification.

## 10. Architecture review findings

- **Ownership:** marker-only ownership avoids adopting unmanaged terminals.
- **Configuration:** Atlas owns only files it creates; `user.ghostty` is the
  explicit user override seam.
- **Desktop integration:** verification checks the launcher file without
  launching a GUI.
- **Security:** COPR is an explicit trust decision; `--nogpgcheck`, shell
  installers, source builds, and unchecked community repositories are excluded.
- **Idempotency:** install, update, verify, backup, and restore are repeatable;
  remove is repeatable after successful detach.
- **Maintainability:** the module is self-contained and does not require engine
  changes.

No architecture change is required.
