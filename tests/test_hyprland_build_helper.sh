#!/usr/bin/env bash
# desktop/hyprland — aquamarine rebuild helper (RFC-0038 §5).
#
# Hermetic: every dynamic case runs the real executable
# (modules/desktop/hyprland/build/build-aquamarine.sh) as a fresh subprocess,
# but with its PATH restricted (via `env -i`) to a per-case fake-bin
# directory containing: symlinks to a fixed, harmless set of coreutils
# resolved from the *test* host, plus purpose-built fake `dnf`, `rpm`,
# `rpmbuild`, and (optionally) `mock` executables that log every invocation and
# never touch the network, a mock chroot, the real RPM database, or a real dnf
# transaction. The build is mock-ONLY: no case runs a real build, and there is
# no host rpmbuild -bb / dnf builddep fallback to exercise (RFC-0038 §5). The
# real _hab_gate runs against fake `rpm` output so its NEVRA/soname/integrity
# checks are exercised deterministically. `HOME`, the staged RPM dir, and the
# two Fedora-version files are sandboxed per case — nothing reads or writes
# outside a per-case `mktemp -d`.
HELPER="$ATLAS_ROOT/modules/desktop/hyprland/build/build-aquamarine.sh"
BASH_BIN="$(command -v bash)"

# --- static assertions (fast, no subprocess sandbox needed) -----------------

assert_status "build helper is valid bash" 0 bash -n "$HELPER"
assert_status "build helper pins the exact release string" 0 \
  bash -c "grep -qF '2%{?dist}.atlas1' \"$HELPER\""
assert_status "build helper never bumps the aquamarine version" 1 \
  bash -c "grep -qE 'aquamarine-0\.(9\.[6-9]|1[0-9])' \"$HELPER\""
assert_status "build helper has no host rpmbuild -bb fallback" 1 \
  bash -c "grep -qE 'rpmbuild.*-bb' \"$HELPER\""
assert_status "build helper has no host dnf builddep fallback" 1 \
  bash -c "grep -q 'builddep' \"$HELPER\""
assert_status "build helper validates the full NEVRA in the gate" 0 \
  bash -c "grep -qF '2.fc44.atlas1' \"$HELPER\" && grep -q 'NAME' \"$HELPER\""

# --- hermetic sandbox builder -------------------------------------------

# _hab_sandbox <dir>: seeds $dir with the directory skeleton and the fake
# dnf/rpm/rpmbuild executables, and defaults the two Fedora-version files to
# "Fedora 44". `mock` is deliberately NOT installed here — call
# _hab_enable_mock to add it for cases that need the (only) build path.
_hab_sandbox() {
  local dir="$1" bin="$1/bin" tool
  mkdir -p "$bin" "$dir/home" "$dir/tmp" "$dir/logs"
  printf 'ID=fedora\nVERSION_ID=44\n' > "$dir/os-release"
  printf 'Fedora release 44 (Test)\n' > "$dir/fedora-release"

  for tool in mkdir sed grep mktemp find cp rm cat mv head; do
    ln -sf "$(command -v "$tool")" "$bin/$tool"
  done

  # Fake dnf: logs every call. `download --source` drops a stub SRPM into the
  # caller's cwd (the real helper always cds into the build workspace first).
  cat > "$bin/dnf" <<'FAKE'
#!/usr/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKEBIN_LOG_DIR/dnf.log"
case "$*" in
  *"download --source"*) : > "aquamarine-0.9.5-2.fc44.src.rpm" ;;
