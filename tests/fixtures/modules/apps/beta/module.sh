#!/usr/bin/env bash
MODULE_NAME="beta"
MODULE_DESCRIPTION="fixture module beta (depends on alpha)"
MODULE_DEPENDS=("core/alpha")
module::check()   { return 1; }
module::install() { not_implemented "beta install"; }
module::verify()  { not_implemented "beta verify"; }
