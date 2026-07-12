# fish

**What it does:** Installs Fedora's Fish shell package and writes one
Atlas-owned Fish snippet.

**Installs / verifies:**

- `fish`
- `/usr/bin/fish`
- `${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/00-atlas.fish`

**Depends on:** nothing.

Atlas owns only Fedora package intent, the install marker, and the isolated
`00-atlas.fish` snippet it creates. Existing Fish installations are valid
user-owned state until `atlas install development/fish` writes the marker.

Atlas never manages:

- login shell state
- `/etc/shells`
- terminal profiles
- `config.fish`
- aliases
- functions
- completions
- plugins
- abbreviations
- universal variables
- command history
- Starship prompt configuration

The Atlas snippet only sets:

```fish
set -gx ATLAS_SHELL fish
```

`update` restores the Atlas snippet if it drifts. `backup` and `restore` are
documented no-ops. The `remove` hook deletes only the Atlas snippet and marker,
and refuses to delete the snippet if it has been modified.
