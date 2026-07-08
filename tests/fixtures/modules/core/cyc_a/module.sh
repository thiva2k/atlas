#!/usr/bin/env bash
MODULE_NAME="cyc_a"
MODULE_DESCRIPTION="cycle fixture a"
MODULE_DEPENDS=("core/cyc_b")
module::check()   { return 1; }
module::install() { not_implemented "cyc_a"; }
module::verify()  { not_implemented "cyc_a"; }
