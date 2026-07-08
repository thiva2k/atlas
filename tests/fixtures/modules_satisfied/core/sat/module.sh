#!/usr/bin/env bash
MODULE_NAME="sat"
MODULE_DESCRIPTION="fixture whose check passes"
MODULE_DEPENDS=()
module::check()   { return 0; }
module::install() { not_implemented "sat install"; }
module::verify()  { not_implemented "sat verify"; }
