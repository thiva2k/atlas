# RFC-0010: Fastfetch Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-12 |
| **Phase / order** | Experience Phase 2 - Workstation identity |
| **Depends on** | Nothing - `MODULE_DEPENDS=()` |
| **Establishes** | The system identity pattern for non-invasive user-overridable desktop config |

## 1. Summary

Implement `modules/desktop/fastfetch` as the Atlas workstation identity module.
Atlas installs Fastfetch from Fedora, writes one Atlas-owned system-level
configuration, and records ownership with a marker. It never edits user
Fastfetch files.

The central rule is:

> Atlas provides the default workstation identity; user Fastfetch configuration
> always wins.

## 2. Goals and non-goals

**Goals**

- Install Fedora package `fastfetch`.
- Provide an Atlas-branded, engineering-focused Fastfetch layout.
- Keep output minimal and useful.
- Install config in an Atlas-owned system XDG location.
- Verify the binary and Atlas-managed config.
- Support idempotent install, update, verify, remove, backup, and restore.

**Non-goals**

- Editing `$XDG_CONFIG_HOME/fastfetch/config.jsonc`.
- Removing user Fastfetch configs.
- Displaying decorative spam, large logos, or novelty modules.
- Installing unrelated system information tools.
- Adding engine hooks or changing runner behavior.

## 3. Config ownership

The Atlas system config path is:

```text
/etc/xdg/fastfetch/config.jsonc
```

This is a default only. If the user has:

```text
$XDG_CONFIG_HOME/fastfetch/config.jsonc
```

Fastfetch may load the user file first; Atlas treats that as user ownership and
does not repair or overwrite it.

The Atlas config displays:

- Atlas identity;
- Fedora version;
- kernel;
- CPU;
- memory;
- GPU;
- shell;
- terminal;
- Git;
- Python;
- Node;
- Docker;
- Claude;
- Codex;
- hostname and user;
- theme and color palette where Fastfetch can detect them.

## 4. Marker state

The marker path is:

```text
$ATLAS_STATE_DIR/installed/desktop-fastfetch
```

The parent directory is mode `700`; the marker is mode `600` and written
atomically. It records:

```text
schema=1
state=installing|installed|detached
package=fastfetch
config_path=/etc/xdg/fastfetch/config.jsonc
config_sha256=<hash of Atlas source config>
```

The marker is the only ownership signal.

## 5. Lifecycle contract

### 5.1 `check`

`check` returns `0` only when the marker is valid, state is `installed`,
Fastfetch is runnable, and the Atlas-managed config matches source.

### 5.2 `install`

`install`:

1. Requires Fedora.
2. Validates any existing marker.
3. Refuses an existing system config when no marker exists.
4. Writes an `installing` marker before durable mutation.
5. Installs `fastfetch`.
6. Writes the Atlas system config atomically.
7. Runs `fastfetch --config <Atlas config>`.
8. Promotes the marker to `installed`.

### 5.3 `verify` and `doctor`

With no marker, `verify` returns `0`. If Fastfetch exists, it reports it as
user-owned/unmanaged. With `detached`, it returns `0` and warns. With
`installing` or `installed`, broken managed state fails verification.

### 5.4 `update`

`update` rewrites the Atlas system config from source and verifies it. It does
not upgrade packages.

### 5.5 `remove`

`remove` deletes only the Atlas-owned system config if it still matches source,
then writes `detached`. It never uninstalls `fastfetch` or touches user config.

### 5.6 `backup` and `restore`

Both hooks are documented no-ops. Atlas-owned Fastfetch state is
reconstructable; user config is user-owned.

## 6. Validation matrix

- clean pre-install verify succeeds;
- unmanaged Fastfetch verify succeeds as user-owned;
- existing system config with no marker refuses install;
- install writes marker and config;
- repeated install is idempotent;
- repeated verify is idempotent;
- doctor follows verify;
- config drift fails verify and remove;
- package failure leaves `installing`;
- unsupported non-Fedora fails before mutation;
- remove detaches without uninstalling package;
- backup and restore are no-ops.

## 7. Architecture review findings

- **Ownership:** marker-only ownership prevents silent adoption.
- **User preservation:** user Fastfetch config is never read, written, or
  removed.
- **Security:** package source is Fedora; no network downloads or external repos.
- **Maintainability:** one source config, one system config, one marker.
- **Idempotency:** all hooks are repeatable.

No engine or architecture change is required.
