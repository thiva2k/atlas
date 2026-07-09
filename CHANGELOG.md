# Changelog

All notable changes to Atlas are documented here. Format loosely follows
[Keep a Changelog]; Atlas uses semantic versioning once it hits 1.0.

## [Unreleased]

### Added
- v1 skeleton: architecture, `atlas` CLI, module runner, and the `internal/`
  engine (logging, errors, OS helpers, module contract, dependency resolution).
- Eight placeholder modules across core / development / apps / desktop.
- Zero-dependency `bootstrap.sh`.
- Pure-Bash test harness under `tests/`.

### Fixed
- **git: Atlas defaults no longer override your own git settings.** The managed
  config was wired into `~/.gitconfig` with `git config --add`, which appends —
  and because git resolves configuration positionally, the Atlas fragment was
  read last and won. Installing Atlas would silently flip a hand-set
  `pull.rebase = false` to `true`. The include block is now prepended, so
  anything you set below it wins, as `RFC-0001` §4.4 always intended. An
  existing bottom-placed include is relocated on the next `atlas install git`.
  The rewrite is a single atomic write, preserves the file's mode, follows a
  symlinked `~/.gitconfig` to its target, and refuses to touch a config that is
  locked, unwritable, not a regular file, or unparseable — always before
  modifying anything.
- **git: `atlas verify git` no longer reports a healthy module as broken** when
  you override one of Atlas's managed defaults. It now checks that the managed
  fragment *resolves*, not that Atlas's value is the winning one — which, after
  the fix above, it deliberately is not.

[Keep a Changelog]: https://keepachangelog.com/
