#!/usr/bin/env bash
MODULE_NAME="codex"
MODULE_DESCRIPTION="Codex CLI: installs the CLI and restores its configuration."
MODULE_DEPENDS=()

module::check()   { return 1; }
module::install() { not_implemented "codex install"; }
module::verify()  { not_implemented "codex verify"; }
