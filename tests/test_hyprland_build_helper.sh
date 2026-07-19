#!/usr/bin/env bash
# desktop/hyprland — aquamarine rebuild helper (RFC-0038 §5).
#
# Hermetic: every dynamic case runs the real executable
# (modules/desktop/hyprland/build/build-aquamarine.sh) as a fresh subprocess,
# but with its PATH restricted (via `env -i`) to a per-case fake-bin
# directory containing: symlinks to a fixed, harmless set of coreutils
# (mkdir, sed, grep, mktemp, find, cp, rm) resolved from the *test* host, plus
# purpose-built fake `dnf`, `rpm`, `rpmbuild`, and (optionally) `mock`
# executables that log every invocation and never touch the network, a mock
# chroot, the real RPM database, or a real dnf transaction. No case invokes a
# real mock/dnf/rpmbuild build. `HOME`, the staged RPM dir, and the two files
# the helper reads to decide "is this Fedora 44" are all sandboxed per case —
# nothing reads or writes outside a per-case `mktemp -d`.
HELPER="$ATLAS_ROOT/modules/desktop/hyprland/build/build-aquamarine.sh"
BASH_BIN="$(command -v bash)"

# --- static assertions (fast, no subprocess sandbox needed) -----------------

assert_status "build helper is valid bash" 0 bash -n "$HELPER"
assert_status "build helper pins the exact release string" 0 \
  bash -c "grep -qF '2%{?dist}.atlas1' \"$HELPER\""
assert_status "build helper never bumps the aquamarine version" 1 \
  bash -c "grep -qE 'aquamarine-0\.(9\.[6-9]|1[0-9])' \"$HELPER\""

# --- hermetic sandbox builder -------------------------------------------

# _hab_sandbox <dir>: seeds $dir with the directory skeleton and the fake
# dnf/rpm/rpmbuild executables, and defaults the two Fedora-version files to
# "Fedora 44". `mock` is deliberately NOT installed here — call
# _hab_enable_mock to add it for cases that need the mock-first path.
_hab_sandbox() {
  local dir="$1" bin="$1/bin" tool
  mkdir -p "$bin" "$dir/home" "$dir/tmp" "$dir/logs"
  printf 'ID=fedora\nVERSION_ID=44\n' > "$dir/os-release"
  printf 'Fedora release 44 (Test)\n' > "$dir/fedora-release"

  for tool in mkdir sed grep mktemp find cp rm cat; do
    ln -sf "$(command -v "$tool")" "$bin/$tool"
  done

  # Fake dnf: logs every call. `download --source` drops a stub SRPM into the
  # caller's cwd (the real helper always cds into the build workspace first).
  # `builddep` is a no-op whose exit code is controllable for fallback tests.
  cat > "$bin/dnf" <<'FAKE'
#!/usr/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKEBIN_LOG_DIR/dnf.log"
case "$*" in
  *"download --source"*) : > "aquamarine-0.9.5-2.fc44.src.rpm" ;;
  *"builddep"*)          exit "${FAKE_DNF_BUILDDEP_RC:-0}" ;;
esac
FAKE

  # Fake rpm: `--define "_topdir X" -i SRPM` seeds a stub spec at
  # $topdir/SPECS/aquamarine.spec. `-qp --requires|--provides PATH` is the
  # gate query — it reads a single-line marker ("GOOD" or "BAD") written into
  # the built-RPM stub by the fake mock/rpmbuild below and reports the
  # matching linkage, so the same gate logic in the real helper can be
  # exercised deterministically without a real RPM ever being built.
  cat > "$bin/rpm" <<'FAKE'
#!/usr/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKEBIN_LOG_DIR/rpm.log"
if [ "${1:-}" = "--define" ] && [ "${3:-}" = "-i" ]; then
  topdir="${2#_topdir }"
  mkdir -p "$topdir/SPECS"
  cat > "$topdir/SPECS/aquamarine.spec" <<'SPEC'
Name:           aquamarine
Version:        0.9.5
Release:        2%{?dist}
Summary:        stub spec for hermetic tests
License:        MIT
%description
stub
SPEC
  exit 0
fi
if [ "${1:-}" = "-qp" ] && [ "${2:-}" = "--requires" ]; then
  path="${3:-}"; [ -f "$path" ] || exit 1
  if grep -qx GOOD "$path"; then printf 'libdisplay-info.so.3()(64bit)\n'
  elif grep -qx BAD "$path"; then printf 'libdisplay-info.so.2()(64bit)\n'
  fi
  exit 0
fi
if [ "${1:-}" = "-qp" ] && [ "${2:-}" = "--provides" ]; then
  path="${3:-}"; [ -f "$path" ] || exit 1
  printf 'libaquamarine.so.8()(64bit)\n'
  exit 0
