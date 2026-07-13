# RFC-0016: Claude Code Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-12 |
| **Phase / order** | Phase 2 — AI coding CLI |
| **Depends on** | Nothing — `MODULE_DEPENDS=()` |
| **Establishes** | The lifecycle pattern for externally packaged AI coding CLIs |

---

## 1. Summary

Implement `modules/development/claude` as Atlas's lifecycle manager for the
Claude Code CLI.

Atlas installs Claude Code from Anthropic's signed RPM repository, verifies the
fixed system command at `/usr/bin/claude`, writes a narrow Atlas-managed policy
drop-in, and records ownership with a strict marker. Atlas does not manage
Claude authentication, API keys, accounts, MCP servers, project instructions,
session history, or user personalization.

The central rule is:

> Atlas makes Claude Code available through a trusted package boundary; the user
> owns all identity, credentials, projects, conversations, and personalization.

## 2. Goals and non-goals

**Goals**

- Install Anthropic's `claude-code` RPM package.
- Vendor Anthropic's Claude Code RPM signing key as versioned module data.
- Validate the bundled key hash and fingerprint before import.
- Write an Atlas-owned DNF repository file for the stable Claude Code channel.
- Verify `/usr/bin/claude` through fixed-path, RPM-owned probes.
- Write one Atlas-owned managed-settings drop-in to disable background
  self-updates and keep package currency under DNF.
- Record Atlas ownership through a strict marker.
- Provide idempotent `check`, `install`, `verify`, `update`, `remove`,
  `backup`, and `restore` hooks.

**Non-goals**

- Managing Claude authentication, API keys, OAuth sessions, or account state.
- Managing `~/.claude`, `~/.claude.json`, `CLAUDE.md`, `.mcp.json`, project
  `.claude/` directories, plugins, skills, hooks, subagents, transcripts, or
  conversation history.
- Managing MCP servers or company-specific policy.
- Running `claude`, interactive login, `claude doctor`, `claude update`, or any
  command that may read or mutate user/project state.
- Installing Claude Code through npm, curl-piped native installers, Homebrew,
  tarballs, or release binaries.
- Enabling shell completions or editing shell startup files.

## 3. Package source and trusted paths

Atlas uses Anthropic's signed RPM repository stable channel:

```
https://downloads.claude.ai/claude-code/rpm/stable
```

Anthropic documents DNF installation for Fedora/RHEL and publishes the signing
key fingerprint:

```
31DD DE24 DDFA B679 F42D 7BD2 BAA9 29FF 1A7E CACE
```

Atlas vendors the public key and never downloads signing keys during module
execution. The trusted CLI path is:

```
/usr/bin/claude
```

Atlas must not use `PATH` to select Claude Code for managed verification.
User-installed Claude binaries in `~/.local/bin`, npm prefixes, native installer
directories, or shell shims are valid user-owned state until the Atlas marker
exists and the fixed package-managed path satisfies the contract.

The trusted probe contract is:

1. `/usr/bin/claude` exists and is executable.
2. `rpm -qf /usr/bin/claude` resolves to a `claude-code-*` package.
3. `/usr/bin/claude --version` succeeds and prints a nonempty version string.

## 4. Atlas-owned state

| State | Path | Lifecycle |
|---|---|---|
| RPM signing key source | `modules/development/claude/config/claude-code.asc` | versioned source data |
| DNF repository source | `modules/development/claude/config/claude-code.repo` | versioned source data |
| Managed settings source | `modules/development/claude/config/00-atlas.json` | versioned source data |
| DNF repository file | `/etc/yum.repos.d/claude-code.repo` | install/update/remove, only with marker |
| Managed settings drop-in | `/etc/claude-code/managed-settings.d/00-atlas.json` | install/update/remove, only with marker |
| Package intent | `claude-code` | install/verify; never uninstall in `remove` |
| Installation marker | `$ATLAS_STATE_DIR/installed/development-claude` | create atomically, validate strictly, remove narrowly |

The managed settings drop-in contains only:

```json
{
  "env": {
    "DISABLE_AUTOUPDATER": "1"
  }
}
```

This keeps background updates aligned with the package-manager boundary. It does
not block user authentication, user settings, MCP configuration, project
settings, or manual DNF upgrades.

## 5. User-owned and external state

Atlas never owns:

- `~/.claude`;
- `~/.claude.json`;
- OAuth sessions, API keys, account selection, or credential helpers;
- `CLAUDE.md`, `.claude/`, `.mcp.json`, project trust, permissions, hooks,
  plugins, skills, subagents, or local settings;
- conversation history, transcripts, caches, generated summaries, or background
  worktrees;
- any managed settings file except Atlas's exact drop-in path.

Existing organization policy under `/etc/claude-code` remains external unless it
is Atlas's exact drop-in file and the Atlas marker is valid.

## 6. Marker state

The marker path is:

```
$ATLAS_STATE_DIR/installed/development-claude
```

The parent directory is mode `700`; the marker is mode `600` and written
atomically. The marker records:

```
schema=1
state=installing|installed
package_source=claude-code
packages=claude-code
repo_sha256=<Atlas source repo hash>
settings_sha256=<Atlas source settings hash>
```

