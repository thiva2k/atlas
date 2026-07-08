#!/usr/bin/env bash
MODULE_NAME="alpha"
MODULE_DESCRIPTION="fixture module alpha"
MODULE_DEPENDS=()
module::check()   { return 1; }
module::install() { not_implemented "alpha install"; }
module::verify()  { not_implemented "alpha verify"; }
