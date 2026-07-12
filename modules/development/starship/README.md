# development/starship

`development/starship` installs Atlas's engineering-focused Starship prompt
configuration.

Atlas writes only:

- `$ATLAS_CONFIG_HOME/starship/starship.toml`
- `$ATLAS_STATE_DIR/installed/development-starship`

Atlas never writes `~/.config/starship.toml`, shell startup files, Fish config,
Bash config, Zsh config, or Starship cache files. User prompt configuration and
shell activation remain user-owned or owned by future shell modules.

The managed config is intentionally minimal. It displays directory, Git branch,
Git status, Python, Node, Docker context, command duration, time, and the prompt
character. It avoids `$all`, custom command modules, emoji, and decorative
segments.

If a `starship` binary already exists, install and verify validate the Atlas
config with `STARSHIP_CONFIG` pointed at the managed file. If Starship is absent,
the module still succeeds because binary installation is outside this RFC.

`remove` deletes only the Atlas-owned config when it still matches Atlas source,
then writes a detached marker. It refuses drifted config to avoid destroying
possible user edits.

`backup` and `restore` are documented no-ops because the config is
reconstructable from the repository.
