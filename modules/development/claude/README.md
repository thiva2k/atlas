# claude

**What it does:** Installs Anthropic's signed Fedora/RHEL RPM package for
Claude Code and records Atlas ownership with a marker.

**Installs / configures:** the `claude-code` package from Anthropic's stable RPM
repository, the Atlas-owned repository file, the bundled RPM signing key, one
managed-settings drop-in that disables background self-updates, and the Atlas
install marker.

**Depends on:** nothing.

## Ownership

Atlas owns only:

- package intent for `claude-code`;
- `/etc/yum.repos.d/claude-code.repo`;
- `/etc/claude-code/managed-settings.d/00-atlas.json`;
- the bundled signing-key source in this module;
- the install marker under Atlas state.

Atlas never owns Claude authentication, API keys, OAuth sessions, MCP servers,
`~/.claude`, `~/.claude.json`, project `.claude/` directories, `CLAUDE.md`,
conversation history, hooks, skills, subagents, or user personalization.

## Lifecycle

`install` validates Fedora, the bundled key hash/fingerprint, repository source,
managed-settings source, fixed CLI path ownership, and unmanaged path conflicts
before mutating state. It then writes an `installing` marker, imports only the
bundled key, writes Atlas-owned files, installs `claude-code`, validates the
trusted `/usr/bin/claude --version` probe, and promotes the marker to
`installed`.

`verify` succeeds when Claude Code has never been installed by Atlas. If Claude
Code is present without an Atlas marker, it is reported as user-owned unmanaged
state. With a marker, `verify` fails only when Atlas-managed state is broken.

`remove` deletes only the Atlas-owned repository file, managed-settings drop-in,
and marker when they still match Atlas source. It never uninstalls the package
and never touches user Claude state.

`backup` and `restore` are documented no-ops because the CLI installation is
reconstructable and user Claude state is outside Atlas ownership.
