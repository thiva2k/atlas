# RFC-0027: Atlas Self-Management

| | |
|---|---|
| **Status** | Accepted |
| **Created** | 2026-07-12 |
| **Requires engine change** | Yes |
| **Supersedes** | None |

---

## 1. Summary

Atlas needs a first-class way to update Atlas itself without weakening the
module ownership model. The canonical operator interface is:

```
atlas self-update
```

The current engine cannot provide this command through a module-local change:

- `atlas self-update` is not a supported platform verb;
- `atlas update atlas` is intentionally rejected because `update` is a module
  lifecycle verb and self-update is an engine lifecycle verb;
- `atlas update core/atlas` is intentionally rejected because it would expose
  Atlas self-updates as just another workstation dependency and require a module
  namespace special case.

Therefore Atlas self-management requires an engine-level implementation, but it
must preserve the module lifecycle contract unchanged.

## 2. Goals

- Provide an explicit self-update command for Atlas.
- Preserve marker-based ownership.
- Avoid adopting arbitrary Git working trees.
- Avoid silently overwriting local changes.
- Keep the implementation pure Bash with zero runtime dependencies beyond tools
  Atlas already requires for source-controlled operation.
- Make self-update idempotent and auditable.
- Keep normal module lifecycle contracts unchanged.
- Establish a future `atlas self-*` namespace for Atlas engine lifecycle
  operations.

## 3. Non-goals

- Managing user dotfiles or project repositories.
- Replacing Git as the source transport.
- Adding an auto-update daemon or background updater.
- Updating Atlas during every `atlas install`.
- Resolving local merge conflicts automatically.
- Force-resetting a dirty working tree.
- Managing authentication to the Git remote.
- Supporting `atlas update atlas`.
- Supporting `atlas update core/atlas`.

## 4. Ownership model

Atlas may only self-manage a checkout that it explicitly owns.

Atlas owns:

- the Atlas installation marker;
- the configured Atlas source directory when the marker records that Atlas
  created or adopted it explicitly;
- the managed executable or launcher path recorded in the marker;
- the selected update channel or remote/ref recorded in the marker;
- an optional managed launcher/symlink if such behavior is approved.

Atlas does not own:

- arbitrary local clones of the Atlas repository;
- user branches;
- uncommitted work;
- Git credentials;
- forks/remotes not recorded in the marker;
- shell startup files;
- package-manager state outside the approved install boundary.

No marker means Atlas must not mutate the current repository as owned state.

## 5. Proposed command contract

Canonical operator command:

```
atlas self-update
```

Explicitly unsupported:

```
atlas update atlas
```

`atlas self-update` is a platform verb because it updates the Atlas engine, not a
workstation capability module. `atlas update atlas` must not be implemented,
because `update` is a module lifecycle verb. Keeping those concepts separate
preserves the architecture and avoids a special case in module resolution.

This RFC also reserves a future Atlas self-management namespace:

```
atlas self-update
atlas self-version
atlas self-verify
```

Only `atlas self-update` is in scope for this RFC. `self-version` and
`self-verify` are reserved for future RFCs or implementation phases.

## 6. Engine changes required

This RFC requires changes to the CLI/runner layer:

1. Add `self-update` to the top-level command parser.
2. Add help text for `atlas self-update`.
3. Add a dedicated self-management implementation path.
4. Keep `module::discover` and normal module lifecycle resolution unchanged.
5. Add tests proving that `atlas update atlas` is rejected as normal module
   resolution, not treated as an alias.
6. Add tests proving that `atlas update core/atlas` is not required for the
   self-update command to work.

The engine must not special-case a normal module in a way that weakens the
module contract.

## 7. Lifecycle and safety contract

`atlas self-update` must:

1. Verify the current Atlas checkout is an explicitly managed checkout.
2. Verify the current Atlas executable resolves to the managed executable or
   launcher recorded in the marker.
3. Verify the current Git remote exactly matches the recorded remote identity
   before mutation.
4. Verify the current branch exactly matches the recorded branch before
   mutation.
