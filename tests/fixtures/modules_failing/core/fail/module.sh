#!/usr/bin/env bash
MODULE_NAME="fail"
MODULE_DESCRIPTION="fixture whose install hook fails"
MODULE_DEPENDS=()
module::check()   { return 1; }
module::install() { log::error "deliberate failure"; return 1; }
module::verify()  { not_implemented "fail verify"; }
