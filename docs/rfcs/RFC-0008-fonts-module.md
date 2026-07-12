# RFC-0008: Fonts Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-12 |
| **Phase / order** | Experience Phase 1 - Typography foundation |
| **Depends on** | Nothing - `MODULE_DEPENDS=()` |
| **Establishes** | The typography ownership contract for the Atlas experience layer |

## 1. Summary

Implement `modules/desktop/fonts` as the typography foundation for the Atlas
experience layer. Atlas installs Inter from Fedora packages, installs
JetBrains Mono Nerd Font from a pinned Nerd Fonts upstream release into an
Atlas-owned user font directory, refreshes the fontconfig cache, and records
ownership with a strict marker.

The central rule is:

> Atlas owns only the fonts and cache refresh intent it creates, never user font
> collections or font preferences.

## 2. Goals and non-goals

**Goals**

- Install `JetBrainsMono Nerd Font` for terminal usage.
- Install `Inter` for system UI usage.
- Refresh fontconfig cache for Atlas-owned fonts.
- Verify through `fc-list` and `fc-match`.
- Record ownership through an Atlas marker.
- Provide idempotent `check`, `install`, `verify`, `update`, `remove`,
  `backup`, and `restore` hooks.

**Non-goals**

- Managing user font preferences, KDE font settings, Ghostty font settings, or
  application font settings.
- Installing broad font collections.
- Removing or modifying user-installed fonts.
- Claiming ownership from font presence alone.
- System-wide installation of the Nerd Font asset.

## 3. Package and asset sources

Fedora 44 package metadata provides:

```text
rsms-inter-fonts
rsms-inter-vf-fonts
jetbrains-mono-fonts
jetbrains-mono-fonts-all
```

Cached Fedora metadata does not provide a JetBrains Mono Nerd Font package. It
does provide other Nerd Font packages, but the experience manual requires
JetBrains Mono Nerd Font specifically.

Atlas therefore uses two sources:

- `rsms-inter-fonts` from Fedora repositories.
- `JetBrainsMono.tar.xz` from Nerd Fonts release `v3.4.0`.

Nerd Fonts release `v3.4.0` is the latest release observed on 2026-07-12, and
its release page links both font archives and SHA-256 checksums. The module pins
the version and archive name:

```text
https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/JetBrainsMono.tar.xz
https://github.com/ryanoasis/nerd-fonts/releases/download/v3.4.0/SHA-256.txt
```

The module downloads the checksum file and archive over HTTPS, verifies the
archive against the checksum entry for `JetBrainsMono.tar.xz`, extracts only
regular `.ttf` and `.otf` files, and installs them into an Atlas-owned user font
directory. It must not use an unpinned `latest` URL.

## 4. Ownership model

### 4.1 Atlas-owned state

| State | Atlas owns it when | Lifecycle |
|---|---|---|
| Nerd Font directory | an Atlas marker records the same path and release | create, verify, update, remove |
| Inter package intent | an Atlas marker records Fedora package intent | install, verify; never uninstall in remove |
| Install marker | always | create atomically, validate strictly |

The Nerd Font directory is:

```text
$XDG_DATA_HOME/fonts/atlas/JetBrainsMonoNerdFont
```

with default:

```text
$HOME/.local/share/fonts/atlas/JetBrainsMonoNerdFont
```

Atlas does not own `$XDG_DATA_HOME/fonts` or any sibling font directories.

### 4.2 User-owned state

Atlas never owns:

- user-installed fonts outside the recorded Atlas directory;
- KDE or application font preferences;
- fontconfig files in user or system config directories;
- system package files installed independently by the user;
- any font file not recorded through the marker.

If the Atlas Nerd Font directory exists before an Atlas marker, `install`
refuses rather than adopting or overwriting it.

## 5. Marker state

The marker path is:

```text
$ATLAS_STATE_DIR/installed/desktop-fonts
```

The parent directory is mode `700`; the marker is mode `600` and written
atomically. It records:

