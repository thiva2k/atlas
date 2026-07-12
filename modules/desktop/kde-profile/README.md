# desktop/kde-profile

`desktop/kde-profile` applies Atlas's conservative KDE workstation profile.

Atlas owns only the KConfig keys listed in `profile.tsv`, and only after Atlas
creates them and writes the install marker:

```text
$ATLAS_STATE_DIR/installed/desktop-kde-profile
```

The module refuses first install if any managed key already exists. It does not
adopt user KDE settings, panel layouts, shortcuts, themes, wallpapers, lock
screen settings, SDDM, notifications, or power profiles.

The initial profile reduces animation duration, keeps focus behavior
predictable, and disables latency-heavy or novelty KWin effects such as blur,
wobbly windows, magic lamp, sliding popups, and squash.

`verify` succeeds before install and after detach. When installed, it fails if a
managed key is missing or drifted.

`remove` deletes only managed keys that still match Atlas source. It refuses
drifted keys so user edits are not destroyed.

`backup` and `restore` are documented no-ops because the managed profile is
reconstructable and user KDE configuration is outside this module.
