# Task 2 Report: Shared `atlas.env` reader (`internal/env.sh`)

## Status: DONE

## TDD Evidence

### RED (Step 2)

After writing `tests/test_env.sh` verbatim from the brief and running `bash tests/run.sh`:

```
test_env.sh
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_env.sh: line 2: //wsl.localhost/Ubuntu/home/thiva/atlas/internal/env.sh: No such file or directory
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_env.sh: line 10: env::get: command not found
  FAIL env::get reads a quoted value from atlas.env
       expected [Ada Lovelace] got []
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_env.sh: line 12: env::get: command not found
  FAIL env::get reads an unquoted value from atlas.env
       expected [ada@example.com] got []
//wsl.localhost/Ubuntu/home/thiva/atlas/tests/test_env.sh: line 16: env::get: command not found
  FAIL env var overrides atlas.env
       expected [env@x] got []
  FAIL missing key returns non-zero
       exit 127, wanted 1
  ok   missing key prints nothing

== 55 passed, 4 failed ==
```

4 failures, all attributable to the missing `internal/env.sh` / undefined `env::get` — confirms the test was
actually exercising the new code path before implementation existed.

### GREEN (Step 5)

After implementing `internal/env.sh` and wiring it into `atlas`:

```
test_env.sh
  ok   env::get reads a quoted value from atlas.env
  ok   env::get reads an unquoted value from atlas.env
  ok   env var overrides atlas.env
  ok   missing key returns non-zero
  ok   missing key prints nothing

== 59 passed, 0 failed ==
```

54 (prior) + 5 (new) = 59 passed, 0 failed. Matches the brief's expected total exactly.

### `bash atlas --help` check

```
$ bash atlas --help; echo "EXIT: $?"
Atlas — workstation lifecycle manager (v0.1.0-dev)
...
EXIT: 0
```

Entrypoint sources `internal/env.sh` cleanly and `--help` still exits 0.

## Files Changed

- `internal/env.sh` (new) — `env::get <NAME>`, transcribed verbatim from the brief's Step 3 code block.
- `tests/test_env.sh` (new) — transcribed verbatim from the brief's Step 1 code block.
- `atlas` (modified) — added `source "$ATLAS_ROOT/internal/env.sh"` immediately after the `os.sh` source line,
  before `module.sh` and `runner.sh`, exactly as the brief's Step 4 diff shows.

Diff of `atlas`:
```diff
 source "$ATLAS_ROOT/internal/log.sh"
 source "$ATLAS_ROOT/internal/error.sh"
 source "$ATLAS_ROOT/internal/os.sh"
+source "$ATLAS_ROOT/internal/env.sh"
 source "$ATLAS_ROOT/internal/module.sh"
 source "$ATLAS_ROOT/internal/runner.sh"
```

## Self-Review

- **Faithful transcription:** `internal/env.sh` and `tests/test_env.sh` were written byte-for-byte from the
  brief's code blocks (double-checked via `git diff` after staging — no stray edits). The `atlas` entrypoint
  edit matches the brief's Step 4 diff exactly (single line insertion, correct position).
- **Env-var-over-file precedence:** `env::get` checks `${!name:-}` (indirect expansion of the live environment
  variable) first and returns immediately if non-empty, only falling through to the file scan otherwise. Verified
  by the "env var overrides atlas.env" test (`ATLAS_GIT_USER_EMAIL='env@x' env::get ATLAS_GIT_USER_EMAIL` → `env@x`
  despite the file having `ada@example.com`).
- **Quote stripping:** one layer of surrounding `"` or `'` is stripped via parameter expansion
  (`val="${val%\"}"; val="${val#\"}"` then the same for single quotes). Verified: `ATLAS_GIT_USER_NAME="Ada Lovelace"`
  in the file resolves to `Ada Lovelace` (quotes gone), and the unquoted `ATLAS_GIT_USER_EMAIL=ada@example.com`
  passes through unchanged.
- **Comment/blank-line handling:** the read loop explicitly `continue`s on empty lines (`[ -z "$line" ] &&
  continue`) and on lines starting with `#` (`\#*) continue ;;`) before any `NAME=` pattern match, so a line like
  `# a comment` can never be mistaken for a key. Verified implicitly — the test file's first line is `# a comment`
  and no test expects a spurious match from it.
- **Last-match-wins:** the loop keeps overwriting `val` on every matching `"$name="*` line rather than breaking
  early, so a later duplicate key line wins. Not exercised by the brief's literal test file (which has only one
  line per key), so I added an ad-hoc manual check beyond the brief (two `ATLAS_X=` lines, `1` then `2`) and
  confirmed `env::get ATLAS_X` returns `2`. This was verification only — no test file changes were needed since
  the brief's test file is prescribed verbatim.
- **Missing-in-both case:** returns 1 with no output. Verified by both the `assert_status ... 1 env::get
  ATLAS_DEFINITELY_MISSING_XYZ` and `assert_eq ... "" ` tests, and additionally covered when `ATLAS_CONFIG_HOME`
  points at a sandbox with no `atlas.env` at all (`[ -r "$file" ] || return 1` — also implicitly covered by the
  cleanup at the end of the test where `$sandbox` is removed and `ATLAS_CONFIG_HOME` unset, though that runs after
  the assertions so it isn't itself asserted).
- **Idempotent source guard:** `[ -n "${ATLAS_ENV_SH:-}" ] && return 0; ATLAS_ENV_SH=1` matches the pattern used by
  the other `internal/*.sh` files, so re-sourcing (e.g. if a module or the runner's subshell sources it again) is
  a no-op.
- **Entrypoint load order:** placed after `os.sh` and before `module.sh`/`runner.sh` per the brief's rationale —
  "so module hooks running in the runner's subshell inherit `env::get`". Confirmed `bash atlas --help` still exits
  0, i.e., no sourcing-order regression.

## Concerns

None. Implementation is a verbatim transcription of the brief with all TDD gates (RED → GREEN) passing, the
suite total matches the expected 59/0, and the entrypoint still loads and runs cleanly.

## Commit

`512ca51` — `feat(env): add atlas.env reader for user-specific config`
(3 files changed, 55 insertions(+): `internal/env.sh`, `tests/test_env.sh`, `atlas`)