fi
exit 1
FAKE

  # Fake rpmbuild: `-bs SPEC` stages a stub tagged SRPM (the mock/fallback
  # split happens after this). `-bb SPEC` is the host fallback build path; it
  # writes the built RPM stub with content $FAKE_BUILD_RESULT (GOOD/BAD),
  # controlling whether the gate downstream passes or fails.
  cat > "$bin/rpmbuild" <<'FAKE'
#!/usr/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKEBIN_LOG_DIR/rpmbuild.log"
topdir="${2#_topdir }"
case "${3:-}" in
  -bs)
    mkdir -p "$topdir/SRPMS"
    : > "$topdir/SRPMS/aquamarine-0.9.5-2.fc44.atlas1.src.rpm"
    ;;
  -bb)
    mkdir -p "$topdir/RPMS"
    printf '%s\n' "${FAKE_BUILD_RESULT:-GOOD}" > "$topdir/RPMS/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"
    exit "${FAKE_RPMBUILD_BB_RC:-0}"
    ;;
  *) exit 1 ;;
esac
FAKE

  chmod +x "$bin"/dnf "$bin"/rpm "$bin"/rpmbuild
}

# _hab_enable_mock <dir>: adds a fake `mock` that writes the built RPM stub
# with content $FAKE_BUILD_RESULT (GOOD/BAD) and can be made to fail via
# $FAKE_MOCK_RC, to exercise both the mock success path and the
# mock-fails-so-fall-back path.
_hab_enable_mock() {
  local bin="$1/bin"
  cat > "$bin/mock" <<'FAKE'
#!/usr/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKEBIN_LOG_DIR/mock.log"
[ "${FAKE_MOCK_RC:-0}" = 0 ] || exit "${FAKE_MOCK_RC}"
resultdir=""
for a in "$@"; do case "$a" in --resultdir=*) resultdir="${a#--resultdir=}" ;; esac; done
[ -n "$resultdir" ] || exit 1
mkdir -p "$resultdir"
printf '%s\n' "${FAKE_BUILD_RESULT:-GOOD}" > "$resultdir/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"
FAKE
  chmod +x "$bin/mock"
}

# _hab_run <dir> [VAR=val ...]: runs the real helper as a subprocess with a
# fully clean environment (`env -i`) — PATH restricted to the sandbox's fake
# bin dir, HOME/TMPDIR sandboxed, the RPM staging dir and both
# Fedora-version-check files redirected under $dir. Extra VAR=val arguments
# (e.g. FAKE_BUILD_RESULT=BAD) are forwarded to control the fakes.
_hab_run() {
  local dir="$1"; shift
  env -i \
    PATH="$dir/bin" \
    HOME="$dir/home" \
    TMPDIR="$dir/tmp" \
    FAKEBIN_LOG_DIR="$dir/logs" \
    ATLAS_HYPR_RPM_DIR="$dir/rpms" \
    ATLAS_HYPR_OS_RELEASE_FILE="$dir/os-release" \
    ATLAS_HYPR_FEDORA_RELEASE_FILE="$dir/fedora-release" \
    ATLAS_HYPR_COPR_REPOID="test:copr" \
    ATLAS_HYPR_MOCK_CHROOT="test-chroot" \
    "$@" \
    "$BASH_BIN" "$HELPER"
}

_hab_out_rpm() { printf '%s\n' "$1/rpms/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"; }

# --- Fedora 44 gate: refuses before any mutation -----------------------------

dir="$(mktemp -d)"; _hab_sandbox "$dir"
printf 'ID=fedora\nVERSION_ID=41\n' > "$dir/os-release"
printf 'Fedora release 41 (Test)\n' > "$dir/fedora-release"

assert_status "helper refuses to build on non-Fedora-44" 1 _hab_run "$dir"
assert_status "Fedora gate failure makes no dnf/rpm/rpmbuild calls" 0 \
  bash -c "[ ! -s '$dir/logs/dnf.log' ] && [ ! -s '$dir/logs/rpm.log' ] && [ ! -s '$dir/logs/rpmbuild.log' ]"
assert_status "Fedora gate failure never creates the RPM staging dir" 1 \
  bash -c "[ -e '$dir/rpms' ]"
rm -rf "$dir"

# --- success path via mock ---------------------------------------------------

dir="$(mktemp -d)"; _hab_sandbox "$dir"; _hab_enable_mock "$dir"

assert_status "helper succeeds via mock and stages a gated RPM" 0 _hab_run "$dir"
assert_status "staged artifact has the exact pinned NEVRA" 0 \
  bash -c "[ -f '$(_hab_out_rpm "$dir")' ]"
assert_status "mock path never calls dnf builddep" 1 \
  bash -c "grep -q builddep '$dir/logs/dnf.log'"
