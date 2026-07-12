# RFC-0026: Codex Module

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-12 |
| **Phase / order** | Phase 2 — AI coding CLI |
| **Depends on** | `development/node` — `MODULE_DEPENDS=("development/node")` |
| **Establishes** | The lifecycle pattern for npm-packaged AI coding CLIs |

---

## 1. Summary

Implement `modules/development/codex` as Atlas's lifecycle manager for the
OpenAI Codex CLI.

Atlas installs the official `@openai/codex` npm package into a fixed system npm
prefix, verifies the fixed system command at `/usr/local/bin/codex`, and records
ownership with a strict marker. Atlas does not manage Codex authentication, API
keys, conversations, project state, prompts, user configuration, MCP servers,
skills, plugins, memory, or history.

The central rule is:

> Atlas makes Codex available through a fixed package boundary; the user owns
> all identity, credentials, projects, conversations, memory, and
> personalization.

## 2. Goals and non-goals

**Goals**

- Install OpenAI's official `@openai/codex` npm package.
- Use the existing Atlas-managed Node/npm runtime from `development/node`.
- Install into the fixed npm prefix `/usr/local`.
- Verify `/usr/local/bin/codex` through fixed-path probes.
- Verify the fixed command resolves into the managed npm package directory.
- Define the Codex configuration boundary explicitly and avoid writing global
  Codex configuration by default because `/etc/codex` affects user-owned Codex
  installations too.
- Record Atlas ownership through a strict marker.
- Provide idempotent `check`, `install`, `verify`, `update`, `remove`,
  `backup`, and `restore` hooks.

**Non-goals**

- Managing OpenAI authentication, ChatGPT login, API keys, OAuth sessions,
  access tokens, account state, or workspace membership.
- Managing `~/.codex`, `~/.codex/config.toml`, `~/.codex/auth.json`, profile
  files, transcripts, logs, memory, or session history.
- Managing `AGENTS.md`, `.codex/`, project config, prompts, rules, hooks,
  plugins, skills, subagents, MCP servers, cloud tasks, or project trust.
- Installing Codex through curl-piped shell installers, Homebrew, standalone
  release binaries, desktop apps, IDE extensions, or cloud integrations.
- Running interactive `codex`, sign-in flows, MCP commands, plugin commands,
  cloud commands, or any command that may read or mutate user/project state.
- Managing npm configuration, npm credentials, npm cache, or other global npm
  packages.

## 3. Package source and trusted paths

OpenAI documents Codex CLI installation on macOS/Linux via its standalone
installer and also documents package-manager installation with:

```
npm install -g @openai/codex
```

Atlas chooses the npm package path because Atlas already manages a Fedora
Node/npm foundation and because npm provides a deterministic package directory
and command shim that Atlas can inspect without executing interactive Codex
flows. Atlas does not use the curl-piped installer because it would execute a
remote script during installation.

The trusted npm and Codex paths are:

```
/usr/bin/npm
/usr/local/lib/node_modules/@openai/codex
/usr/local/bin/codex
```

Atlas must not use `PATH` to select Codex for managed verification.
User-installed Codex binaries in `~/.local/bin`, custom npm prefixes, standalone
installer directories, or shell shims are valid user-owned state until the Atlas
marker exists and the fixed Atlas-managed path satisfies the contract.

The trusted probe contract is:

1. `/usr/bin/npm` exists, is executable, and is RPM-owned by `nodejs24-npm-bin`.
2. `/usr/local/lib/node_modules/@openai/codex/package.json` exists and declares
   `"name": "@openai/codex"`.
3. `/usr/local/bin/codex` exists, is executable, and resolves under the managed
   npm package directory.
4. `/usr/local/bin/codex --version` succeeds and prints a nonempty version
   string.

## 4. Atlas-owned state

| State | Path | Lifecycle |
|---|---|---|
| npm package intent | `@openai/codex` under `/usr/local` | install/verify/remove, only with marker |
| Command shim | `/usr/local/bin/codex` | created by npm; verified as package-owned |
| Installation marker | `$ATLAS_STATE_DIR/installed/development-codex` | create atomically, validate strictly, remove narrowly |

Atlas owns no active Codex runtime configuration in this version. OpenAI's
documented system configuration locations, including `/etc/codex/config.toml`
and `/etc/codex/requirements.toml`, affect every local Codex client on the
machine. On a workstation where the user may already have a user-owned Codex
installation, writing those files would silently change external state. Any
future active Codex configuration must be introduced by a follow-up RFC with an
explicit migration and compatibility plan.

## 5. User-owned and external state

Atlas never owns:

- `~/.codex`;
- `~/.codex/config.toml`;
- `~/.codex/auth.json` or any token/session file;
- `~/.codex/*.config.toml` profile files;
- transcripts, logs, conversations, memory, cache, summaries, or local history;
- `AGENTS.md`, `.codex/`, project configuration, project trust, prompts, rules,
  hooks, plugins, skills, subagents, or MCP servers;
- npm configuration, npm credentials, npm cache, or unrelated global packages;
- `/etc/codex/config.toml`, `/etc/codex/requirements.toml`, or any other Codex
  system policy file.

Existing user or organization policy under `/etc/codex` remains external and is
never adopted.

## 6. Marker state

The marker path is:

```
$ATLAS_STATE_DIR/installed/development-codex
```

The parent directory is mode `700`; the marker is mode `600` and written
atomically. The marker records:

```
schema=1
state=installing|installed
package_source=npm
package=@openai/codex
npm_prefix=/usr/local
depends=development/node
```

