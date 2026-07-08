#!/usr/bin/env bash
MODULE_NAME="brave"
MODULE_DESCRIPTION="Brave browser: installs Brave via its official repository."
MODULE_DEPENDS=()

module::check()   { return 1; }
module::install() { not_implemented "brave install"; }
module::verify()  { not_implemented "brave verify"; }