```text
schema=1
state=installing|installed|detached
inter_package=rsms-inter-fonts
nerd_font_version=v3.4.0
nerd_font_archive=JetBrainsMono.tar.xz
nerd_font_url=<pinned URL>
nerd_font_dir=<absolute Atlas font directory>
```

Malformed, unreadable, insecure, or inconsistent markers are broken managed
state and fail verification.

`detached` means Atlas removed its owned Nerd Font files and no longer asserts
font health, while leaving Fedora packages installed.

## 6. Lifecycle contract

### 6.1 `check`

`check` returns `0` only when the marker is valid, state is `installed`, the
Atlas Nerd Font directory contains font files, `fc-match "JetBrainsMono Nerd
Font"` resolves to a JetBrains Mono Nerd Font family, and `fc-match Inter`
resolves to Inter.

### 6.2 `install`

`install` is idempotent:

1. Require Fedora before mutation.
2. Load and validate any existing marker.
3. If no marker exists, refuse a pre-existing Atlas Nerd Font directory.
4. Write an `installing` marker before durable mutation.
5. Install required Fedora packages: `fontconfig`, `curl`, `xz`, and
   `rsms-inter-fonts`.
6. Download and verify the pinned Nerd Fonts archive when the Atlas Nerd Font
   directory is missing or invalid.
7. Refresh the fontconfig cache for the Atlas-owned directory.
8. Verify `fc-list`, `fc-match "JetBrainsMono Nerd Font"`, and
   `fc-match Inter`.
9. Promote the marker to `installed`.

### 6.3 `verify` and `doctor`

The runner maps `doctor` to `verify`; this module preserves that contract.

With no marker, `verify` returns `0` and reports whether matching fonts appear
present but unmanaged. With `detached`, it returns `0` and warns that Atlas no
longer asserts typography health. With `installing` or `installed`, it fails
when managed font state is broken.

### 6.4 `update`

`update` refreshes the Atlas Nerd Font directory to the pinned version and
refreshes the font cache. It does not upgrade Fedora packages; package currency
belongs to Fedora updates.

### 6.5 `remove`

`remove` deletes only the recorded Atlas Nerd Font directory after marker
validation, refreshes the font cache, and writes a `detached` marker. It does
not uninstall `rsms-inter-fonts` or touch user fonts/preferences.

### 6.6 `backup` and `restore`

`backup` and `restore` are documented no-op hooks returning `0`.

Atlas-owned font state is reconstructable from Fedora packages and the pinned
Nerd Fonts release. User font collections and preferences are user-owned.

## 7. Validation matrix

Required coverage:

- clean Fedora pre-install verifies successfully;
- unmanaged fonts verify as user-owned;
- install writes marker and Atlas-owned font directory;
- repeated install is idempotent;
- repeated verify is idempotent;
- `doctor` follows verify;
- `status` reports installed/not installed correctly;
- `fc-list` absence fails managed verify;
- `fc-match "JetBrainsMono Nerd Font"` absence fails managed verify;
- `fc-match Inter` absence fails managed verify;
- package failure leaves `installing` state;
- download or checksum failure leaves `installing` state;
- unsupported non-Fedora install fails before mutation;
- remove deletes only Atlas-owned Nerd Font files and leaves Inter installed;
- detached reinstall refuses a user-created Atlas font directory;
- backup and restore are no-ops.

## 8. Architecture review findings

- **Ownership:** marker-only ownership avoids adopting user font directories.
- **Configuration:** no font preferences are written; later modules may reference
  family names only.
- **Security:** Fedora packages are preferred. The only upstream asset is
  version-pinned and checksum-verified; no unpinned latest URL is used.
- **Idempotency:** package installation, font extraction, cache refresh, verify,
  update, and remove are repeatable.
- **Maintainability:** all managed files live under one Atlas-owned font
  directory; no engine changes are required.

No architecture or engine change is required.