5. Refuse to run when the working tree has uncommitted changes, unless a future
   RFC defines a safe stash/restore policy.
6. Refuse detached HEAD unless explicitly recorded in the marker.
7. Fetch from the recorded remote.
8. Verify fast-forward is possible before applying the update.
9. Fast-forward only.
10. Refuse merge commits, rebases, force resets, and conflict resolution.
11. Re-run post-update validation:
   - `bash -n atlas`;
   - `bash -n` over `internal/*.sh` and module scripts;
   - `atlas version`;
   - `atlas help`;
   - `atlas status`.
12. Run the full test suite only when explicitly requested with:
   - `atlas self-update --verify`; or
   - `atlas self-update --full-test`.
13. Leave the previous checkout untouched if preflight fails.

The managed-state check is intentionally strict. A typical accepted state is:

```
remote=github.com/thiva2k/atlas
branch=main
executable=<managed executable or launcher path>
working_tree=clean
fast_forward=possible
```

If any check fails, Atlas must stop with:

```
Refusing self-update.
Repository is not in managed state.
```

If the current executable does not match the marker, Atlas must stop with:

```
Refusing self-update.
Current Atlas executable does not match the managed installation.
```

No guessing. No recovery. Fail closed.

If Atlas is installed from a release artifact rather than a Git checkout, this
RFC must be amended or superseded with an artifact update strategy before
implementation.

## 8. Marker contract

The self-management marker should record at minimum:

```
schema=1
state=installed
source=git
path=<absolute Atlas root>
remote=<remote name or URL>
remote_identity=github.com/thiva2k/atlas
branch=main
ref=<branch policy>
launcher=<optional managed launcher path>
executable=<managed executable or launcher path>
```

The marker must be mode `600`; its parent directory must be mode `700`.
Malformed or inconsistent markers fail closed.

## 9. Security considerations

- Self-update is code update. It must be explicit, never automatic.
- Atlas must not execute remote installer scripts.
- Atlas must not force-reset local work.
- Atlas must not log credentials embedded in remote URLs.
- Atlas must not bypass Git's configured transport/authentication.
- Fast-forward-only updates reduce the chance of surprising local history
  changes.
- Exact remote and branch matching prevents Atlas from updating an unintended
  fork, feature branch, or local experiment.
- Exact executable matching prevents Atlas from updating one checkout while the
  user is accidentally running another Atlas binary or launcher.
- The implementation must avoid `eval`, unchecked `mktemp`, and unsafe temporary
  paths.

## 10. Testing strategy

Tests must cover:

- unmanaged checkout refuses mutation;
- managed clean checkout fast-forwards;
- dirty checkout refuses before fetch/apply;
- detached HEAD refuses;
- current executable mismatch refuses before fetch/apply;
- mismatched remote refuses before fetch/apply;
- mismatched branch refuses before fetch/apply;
- remote URL with credentials is redacted in logs;
- non-fast-forward update refuses;
- syntax validation failure after update is detected;
- `atlas version`, `atlas help`, and `atlas status` run after update;
- `atlas self-update --verify` runs the full suite;
- `atlas self-update --full-test` runs the full suite;
- `atlas self-update` command dispatch;
- `atlas update atlas` is rejected and does not dispatch self-update;
- normal module resolution remains unchanged.

## 11. Decision required

Accepted decisions:

1. The only public command is `atlas self-update`.
2. `atlas update atlas` must not be implemented.
3. `atlas self-update` belongs to an engine self-management namespace, separate
   from module lifecycle verbs.
4. The update must verify exact recorded remote, exact recorded branch, clean
   working tree, current executable identity, and fast-forward possibility
   before mutation.
5. Default post-update validation runs syntax checks plus `atlas version`,
   `atlas help`, and `atlas status`.
6. The full test suite is optional via `atlas self-update --verify` or
   `atlas self-update --full-test`.

Remaining implementation detail:

- Define the explicit adoption/install action that creates the self-management
  marker for an Atlas checkout.