Malformed, unreadable, mode-insecure, unknown-key, or inconsistent markers are
broken managed state and fail verification. An `installing` marker means Atlas
started but did not complete installation; `install` may reconcile it, but
`verify` must fail until the marker is promoted to `installed`.

There is no `detached` state. `remove` deletes the Atlas-owned repository file,
managed settings drop-in, and marker when they still match Atlas source. It does
not uninstall `claude-code`.

## 7. Lifecycle contract

### 7.1 `check`

`check` returns `0` only when the marker is valid, state is `installed`, the
managed repo/settings files match Atlas source, the package is installed, and
the trusted command probe passes.

### 7.2 `install`

`install` is idempotent and follows this order:

1. Require Fedora before any mutation.
2. Validate any existing marker.
3. Validate bundled key, repo source, and settings source.
4. Refuse unsafe fixed-path conflicts before mutation:
   - `/usr/bin/claude` exists but is not executable;
   - `/usr/bin/claude` exists and is not RPM-owned by `claude-code-*`.
5. Refuse unmanaged Atlas-owned paths before mutation:
   - repo file exists without an Atlas marker;
   - managed settings drop-in exists without an Atlas marker.
6. Write an `installing` marker atomically.
7. Import only the bundled signing key and verify the imported fingerprint.
8. Write the Atlas repository file and managed settings drop-in atomically.
9. Run `os::dnf_install claude-code`.
10. Validate package presence, trusted command probe, repo, settings, and marker.
11. Promote the marker atomically to `installed`.

### 7.3 `verify` and `doctor`

With no marker, `verify` returns `0`. It logs whether Claude Code appears absent
or present but unmanaged.

With a valid `installed` marker, `verify` fails only when Atlas-managed expected
state is broken: package missing, trusted command missing, wrong RPM ownership,
non-runnable command, repository drift, managed settings drift, key source
tampering, or invalid marker.

With an `installing` marker, `verify` fails and tells the user to rerun install.

The current runner dispatches `atlasctl doctor` to `module::verify`; RFC-0016
preserves that contract. Atlas does not run `claude doctor` because it may read
authentication, project, network, or user configuration state outside Atlas's
ownership boundary.

### 7.4 `update`

`update` restores Atlas-owned repository/settings drift and reports that package
currency is managed by DNF. It does not run `claude update`.

### 7.5 `remove`

`remove` deletes only Atlas-owned repo/settings files that still match Atlas
source and the Atlas marker. It refuses drifted or malformed managed state
rather than guessing. It never uninstalls `claude-code` and never touches user
Claude state.

### 7.6 `backup` and `restore`

`backup` and `restore` are documented no-op hooks returning `0`.

The CLI installation is reconstructable from the RPM repository. User Claude
state contains credentials, sessions, project trust, and conversations, all of
which are user-owned and must not be copied by Atlas.

## 8. Security considerations

- Runtime key downloads are prohibited. Atlas imports only the bundled key after
  hash and fingerprint validation.
- The repo file enables `gpgcheck=1`.
- The fixed command probe ignores `PATH` shims and Claude-related environment
  variables.
- Atlas does not run interactive Claude commands, login, doctor, update, MCP, or
  project commands.
- Authentication and API keys remain user-owned and are never read.
- Background self-updates are disabled through an Atlas-owned managed-settings
  drop-in so package-manager ownership remains deterministic.
- Existing organization policy files are not adopted or overwritten.

## 9. Testing and validation matrix

Unit tests must cover:

- no-marker verify success when Claude Code is absent;
- no-marker verify success when Claude Code is present but unmanaged;
- malformed, insecure, unknown-key, hash-mismatch, and installing markers;
- bundled key hash/fingerprint validation;
- repo/settings source validation;
- non-Fedora install refusal before mutation;
- unmanaged repo/settings refusal before mutation;
- fixed-path executable and RPM ownership preflight;
- marker written before key/repo/settings/DNF mutation;
- exact package set;
- promotion only after validation;
- DNF failure leaves `installing`;
- verify failures for missing package, command, wrong owner, repo drift, and
  settings drift;
- update restores repo/settings drift only for valid managed state;
- remove deletes only Atlas-owned repo/settings/marker and never uninstalls;
- backup/restore no-ops;
- runner status and doctor behavior.

Real Fedora validation must include:

```
atlasctl install development/claude
claude --version
atlasctl verify development/claude
atlasctl doctor development/claude
atlasctl status development/claude
atlasctl install development/claude
```

The second install must perform no work. Authentication is explicitly outside
this validation.

## 10. Architecture review

- **Ownership:** marker-based ownership only; no user or project Claude state is
  adopted.
- **Security:** signed RPM channel, bundled key, fixed path, no credential reads,
  no interactive commands.
- **Idempotency:** `check` gates satisfied installs; `install` repairs an
  interrupted marker only after preflight; `remove` is narrow and repeatable.
- **Future extensibility:** organization policy, MCP, plugins, and auth helpers
  can become separate RFCs if Atlas chooses to manage them later.
- **No engine change:** existing module hooks are sufficient.
