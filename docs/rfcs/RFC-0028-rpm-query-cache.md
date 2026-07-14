# RFC-0028: RPM Query Cache

Status: Accepted

Date: 2026-07-13

> Revision 2 (2026-07-13): reworked after adversarial review. The owner query is
> now deduplicated but **not** memoised (a stdout-returning helper cannot cache
> across the command-substitution call pattern its callers use — see §5.4); the
> cache flush is now **unconditional** on any `dnf` invocation (§5.2); the mutator
> census is corrected and `rpmkeys --import` is accounted for (§5.2); the call-site
> count is corrected to 20 sites across 12 modules (§5.3).

## 1. Summary

Centralise the two RPM queries Atlas repeats — `rpm -q <pkg>` (is a package
installed?) and `rpm -qf <path>` (which package owns a file?) — behind two engine
helpers, `os::pkg_installed` and `os::pkg_owner`.

The change delivers two things, and the first is the reliable one:

1. **Deduplication (all 20 sites).** Twenty call sites across twelve modules each
   re-implement the same `rpm -q "$1" >/dev/null 2>&1` predicate or the same
   `owner="$(rpm -qf "$path" 2>/dev/null)" || return 1` idiom. They collapse to
   two reviewed helpers with one documented contract each.
2. **A modest, provably-safe speedup on the presence predicate only.**
   `os::pkg_installed` memoises within the module subshell; `os::pkg_owner` does
   not (§5.4 explains why it cannot, and why that is fine). The `install` verb
   runs `check → install → verify` in one subshell, and `check` and `verify` both
   re-query the same package set with `rpm -q`; memoisation collapses those
   repeats to one fork per distinct package.

This RFC deliberately does not oversell the speedup. See §3 and §6.

## 2. Goals

- One reviewed place each for "is this package installed?" and "who owns this
  path?"; remove the duplicated idioms from module code.
- Never fork `rpm -q` twice for the same package **within one module subshell**.
- Preserve every existing behavioural contract exactly: the presence predicate's
  exit code, and the owner query's stdout **and** exit code.
- Guarantee the cache can never report state that contradicts reality — during a
  run that mutates packages, or across separate `atlas` invocations — and make
  that guarantee rest on the design, not on a caller convention.

## 3. Non-goals

- **No persistent or on-disk cache.** The cache lives in shell memory and dies
  with the process. A package removed with `dnf` between two `atlas` runs is
  always re-seen next run. The correctness audit that motivated v1.0.1 found bugs
  of the form "reports satisfied without checking reality"; a cross-run cache
  manufactures exactly that class. It is prohibited, not merely omitted.
- **No memoisation of the owner query.** `os::pkg_owner` returns the owning
  package on stdout, so its callers invoke it inside `"$( … )"`. A cache written
  inside that command-substitution subshell cannot persist into the module
  subshell, so a memoised owner query would be dead code that a naive unit test
  would nonetheless "pass." We therefore do not pretend to cache it — it is a
  thin deduplication wrapper only (§5.4).
- **No cross-module caching.** The runner isolates each module in its own
  subshell (`_runner_run_module`); the cache is per-module by construction (§4).
- **No caching of `rpm -qa`, version strings, or ad-hoc `rpm -qf` beyond the
  owner predicate. No TTL, no eviction.** One module subshell asks a tiny bounded
  number of distinct questions.

## 4. Why the runner model makes this safe

`_runner_run_module` runs every hook of a module inside one `( … )` subshell and
sources the module fresh there. Two consequences follow for free:

- **Per-invocation by construction.** The cache is a Bash associative array; a
  subshell cannot outlive the `atlas` process, so no cached answer survives to a
  later run. There is no persistence path to get wrong.
- **Cross-module isolation by construction.** A `( … )` subshell inherits a
  *copy* of parent variables; mutations inside do not escape. Module A's cache
  cannot leak into module B's subshell.

The isolation argument depends on the cache being populated **only inside module
subshells**. Therefore: the helpers are called only from module hooks. The
`atlas` entrypoint and the runner itself MUST NOT call `os::pkg_installed`
(a parent-populated entry would be inherited by every later module subshell,
which no per-module flush can clear). This is a standing rule (§9, decision 3).

The one hazard the model does not solve on its own is *intra-subshell mutation*:
the `install` verb runs `check` (may cache "absent"), then `install` (runs `dnf`,
makes it present), then `verify` (must see "present"). §5.2 closes this.