assert_status "mock path never falls back to host rpmbuild -bb" 1 \
  bash -c "grep -q -- '-bb' '$dir/logs/rpmbuild.log'"
assert_status "helper never creates \$HOME/rpmbuild (isolated workspace only)" 1 \
  bash -c "[ -e '$dir/home/rpmbuild' ]"
rm -rf "$dir"

# --- gate failure: wrong linkage is refused, nothing is staged --------------

dir="$(mktemp -d)"; _hab_sandbox "$dir"; _hab_enable_mock "$dir"

out="$(_hab_run "$dir" FAKE_BUILD_RESULT=BAD 2>&1)"; rc=$?
assert_eq       "a mock artifact with wrong linkage is refused" "$rc" "1"
assert_contains "gate failure is reported as a GATE FAILED error" "$out" "GATE FAILED"
assert_status "a gate failure never stages an artifact" 1 \
  bash -c "[ -e '$(_hab_out_rpm "$dir")' ]"
rm -rf "$dir"

# --- idempotency: a second run short-circuits, no fresh tool calls ----------

dir="$(mktemp -d)"; _hab_sandbox "$dir"; _hab_enable_mock "$dir"
_hab_run "$dir" >/dev/null 2>&1
first_sha="$(sha256sum "$(_hab_out_rpm "$dir")" | cut -d' ' -f1)"
: > "$dir/logs/mock.log"; : > "$dir/logs/dnf.log"; : > "$dir/logs/rpmbuild.log"; : > "$dir/logs/rpm.log"

assert_status "repeated run against an already-gated artifact still exits 0" 0 _hab_run "$dir"
assert_status "idempotent run makes no fresh mock/dnf-download/rpmbuild calls" 0 \
  bash -c "[ ! -s '$dir/logs/mock.log' ] && ! grep -q download '$dir/logs/dnf.log' && [ ! -s '$dir/logs/rpmbuild.log' ]"
second_sha="$(sha256sum "$(_hab_out_rpm "$dir")" | cut -d' ' -f1)"
assert_eq "idempotent run leaves the staged artifact byte-identical" "$second_sha" "$first_sha"
rm -rf "$dir"

# --- fallback path: mock absent -> host rpmbuild + dnf builddep -------------

dir="$(mktemp -d)"; _hab_sandbox "$dir"   # note: no _hab_enable_mock — mock is not on PATH

assert_status "helper falls back to rpmbuild+dnf builddep when mock is absent" 0 _hab_run "$dir"
assert_status "fallback path calls dnf builddep" 0 \
  bash -c "grep -q builddep '$dir/logs/dnf.log'"
assert_status "fallback path calls host rpmbuild -bb" 0 \
  bash -c "grep -q -- '-bb' '$dir/logs/rpmbuild.log'"
assert_status "fallback path never invokes mock" 1 \
  bash -c "[ -e '$dir/logs/mock.log' ] && [ -s '$dir/logs/mock.log' ]"
assert_status "fallback path stages a correctly gated artifact" 0 \
  bash -c "[ -f '$(_hab_out_rpm "$dir")' ]"
rm -rf "$dir"

# --- fallback path: mock present but its build fails ------------------------

dir="$(mktemp -d)"; _hab_sandbox "$dir"; _hab_enable_mock "$dir"

assert_status "helper falls back when mock is present but its build fails" 0 \
  _hab_run "$dir" FAKE_MOCK_RC=1
assert_status "mock-failure fallback still calls dnf builddep" 0 \
  bash -c "grep -q builddep '$dir/logs/dnf.log'"
assert_status "mock-failure fallback stages a correctly gated artifact" 0 \
  bash -c "[ -f '$(_hab_out_rpm "$dir")' ]"
rm -rf "$dir"

# --- required tools missing: refuses before any mutation --------------------

dir="$(mktemp -d)"; _hab_sandbox "$dir"
rm -f "$dir/bin/dnf"

assert_status "helper refuses when dnf is missing from PATH" 1 _hab_run "$dir"
assert_status "missing-dnf refusal never creates the RPM staging dir" 1 \
  bash -c "[ -e '$dir/rpms' ]"
rm -rf "$dir"

# --- watcher: supersession logic (RFC-0038 §9) ------------------------------
WATCH="$ATLAS_ROOT/modules/desktop/hyprland/assets/watch-availability.sh"
assert_status "watcher is valid bash" 0 bash -n "$WATCH"
assert_status "watcher keys off atlas release marker" 0 \
  bash -c "grep -qE 'atlas\\*' \"$WATCH\" || grep -qF 'atlas1' \"$WATCH\""
assert_status "watcher no longer self-disables solely because hyprland is installed" 1 \
  bash -c "grep -q 'hyprland already installed; disabling watcher' \"$WATCH\""
