# fastfetch

**What it does:** Installs Fastfetch and provides the Atlas workstation identity
layout.

**Installs / configures:**

- Fedora package `fastfetch`
- Atlas-owned system config `/etc/xdg/fastfetch/config.jsonc`
- Atlas install marker under `$ATLAS_STATE_DIR/installed/desktop-fastfetch`

**Depends on:** nothing.

Atlas owns only the system default Fastfetch config it creates. It never edits,
deletes, reads, or verifies user Fastfetch configuration under
`$XDG_CONFIG_HOME/fastfetch`.

If a user config exists, Fastfetch may prefer it over the Atlas system default.
That is intentional: the user always wins.

The Atlas layout is intentionally small and engineering-focused. It avoids large
decorative logos and novelty modules.

`update` refreshes the Atlas config from the repository. `remove` deletes only
the Atlas system config when it still matches source and leaves the `fastfetch`
package installed. `backup` and `restore` are documented no-ops.
