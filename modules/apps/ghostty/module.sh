#!/usr/bin/env bash
MODULE_NAME="ghostty"
MODULE_DESCRIPTION="Ghostty terminal: installs the Ghostty terminal emulator."
MODULE_DEPENDS=()

module::check()   { return 1; }
module::install() { not_implemented "ghostty install"; }
module::verify()  { not_implemented "ghostty verify"; }
