#!/usr/bin/env bash
MODULE_NAME="needy"
MODULE_DESCRIPTION="fixture that declares a nonexistent dependency"
MODULE_DEPENDS=("core/ghost")
module::check()   { return 1; }
module::install() { not_implemented "needy install"; }
module::verify()  { not_implemented "needy verify"; }
