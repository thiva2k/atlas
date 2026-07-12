# fonts

**What it does:** Installs the Atlas typography foundation for the experience
layer.

**Installs / configures:**

- `JetBrainsMono Nerd Font` from pinned Nerd Fonts release `v3.4.0`
- `Inter` from Fedora package `rsms-inter-fonts`
- Font cache refresh for the Atlas-owned font directory
- Atlas install marker under `$ATLAS_STATE_DIR/installed/desktop-fonts`

**Depends on:** nothing.

Atlas owns only:

- `$XDG_DATA_HOME/fonts/atlas/JetBrainsMonoNerdFont`
- the package intent for `rsms-inter-fonts`
- its install marker

Atlas never owns user-installed fonts, fontconfig preferences, KDE font
settings, application font settings, or user font directories.

The Nerd Font asset is installed in user font space so Atlas can remove only
what it created. `remove` deletes that Atlas-owned directory and leaves Fedora
packages and user preferences untouched. `backup` and `restore` are documented
no-ops because the managed font state is reconstructable.
