# node

**What it does:** Installs Fedora's Node.js 24 LTS runtime and Fedora-provided
npm packages, then records Atlas ownership with a marker.

**Installs / verifies:**

- `nodejs24`
- `nodejs24-bin`
- `nodejs24-npm`
- `nodejs24-npm-bin`
- `/usr/bin/node`
- `/usr/bin/npm`

**Depends on:** nothing.

Atlas owns only Fedora package intent and its install marker. Existing Node.js
or npm installations are valid user-owned state until `atlas install
development/node` writes the marker.

Atlas never manages:

- pnpm
- bun
- yarn
- corepack
- nvm
- fnm
- Volta
- asdf
- Deno
- global npm packages
- npm configuration
- npm credentials
- npm cache
- `node_modules`
- `package.json`
- lockfiles
- project scripts
- shell completions

Verification uses fixed system paths, not `PATH`, so version managers, project
shims, and user-local wrappers do not affect Atlas's managed-runtime decision.

`update`, `backup`, and `restore` are documented no-ops. Package currency is
handled by Fedora updates, and npm/project state is user-owned.

The `remove` hook deletes only the Atlas marker. It never uninstalls Node.js or
npm.