esac
FAKE

  # Fake rpm: `--define "_topdir X" -i SRPM` seeds a stub spec. The gate queries
  # (`-qp --qf`, `-qp --requires|--provides`, `-K`) read a one-line marker
  # ("GOOD"/"BAD"/"WRONGREL"/"CORRUPT") the fake mock wrote into the built-RPM
  # stub, so the REAL _hab_gate in the helper is exercised deterministically.
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
# Read the marker content out of the stub RPM at the query path.
_marker() { head -n1 "${1:-/dev/null}" 2>/dev/null || true; }
if [ "${1:-}" = "-qp" ] && [ "${2:-}" = "--qf" ]; then
  path="${4:-}"; [ -f "$path" ] || exit 1
  case "$(_marker "$path")" in
    WRONGREL) printf 'aquamarine 0.9.5 9.fc44 x86_64\n' ;;
    *)        printf 'aquamarine 0.9.5 2.fc44.atlas1 x86_64\n' ;;
  esac
  exit 0
fi
if [ "${1:-}" = "-qp" ] && [ "${2:-}" = "--requires" ]; then
  path="${3:-}"; [ -f "$path" ] || exit 1
  case "$(_marker "$path")" in
    BAD) printf 'libdisplay-info.so.2()(64bit)\n' ;;
    SONAME30) printf 'libdisplay-info.so.30()(64bit)\n' ;;
    *)   printf 'libdisplay-info.so.3()(64bit)\n' ;;
  esac
  exit 0
fi
if [ "${1:-}" = "-qp" ] && [ "${2:-}" = "--provides" ]; then
  path="${3:-}"; [ -f "$path" ] || exit 1
  case "$(_marker "$path")" in
    SONAME30) printf 'libaquamarine.so.80()(64bit)\n' ;;
    *) printf 'libaquamarine.so.8()(64bit)\n' ;;
  esac
  exit 0
fi
if [ "${1:-}" = "-K" ]; then
  # last arg is the path
  for path in "$@"; do :; done
  [ -f "$path" ] || exit 1
  [ "$(_marker "$path")" = CORRUPT ] && exit 1
  exit 0
fi
exit 1
FAKE

  # Fake rpmbuild: only `-bs SPEC` is valid now (source RPM re-roll). Any `-bb`
  # invocation is a test failure — the helper must never call it.
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
  *) exit 1 ;;
esac
FAKE

  chmod +x "$bin"/dnf "$bin"/rpm "$bin"/rpmbuild
}

# _hab_enable_mock <dir>: adds a fake `mock` that writes the built RPM stub
# with content $FAKE_BUILD_RESULT (GOOD/BAD/WRONGREL/CORRUPT) and can be made
# to fail via $FAKE_MOCK_RC.
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

# _hab_run <dir> [VAR=val ...]: runs the real helper with env -i, PATH pinned to
# the sandbox fake bin, HOME/TMPDIR/staging/Fedora-files redirected under $dir.
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

dir="$(mktemp -d)"; _hab_sandbox "$dir"; _hab_enable_mock "$dir"
printf 'ID=fedora\nVERSION_ID=41\n' > "$dir/os-release"
printf 'Fedora release 41 (Test)\n' > "$dir/fedora-release"

assert_status "helper refuses to build on non-Fedora-44" 1 _hab_run "$dir"
assert_status "Fedora gate failure makes no dnf/rpm/rpmbuild/mock calls" 0 \
  bash -c "[ ! -s '$dir/logs/dnf.log' ] && [ ! -s '$dir/logs/rpm.log' ] && [ ! -s '$dir/logs/rpmbuild.log' ] && [ ! -e '$dir/logs/mock.log' ]"
assert_status "Fedora gate failure never creates the RPM staging dir" 1 \
  bash -c "[ -e '$dir/rpms' ]"
rm -rf "$dir"

# --- success path via mock ---------------------------------------------------

dir="$(mktemp -d)"; _hab_sandbox "$dir"; _hab_enable_mock "$dir"

assert_status "helper succeeds via mock and stages a gated RPM" 0 _hab_run "$dir"
assert_status "staged artifact has the exact pinned NEVRA" 0 \
  bash -c "[ -f '$(_hab_out_rpm "$dir")' ]"
assert_status "mock path re-rolls the SRPM with host rpmbuild -bs only" 0 \
  bash -c "grep -q -- '-bs' '$dir/logs/rpmbuild.log' && ! grep -q -- '-bb' '$dir/logs/rpmbuild.log'"
