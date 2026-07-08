#!/usr/bin/env bash
MODULE_NAME="claude"
MODULE_DESCRIPTION="Claude Code CLI: installs the CLI and restores its configuration."
MODULE_DEPENDS=()

module::check()   { return 1; }
module::install() { not_implemented "claude install"; }
module::verify()  { not_implemented "claude verify"; }
