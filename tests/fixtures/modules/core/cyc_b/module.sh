#!/usr/bin/env bash
MODULE_NAME="cyc_b"
MODULE_DESCRIPTION="cycle fixture b"
MODULE_DEPENDS=("core/cyc_a")
module::check()   { return 1; }
module::install() { not_implemented "cyc_b"; }
module::verify()  { not_implemented "cyc_b"; }
