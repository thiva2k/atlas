# desktop/wallpapers

Installs a curated Atlas SVG wallpaper collection into
`$XDG_DATA_HOME/backgrounds/atlas`.

Atlas owns the `*.svg` files in that directory and the install marker. The
directory is shared with other modules, so files that are not SVGs stay put.
Install refuses when an SVG is already there without a marker. Remove deletes
only unchanged Atlas SVGs, and removes the directory only when it is left empty.

Atlas never changes the active wallpaper and never touches user wallpaper
settings.
