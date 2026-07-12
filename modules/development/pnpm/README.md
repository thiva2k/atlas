# development/pnpm

Installs and verifies Fedora's `pnpm` package.

Atlas owns only:

- Fedora package intent for `pnpm`;
- the fixed managed command probe at `/usr/bin/pnpm`;
- the Atlas install marker.

Atlas does not own:

- `node_modules`;
- `pnpm-lock.yaml`, `package.json`, workspaces, or project scripts;
- the pnpm store or cache;
- global pnpm packages;
- pnpm, npm, registry, TLS, or credential configuration;
- Corepack state or shims;
- shell completions or shell startup files.

## Lifecycle

- `check` succeeds only when Atlas has an installed marker and `/usr/bin/pnpm`
  is healthy.
- `install` requires Fedora, writes an `installing` marker, installs Fedora's
  `pnpm` package, validates `/usr/bin/pnpm`, then promotes the marker.
- `verify` succeeds on never-installed or unmanaged systems and fails only for
  broken Atlas-managed state.
- `update`, `backup`, and `restore` are documented no-ops.
- `remove` deletes only the Atlas marker and never uninstalls Fedora packages or
  touches user project/package-manager state.

## Dependency

`development/pnpm` depends on `development/node`.

Node.js provides the runtime foundation. pnpm is intentionally separate so the
Node module stays a runtime module and never becomes responsible for project
package management.

See `docs/rfcs/RFC-0015-pnpm-module.md`.