## 5. Design

### 5.1 Presence helper — memoised (`internal/os.sh`)

```bash
# Per-process cache of `rpm -q` results. Scoped to the module subshell the runner
# spawns, so it is inherently per-invocation and per-module (RFC-0028 §4). Only
# ever populated inside a module subshell; never from the atlas parent process.
declare -gA _OS_PKG_INSTALLED=()   # pkg name -> "0" installed / "1" not

# Is an RPM package installed? Same exit-code contract as a bare
# `rpm -q "$1" >/dev/null 2>&1`. Memoisation persists wherever the caller invokes
# it as a direct predicate (the common case). One site — desktop/utilities —
# calls its wrapper inside `$(_utilities_missing_packages)`, where the cache
# write is discarded with the child subshell: still correct (never stale), just
# not memoised there.
os::pkg_installed() {
  local pkg="$1"
  if [ -z "${_OS_PKG_INSTALLED[$pkg]+x}" ]; then
    local rc=0; rpm -q "$pkg" >/dev/null 2>&1 || rc=1
    _OS_PKG_INSTALLED[$pkg]="$rc"
  fi
  return "${_OS_PKG_INSTALLED[$pkg]}"
}

# Drop the cache. Called after any package-state mutation.
os::pkg_cache_flush() { _OS_PKG_INSTALLED=(); }
```

### 5.2 Invalidation — the correctness hinge

**Census of RPM-database mutators (grep-verified, corrected):**

- `os::dnf_install` — the only function that installs/updates **packages** (the
  keys the cache stores). Seventeen call sites, all **direct** calls (never inside
  command substitution — see the standing rule below).
- `rpmkeys --import` — into the **system** rpm DB in `development/docker`
  (module.sh:195) and `development/claude` (module.sh:210). These add
  `gpg-pubkey` signing-key entries. A `gpg-pubkey` owns no files and no module
  ever queries a `gpg-pubkey` name, so they cannot alter a cached answer and need
  no flush. (The earlier `rpmkeys --import --root "$tmp"` calls at docker:176 /
  claude:191 import into a throwaway root, not the system DB, and are irrelevant.
  Both real imports also run inside install flows that call `os::dnf_install`,
  which flushes regardless.)
- `dnf copr enable` (`development/ghostty`) mutates **repo configuration**, not
  the rpm DB, so it is out of census scope.
- No module runs `rpm -e`, `rpm -i`, or `dnf remove`. (There is no `remove` verb;
  RFC-0002.)

Standing rule: `os::dnf_install` must itself be called **directly**, never inside
`"$( … )"`. A command-substituted call would mutate the real system in a child
subshell whose `os::pkg_cache_flush` dies with it, leaving the module subshell's
cache stale. All seventeen current sites comply; new call sites must too.

`os::dnf_install` flushes **unconditionally** — a failed `dnf` can still have
changed package state (a post-transaction scriptlet can fail after the packages
are on disk), so the flush must not be gated on the exit code:

```bash
os::dnf_install() {
  [ "$#" -gt 0 ] || return 0
  os::require_cmd dnf
  local sudo=""; os::is_root || sudo="sudo"
  log::info "installing packages: $*"
  local rc=0
  $sudo dnf install -y "$@" || rc=1
  os::pkg_cache_flush        # packages may have changed even on failure — flush first
  if [ "$rc" -ne 0 ]; then log::error "dnf install failed: $*"; return 1; fi
}
```

After the flush, `verify`'s first `os::pkg_installed` re-forks `rpm -q` and sees
reality. The stale-read hazard is closed at the one place package state changes,
by the design itself — not by any caller's `|| return 1` habit.

### 5.3 Owner helper — deduplication only

```bash
# Which package owns a path? Prints the owning package name (empty when unowned)
# and returns 0 iff owned — the exact contract callers rely on via
# `owner="$(os::pkg_owner "$p")" || return 1`. Not cached; see §5.4.
os::pkg_owner() {
  local owner; owner="$(rpm -qf "$1" 2>/dev/null)" || owner=""
  printf '%s\n' "$owner"
  [ -n "$owner" ]
}
```

### 5.4 Why the owner query is not memoised

