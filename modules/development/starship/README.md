# development/starship

`development/starship` installs Atlas's engineering-focused Starship prompt
configuration and can activate it in interactive fish.

Install writes only:

- `$ATLAS_CONFIG_HOME/starship/starship.toml`
- `$ATLAS_STATE_DIR/installed/development-starship`

Install never writes `~/.config/starship.toml`, shell startup files, or Starship
cache files, and it does not install the `starship` binary. `atlas activate
development/starship` writes
`${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d/10-atlas-starship.fish` and
`$ATLAS_STATE_DIR/activated/development-starship`. A file already at the snippet
path is recorded and restored by `deactivate`. Bash, Zsh, and `config.fish`
stay untouched.

The managed config is intentionally minimal. It displays directory, Git branch,
Git status, Python, Node, Docker context, command duration, time, and the prompt
character. It avoids `$all`, custom command modules, emoji, and decorative
segments.

If a `starship` binary already exists, install and verify validate the Atlas
config with `STARSHIP_CONFIG` pointed at the managed file. If Starship is absent,
install and verify still succeed; this module does not install the binary.
Activate requires `starship` on `PATH`.

`remove` deletes only the Atlas-owned config when it still matches Atlas source,
then writes a detached marker. It refuses drifted config to avoid destroying
possible user edits. It does not remove an active fish snippet; `atlas deactivate
development/starship` does that.

`backup` and `restore` are documented no-ops because the config is
reconstructable from the repository.