assert_status "helper never creates \$HOME/rpmbuild (isolated workspace only)" 1 \
  bash -c "[ -e '$dir/home/rpmbuild' ]"
assert_status "no staging temp is left behind" 0 \
  bash -c "! ls '$dir/rpms'/.stage.* >/dev/null 2>&1"
rm -rf "$dir"

# --- gate failures: each wrong attribute is refused, nothing staged ---------

for bad in BAD SONAME30 WRONGREL CORRUPT; do
  dir="$(mktemp -d)"; _hab_sandbox "$dir"; _hab_enable_mock "$dir"
  out="$(_hab_run "$dir" FAKE_BUILD_RESULT="$bad" 2>&1)"; rc=$?
  assert_eq       "a mock artifact failing the $bad gate is refused" "$rc" "1"
  assert_contains "$bad gate failure is reported as GATE FAILED" "$out" "GATE FAILED"
  assert_status "a $bad gate failure never stages an artifact" 1 \
    bash -c "[ -e '$(_hab_out_rpm "$dir")' ]"
  rm -rf "$dir"
done

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

# --- pre-existing artifact with wrong linkage is re-validated, not trusted ---

dir="$(mktemp -d)"; _hab_sandbox "$dir"; _hab_enable_mock "$dir"
mkdir -p "$dir/rpms"
printf 'BAD\n' > "$(_hab_out_rpm "$dir")"   # a stale/wrong file at the expected path
assert_status "a pre-existing wrong artifact does not short-circuit (rebuilds)" 0 _hab_run "$dir"
assert_status "the rebuilt artifact replaces the stale one and is gated GOOD" 0 \
  bash -c "grep -qx GOOD '$(_hab_out_rpm "$dir")'"
assert_status "re-validation actually invoked mock to rebuild" 0 \
  bash -c "[ -s '$dir/logs/mock.log' ]"
rm -rf "$dir"

# --- mock absent: hard failure, no host fallback ----------------------------

dir="$(mktemp -d)"; _hab_sandbox "$dir"   # note: no _hab_enable_mock

out="$(_hab_run "$dir" 2>&1)"; rc=$?
assert_eq       "helper fails when mock is absent (no host fallback)" "$rc" "1"
assert_contains "mock-absent failure names mock as required" "$out" "mock is required"
assert_status "mock-absent failure never calls dnf builddep or rpmbuild -bb" 0 \
  bash -c "! grep -q builddep '$dir/logs/dnf.log' 2>/dev/null && ! grep -q -- '-bb' '$dir/logs/rpmbuild.log' 2>/dev/null"
assert_status "mock-absent failure stages nothing" 1 \
  bash -c "[ -e '$(_hab_out_rpm "$dir")' ]"
rm -rf "$dir"

# --- mock present but its build fails: hard failure, no fallback ------------

dir="$(mktemp -d)"; _hab_sandbox "$dir"; _hab_enable_mock "$dir"

out="$(_hab_run "$dir" FAKE_MOCK_RC=1 2>&1)"; rc=$?
assert_eq       "helper fails when mock build fails (no host fallback)" "$rc" "1"
assert_contains "mock-build failure is reported" "$out" "mock build failed"
assert_status "mock-build failure never calls dnf builddep or rpmbuild -bb" 0 \
  bash -c "! grep -q builddep '$dir/logs/dnf.log' 2>/dev/null && ! grep -q -- '-bb' '$dir/logs/rpmbuild.log' 2>/dev/null"
assert_status "mock-build failure stages nothing" 1 \
  bash -c "[ -e '$(_hab_out_rpm "$dir")' ]"
rm -rf "$dir"

# --- required tools missing: refuses before any mutation --------------------

dir="$(mktemp -d)"; _hab_sandbox "$dir"; _hab_enable_mock "$dir"
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
assert_status "watcher no longer polls COPR availability (dead pre-install path removed)" 1 \
  bash -c "grep -q 'download.copr.fedorainfracloud.org' \"$WATCH\""
