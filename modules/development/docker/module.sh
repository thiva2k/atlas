#!/usr/bin/env bash
MODULE_NAME="docker"
MODULE_DESCRIPTION="Container runtime: installs Docker Engine and enables the service."
MODULE_DEPENDS=()

module::check()   { return 1; }
module::install() { not_implemented "docker install"; }
module::verify()  { not_implemented "docker verify"; }
