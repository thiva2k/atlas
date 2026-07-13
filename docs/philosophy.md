# Philosophy of Atlas

Atlas is a workstation lifecycle manager, not an install script.

The difference matters. An install script tries to make the current command
finish. A lifecycle manager has to remain correct after repeated installs,
updates, verification, backups, restores, partial failures, user edits, and
future modules.

## Atlas owns only what Atlas creates

Atlas never infers ownership from existence.

A package can exist because Fedora installed it. A config file can exist because
the user wrote it. A Docker volume can exist because a project created it. None
of that belongs to Atlas merely because Atlas can see it.

Ownership is recorded in Atlas-managed state. Without a marker or an explicit
documented adoption path, Atlas owns nothing.

## A fresh Fedora machine is valid state

`verify` is not an install command in disguise. It succeeds when:

- Atlas-managed state is healthy; or
- Atlas has never installed that module.

It fails only when Atlas owns the module and the managed state is broken. This
keeps diagnostics honest and makes pre-install validation useful.

## Idempotency is a product requirement

`atlasctl install` must be safe to run repeatedly. The second run should do no
unintended work.

This property is not convenience; it is how Atlas becomes reliable on real
machines. Users should not need to remember whether a previous run completed,
partially failed, or was interrupted.

## Security beats convenience

Atlas refuses unsafe states instead of silently repairing systems it does not
own. Examples:

- it does not add users to Docker's privileged group for convenience;
- it does not prompt for or store API keys;
- it does not trust user-owned secret files with unsafe permissions;
- it does not overwrite user configuration without validation and ownership.

When security and convenience disagree, Atlas chooses the safer default and
prints an actionable diagnostic.

## The user always wins

Atlas provides defaults, not domination. Where a tool supports layered
configuration, Atlas writes an isolated managed fragment and lets user-owned
configuration override it.

Where safe layering is impossible, a module must define the ownership boundary
in an RFC and refuse ambiguous states.

## Modules are the unit of change

Every capability lives under `modules/<category>/<name>/` and implements the
same lifecycle hooks. The engine discovers modules and calls the contract; it
does not know module internals.

This keeps Atlas scalable. Adding Python, Docker, Ghostty, or a future module
should not require new runner behavior.

## Bash is a constraint, not an accident

Atlas runs on a fresh Fedora workstation before the development environment
exists. That means no Python framework, no Ansible, no YAML parser, no `jq`, and
no language-specific runtime.

The trade-off is discipline: explicit error handling, quoting, temporary-file
safety, secret discipline, and tests for every production bug.

## Documentation is part of the system

An undocumented module is not done. The RFC explains the design, the module
README explains the behavior, tests encode the contract, and the code implements
only what the architecture permits.
