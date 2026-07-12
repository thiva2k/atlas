# codex

**What it does:** Installs OpenAI's Codex CLI from the official npm package.

**Installs / configures:** `@openai/codex` under the fixed npm prefix
`/usr/local`, with the managed command at `/usr/local/bin/codex`.

**Depends on:** `development/node`.

**Ownership boundary:** Atlas owns only the fixed npm package boundary and the
Atlas marker. It does not own authentication, API keys, conversations, project
state, prompts, user configuration, MCP servers, skills, plugins, memory, or
system Codex policy.

Existing user-owned Codex installations, including `~/.local/bin/codex` and
`~/.codex`, remain unmanaged. `verify` succeeds when Codex is unmanaged and
reports that state explicitly.
