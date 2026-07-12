# ghostty

**What it does:** Installs Ghostty as Atlas's reference developer terminal on
Fedora, then applies Atlas-owned Ghostty defaults.

**Installs / configures:**

- Fedora COPR repository `scottames/ghostty`
- `ghostty` package
- `$XDG_CONFIG_HOME/ghostty/config.ghostty` when Atlas can create it safely
- `$XDG_CONFIG_HOME/ghostty/themes/atlas-reference`
- Atlas install marker under `$ATLAS_STATE_DIR/installed/development-ghostty`

**Depends on:** nothing.

Atlas owns only the marker, the COPR/package intent it records, and the
Ghostty config/theme files it creates. It does not adopt an existing
`config.ghostty` or unmanaged Ghostty installation.

Put user-specific Ghostty settings in:

```text
$XDG_CONFIG_HOME/ghostty/user.ghostty
```

Atlas never creates, edits, deletes, verifies, backs up, or restores that file.
Because Ghostty processes `config-file` after the containing file, settings in
`user.ghostty` override Atlas defaults.

Atlas references developer font family names only. Font installation remains
owned by `desktop/fonts`. Shell integration uses Ghostty's built-in integration;
Atlas does not edit Fish, Zsh, Bash, Starship, or shell startup files.

The Atlas-managed defaults intentionally bias toward engineering work: modest
padding, a slightly taller cell height, disabled programming ligatures for
unambiguous code reading, a non-blinking bar cursor, bounded scrollback, inherited
working directories for new terminal surfaces, and a dark Atlas-blue theme with
no transparency or blur. Put personal changes in `user.ghostty`; that include
stays last so user overrides win.

`update` refreshes Atlas-owned Ghostty config/theme files. `remove` detaches
Atlas by deleting only unchanged Atlas-owned files and writing a detached
marker; it does not uninstall Ghostty or remove the COPR repo. `backup` and
`restore` are documented no-ops because Atlas-owned state is reconstructable and
user terminal customization is user-owned.