Malformed, unreadable, mode-insecure, unknown-key, or inconsistent markers are
broken managed state and fail verification. An `installing` marker means Atlas
started but did not complete installation; `install` may reconcile it, but
`verify` must fail until the marker is promoted to `installed`.

There is no `detached` marker state. `remove` deletes only Atlas-owned Codex
installation files that still match the managed package boundary and the marker.
It never touches user Codex state.

## 7. Lifecycle contract

### 7.1 `check`

`check` returns `0` only when the marker is valid, state is `installed`, the
npm package is present under the fixed prefix, and the trusted command probe
passes.

### 7.2 `install`

`install` is idempotent and follows this order:

1. Require Fedora before any mutation.
2. Validate any existing marker.
3. Validate the fixed `/usr/bin/npm` dependency boundary.
5. Refuse unsafe fixed-path conflicts before mutation:
   - `/usr/local/bin/codex` exists without an Atlas marker;
   - `/usr/local/lib/node_modules/@openai/codex` exists without an Atlas marker;
   - `/usr/local/bin/codex` exists but is not executable or does not resolve
     under the managed package directory.
6. Write an `installing` marker atomically.
7. Run `/usr/bin/npm install -g @openai/codex --prefix /usr/local --no-audit --no-fund`.
8. Validate package presence, trusted command probe, and marker.
9. Promote the marker atomically to `installed`.

### 7.3 `verify` and `doctor`

With no marker, `verify` returns `0`. It logs whether Codex appears absent or
present but unmanaged.

With a valid `installed` marker, `verify` fails only when Atlas-managed expected
state is broken: npm dependency missing, managed package missing, trusted
command missing, command not package-owned, non-runnable command, or invalid
marker.

With an `installing` marker, `verify` fails and tells the user to rerun install.

The current runner dispatches `atlas doctor` to `module::verify`; RFC-0026
preserves that contract. Atlas does not run interactive Codex commands because
they may read authentication, project, memory, network, or user configuration
state outside Atlas's ownership boundary.

### 7.4 `update`

`update` runs the same fixed-prefix npm package installation command used by
`install`. It does not run Codex interactive update flows.

### 7.5 `remove`

`remove` removes the Atlas-owned npm package with fixed-prefix npm only when the
marker is valid and the command/package boundary still matches the managed
package. It then removes the marker. It never touches `~/.codex`, project state,
MCP, skills, plugins, memory, prompts, authentication, or `/etc/codex`.

If the managed package boundary drifted, `remove` refuses rather than guessing.

### 7.6 `backup` and `restore`

`backup` and `restore` are documented no-op hooks returning `0`.

The CLI installation is reconstructable from npm. User Codex state contains
credentials, sessions, projects, prompts, memory, MCP configuration, and
conversations, all of which are user-owned and must not be copied by Atlas.

## 8. Security considerations

- Atlas does not execute the curl-piped installer.
- Atlas uses the fixed `/usr/bin/npm` installed by `development/node`.
- Atlas uses a fixed npm prefix and fixed Codex command path.
- The fixed command probe ignores `PATH` shims and Codex/OpenAI/npm
  environment variables.
- Atlas refuses unmanaged fixed-path Codex files before mutation.
- Atlas does not read, write, back up, restore, or log credentials.
- Atlas does not run interactive Codex commands, login, cloud, MCP, plugin,
  skill, memory, or project commands.
- Atlas does not write `/etc/codex` because that global configuration would
  affect user-owned Codex installations.
- Existing organization policy files are not adopted or overwritten.

## 9. Testing and validation matrix

Unit tests must cover:

- no-marker verify success when Codex is absent;
- no-marker verify success when Codex is present but unmanaged;
- malformed, insecure, unknown-key, hash-mismatch, and installing markers;
- non-Fedora install refusal before mutation;
- unmanaged command/package refusal before mutation;
- fixed `/usr/bin/npm` executable and RPM ownership preflight;
- marker written before npm mutation;
- exact npm install command;
- promotion only after validation;
- npm failure leaves `installing`;
- verify failures for missing npm, missing package, missing command, wrong
  package ownership, and command failure;
- update refreshes the npm package;
- remove deletes only Atlas-owned package/marker and never touches user Codex
  state;
- backup/restore no-ops;
- runner status and doctor contracts.

Fedora acceptance tests:

```
atlas install development/codex
/usr/local/bin/codex --version
atlas verify development/codex
atlas doctor development/codex
atlas status development/codex
atlas install development/codex
```

The second install must perform no work. If a user-owned `codex` appears earlier
on `PATH`, that remains user-owned; Atlas validation uses the fixed system path.

## 10. Architecture review notes

- **Ownership boundary.** The fixed npm prefix is the only package boundary
  Atlas can reasonably own for Codex on Fedora today. User-local Codex installs
  remain unmanaged.
- **Configuration boundary.** Atlas intentionally writes no active Codex
  runtime configuration. `/etc/codex` is global across local clients and could
  alter existing user-owned Codex installations, including skills and plugins.
- **Supply chain.** npm is weaker than a signed Fedora RPM or vendor-signed DNF
  repository. This is accepted because OpenAI documents `@openai/codex` as an
  official installation method and because Atlas refuses to execute remote
  installer scripts. Future OpenAI RPM support should supersede this module
  design.
- **Security.** Atlas uses Codex requirements only for a narrow managed runtime
  baseline and never for personalization. Authentication and project trust stay
  user-owned.
- **Idempotency.** Marker validation and fixed-path preflights make repeated
  install/verify/update/remove deterministic.
- **No engine changes.** The existing module contract is sufficient.
