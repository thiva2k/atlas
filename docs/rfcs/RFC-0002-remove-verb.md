# RFC-0002: Platform verb `remove`

| | |
|---|---|
| **Status** | Proposed |
| **Author** | Claude Code (for thiva2k) |
| **Created** | 2026-07-09 |
| **Depends on** | RFC-0001 (whose `module::remove` is the first implementation) |

---

## 1. Problem

`docs/architecture.md` §3 defines `remove` as an optional **module hook** —
"Cleanly remove it" — but its **platform verb** list omits it:

```
atlas install    atlas update    atlas verify    atlas backup
atlas restore    atlas doctor    atlas status
```

`_runner_hooks_for_verb` in `internal/runner.sh` has no `remove` case, so
`atlas remove core/git` exits `2` (unknown command). Every other optional hook
(`update`, `backup`, `restore`) has a verb; `remove` alone does not.

This went unnoticed while every module was a placeholder. The Git module
(RFC-0001) now implements and tests `module::remove`, so the hook exists, is
correct, and cannot be invoked. §3's own claim — "a platform verb is nothing more
than the runner fanning that verb out across the selected modules" — means a hook
with no verb is unreachable by construction.

## 2. Why this needs its own RFC

`remove` would be Atlas's **first destructive verb**, and the runner's current
fan-out defaults are all wrong for it:

1. **Bare invocation.** `runner::run` fans an argument-less verb across *every*
   discovered module. `atlas remove` would tear down the entire workstation.
2. **Dependency order.** `module::resolve_order` emits dependency-first order, so
   `install` builds foundations before dependents. Teardown is the mirror image:
   removing `core/git` before a module that layers config on top of Git operates
   on a half-dismantled substrate.
3. **Missing hooks.** A module with no `remove` hook is currently a silent
   `log::debug` skip counted as "ok" — which would tell the user something was
   removed when nothing was.

None of these are mechanical. Per `docs/rfcs/README.md`, a change to the engine,
the module contract, or the frozen architecture starts as an RFC written *before*
the code — which is exactly why this is a stub and not a patch smuggled into
RFC-0001's branch.

## 3. Questions this RFC must answer

- Does `atlas remove` with no module ids **refuse** (exit `2`)? (Atlas must run
  unattended, so an interactive confirmation prompt is not available.)
- Does the runner **reverse** the topological order for `remove`?
- Does removing a module that another *installed* module depends on refuse with
  exit `3`, the way `dnf` refuses?
- Does a module lacking a `remove` hook emit a visible `__SKIP__` + info line
  rather than counting as `ok`?
- Is a `--dry-run` flag in scope, or a separate cross-cutting concern?
- Is `remove` the right name, or `uninstall`?

## 4. Non-goals

- Changing `module::remove`'s hook contract. RFC-0001's implementation
  (idempotent, logs what it changes, never widens blast radius beyond
  Atlas-owned state) is the precedent and stands.
- Removing packages. `remove` reverts *Atlas's* changes; uninstalling shared
  system packages is out of scope, as RFC-0001 §4.7 already establishes.
