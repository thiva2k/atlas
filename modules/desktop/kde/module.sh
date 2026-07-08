#!/usr/bin/env bash
MODULE_NAME="kde"
MODULE_DESCRIPTION="KDE Plasma: installs and configures the KDE Plasma desktop."
MODULE_DEPENDS=()

module::check()   { return 1; }
module::install() { not_implemented "kde install"; }
module::verify()  { not_implemented "kde verify"; }
