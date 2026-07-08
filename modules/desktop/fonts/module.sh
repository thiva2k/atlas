#!/usr/bin/env bash
MODULE_NAME="fonts"
MODULE_DESCRIPTION="Developer fonts: installs Nerd Fonts and common typefaces."
MODULE_DEPENDS=()

module::check()   { return 1; }
module::install() { not_implemented "fonts install"; }
module::verify()  { not_implemented "fonts verify"; }
