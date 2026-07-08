#!/usr/bin/env bash
MODULE_NAME="git"
MODULE_DESCRIPTION="Distributed version control: installs git and applies global config."
MODULE_DEPENDS=()

module::check()   { return 1; }               # TODO: os::has_cmd git && gitconfig applied
module::install() { not_implemented "git: dnf install git + apply config/gitconfig.template"; }
module::verify()  { not_implemented "git: git --version and config sanity"; }