Every owner call site captures stdout: `owner="$(os::pkg_owner "$path")"`.
Command substitution executes the function in a child subshell, so any
`_OS_PKG_OWNER[$path]=…` written there is discarded when that subshell exits and
never reaches the module subshell. A stdout-returning helper is therefore
*unmemoisable* by an inherited associative array; adding one would be dead code
whose only effect is a false green in a unit test that called it directly. If
profiling later shows `rpm -qf` forks are material, a follow-up RFC can return
the owner via a nameref/global (no command substitution) and cache that — but not
in this RFC, and not without a benchmark to justify the added surface.

### 5.5 Migration (20 sites, 12 modules)

Modules keep their private wrappers (their names/prefixes are local style); the
wrapper body delegates:

```bash
_python_pkg_present()   { os::pkg_installed "$1"; }
_python_path_owned_by() {
  local path="$1" prefix="$2" owner
  [ -x "$path" ] || return 1
  owner="$(os::pkg_owner "$path")" || return 1
  case "$owner" in "$prefix"-*) return 0 ;; *) return 1 ;; esac
}
```

Sites (grep `rpm -q` / `rpm -qf`): `desktop/cursor` (1), `desktop/icons` (1),
`desktop/utilities` (1), `development/python` (2), `development/node` (2),
`development/uv` (2), `development/pnpm` (2), `development/fish` (2),
`development/claude` (2), `development/codex` (1), `development/ghostty` (1),
`development/docker` (3). Total 20.

Note the one variant contract: `development/ghostty` (module.sh:218) uses
`if owner="$(rpm -qf …)"; then` and tolerates an unowned path rather than
`|| return 1`. `os::pkg_owner`'s rc (0 iff owned) preserves that branch exactly.

## 6. Honest benefit assessment

- **Deduplication is the reliable win** — 20 ad-hoc `rpm` idioms → two reviewed
  helpers. Worth doing on code-quality grounds alone.
- **The speedup is real but bounded and applies only to `rpm -q`.** It helps most
  on the fresh-`install` path (`check`+`install`+`verify` re-querying the same
  packages) and any hook that asks the same package twice. It does **not** help
  `atlas status`/`doctor` across modules (one hook per module subshell), and it
  does **not** touch `rpm -qf` at all (§5.4).
- No headline number is claimed. If the fork savings prove negligible, the
  deduplication and single contract still justify the change, and nothing about
  it can regress correctness (§5.2).

## 7. Security & correctness considerations

- The cache holds only package names and 0/1 flags — no secrets.
- The only way to observe a stale presence answer is a package-state change that
  bypasses `os::dnf_install`. The §5.2 census shows none exists; any future
  mutator MUST call `os::pkg_cache_flush` (this RFC is where that rule lives).
- Helpers are invoked only inside module subshells (§4); the parent process must
  not populate the cache.
- No hook's conclusion about the system changes — only how many times it forks
  `rpm` to reach it.

## 8. Testing strategy

New engine tests (`tests/test_os_pkg_cache.sh`), with a mock `rpm` that counts
invocations via a counter file:

1. **Presence memoised.** Two `os::pkg_installed foo` calls fork `rpm` once and
   return the same code; a known-absent package caches rc 1 with one fork.
2. **Flush on install — success.** Seed "absent"; mock `dnf` flips foo to present;
   `os::dnf_install foo`; assert the next `os::pkg_installed foo` re-forks and
   returns present.
3. **Flush on install — failure (the sharp one).** Mock `dnf` makes foo present
   but exits 1; `os::dnf_install foo` returns 1 **and** still flushes; assert the
   next `os::pkg_installed foo` re-forks and returns present. Proves the
   invalidation does not depend on `dnf` success.
4. **Owner contract, not memoisation.** `os::pkg_owner` on an owned path prints
   the package and returns 0; on an unowned path prints "" and returns 1. The
   test asserts the stdout+rc contract via the real `owner="$(…)"` call pattern —
   it does **not** assert a fork count, because §5.4 says there is no caching to
   assert.
5. **Subshell isolation.** A cache populated in one `( … )` does not affect a
   sibling `( … )`.
6. Full existing suite (949 tests) stays green after migrating the 20 sites.

## 9. Decision required

1. Accept the split: memoise `os::pkg_installed`; `os::pkg_owner` is a thin
   deduplication wrapper, explicitly **not** memoised (§5.4).
2. Accept **unconditional** flush inside `os::dnf_install`, and the standing rule
   that any future package mutation calls `os::pkg_cache_flush` (§5.2, §7).
3. Accept the rule that the helpers are only ever called inside module subshells,
   never from the `atlas` parent process (§4).
4. Accept migrating all 20 sites in this RFC rather than opportunistically.
