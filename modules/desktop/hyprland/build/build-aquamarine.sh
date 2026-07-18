#!/usr/bin/env bash
# Atlas — rebuild aquamarine 0.9.5 against Fedora 44's libdisplay-info.so.3.
#
# Hyprland's installed binary hard-links libaquamarine.so.8()(64bit); only
# aquamarine 0.9.5 provides that soname, so the version below is pinned and
# must NEVER be bumped (RFC-0038 §5, docs/superpowers/specs/
# 2026-07-19-hyprland-source-build-design.md §2). Only the Release tag moves,
# and only to the one exact string that sorts above the broken upstream
# 2.fc44 and below a future official 3.fc44.
#
# Produces $ATLAS_HYPR_RPM_DIR/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm
# (default $ATLAS_HYPR_RPM_DIR: $HOME/atlas-hypr-rpms), gated to require
# libdisplay-info.so.3, never .so.2, and provide libaquamarine.so.8.
# Idempotent: exits 0 immediately if a gated artifact is already staged.
#
# Build order is mock-first (chroot build; zero host mutation until the
# gated artifact is copied out) with a host rpmbuild + dnf builddep fallback
# when mock is unavailable or its build fails (RFC-0038 §5). All work happens
# in a private, disposable workspace under $TMPDIR — this never touches
# ~/rpmbuild or any other path outside $ATLAS_HYPR_RPM_DIR.
#
# This script never runs unattended against a live system on its own; it is
# invoked by modules/desktop/hyprland/module.sh, which re-checks the same
# gate before ever handing the RPM to dnf.
set -euo pipefail

ATLAS_HYPR_COPR_REPOID="${ATLAS_HYPR_COPR_REPOID:-copr:copr.fedorainfracloud.org:solopasha:hyprland}"
ATLAS_HYPR_MOCK_CHROOT="${ATLAS_HYPR_MOCK_CHROOT:-fedora-44-x86_64}"
ATLAS_HYPR_RPM_DIR="${ATLAS_HYPR_RPM_DIR:-$HOME/atlas-hypr-rpms}"
ATLAS_HYPR_OS_RELEASE_FILE="${ATLAS_HYPR_OS_RELEASE_FILE:-/etc/os-release}"
ATLAS_HYPR_FEDORA_RELEASE_FILE="${ATLAS_HYPR_FEDORA_RELEASE_FILE:-/etc/fedora-release}"

# Pinned exactly — never bump. See the header comment above.
_HAB_RELEASE='2%{?dist}.atlas1'
_HAB_SRPM_NAME="aquamarine-0.9.5-2.fc44.src.rpm"
_HAB_TAGGED_SRPM_NAME="aquamarine-0.9.5-2.fc44.atlas1.src.rpm"
_HAB_RPM_NAME="aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"
_HAB_OUT_RPM="$ATLAS_HYPR_RPM_DIR/$_HAB_RPM_NAME"

_hab_log() { printf 'build-aquamarine: %s\n' "$*" >&2; }
_hab_die() { _hab_log "$*"; exit 1; }

# A built RPM passes iff it requires libdisplay-info.so.3, NEVER .so.2, and
# provides libaquamarine.so.8 — the soname Hyprland hard-links (RFC-0038 §5).
_hab_gate() {
  local rpm_path="$1"
  [ -f "$rpm_path" ] || return 1
  rpm -qp --requires "$rpm_path" 2>/dev/null | grep -q 'libdisplay-info\.so\.3' || return 1
  rpm -qp --requires "$rpm_path" 2>/dev/null | grep -q 'libdisplay-info\.so\.2' && return 1
  rpm -qp --provides "$rpm_path" 2>/dev/null | grep -q 'libaquamarine\.so\.8' || return 1
  return 0
}

# Fedora 44 only — this rebuild is pinned to F44's specific libdisplay-info
# ABI break, so a generic "is this Fedora" check is not enough (RFC-0038 §8.1).
# Prefers VERSION_ID from os-release; falls back to the "release 44" text in
# /etc/fedora-release. Both paths are overridable so tests never read the
# real host files.
_hab_fedora_44() {
  if [ -r "$ATLAS_HYPR_OS_RELEASE_FILE" ]; then
    if grep -qm1 '^ID=fedora$' "$ATLAS_HYPR_OS_RELEASE_FILE" 2>/dev/null &&
       grep -Eqm1 '^VERSION_ID="?44"?$' "$ATLAS_HYPR_OS_RELEASE_FILE" 2>/dev/null; then
      return 0
    fi
  fi
  [ -r "$ATLAS_HYPR_FEDORA_RELEASE_FILE" ] &&
    grep -Eqm1 'release 44\b' "$ATLAS_HYPR_FEDORA_RELEASE_FILE" 2>/dev/null
}

command -v dnf      >/dev/null 2>&1 || _hab_die "dnf required on PATH"
command -v rpm      >/dev/null 2>&1 || _hab_die "rpm required on PATH"
command -v rpmbuild >/dev/null 2>&1 || _hab_die "rpmbuild required on PATH"
_hab_fedora_44 || _hab_die "this helper only runs on Fedora 44 (checked $ATLAS_HYPR_OS_RELEASE_FILE and $ATLAS_HYPR_FEDORA_RELEASE_FILE)"

mkdir -p "$ATLAS_HYPR_RPM_DIR" || _hab_die "cannot create $ATLAS_HYPR_RPM_DIR"

if _hab_gate "$_HAB_OUT_RPM"; then
  _hab_log "already built and gated: $_HAB_OUT_RPM"
  exit 0
fi

# Isolated, disposable workspace. Never $HOME/rpmbuild — nothing here
# survives a failed or successful run except the one gated artifact staged
# into $ATLAS_HYPR_RPM_DIR below.
_HAB_BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/atlas-hypr-build.XXXXXX")" || _hab_die "mktemp failed"
trap '[ -n "${_HAB_BUILD_ROOT:-}" ] && rm -rf "$_HAB_BUILD_ROOT"' EXIT

mkdir -p "$_HAB_BUILD_ROOT"/{SOURCES,SPECS,BUILD,RPMS,SRPMS,BUILDROOT,mock-result}

( cd "$_HAB_BUILD_ROOT" && dnf download --source --repoid="$ATLAS_HYPR_COPR_REPOID" aquamarine ) ||
  _hab_die "failed to download aquamarine source RPM from $ATLAS_HYPR_COPR_REPOID"
_HAB_SRPM="$_HAB_BUILD_ROOT/$_HAB_SRPM_NAME"
[ -f "$_HAB_SRPM" ] || _hab_die "expected source RPM not found: $_HAB_SRPM"

rpm --define "_topdir $_HAB_BUILD_ROOT" -i "$_HAB_SRPM" || _hab_die "failed to unpack source RPM"
_HAB_SPEC="$_HAB_BUILD_ROOT/SPECS/aquamarine.spec"
[ -f "$_HAB_SPEC" ] || _hab_die "expected spec not found after unpack: $_HAB_SPEC"

sed -i "s/^Release:.*/Release:        $_HAB_RELEASE/" "$_HAB_SPEC" || _hab_die "failed to edit spec Release tag"
grep -qF "Release:        $_HAB_RELEASE" "$_HAB_SPEC" || _hab_die "Release tag was not pinned in the spec"

rpmbuild --define "_topdir $_HAB_BUILD_ROOT" -bs "$_HAB_SPEC" || _hab_die "failed to rebuild the tagged source RPM"
_HAB_TAGGED_SRPM="$_HAB_BUILD_ROOT/SRPMS/$_HAB_TAGGED_SRPM_NAME"
[ -f "$_HAB_TAGGED_SRPM" ] || _hab_die "expected tagged source RPM not found: $_HAB_TAGGED_SRPM"

_HAB_BUILT_RPM=""

if command -v mock >/dev/null 2>&1; then
  _hab_log "building in mock chroot $ATLAS_HYPR_MOCK_CHROOT"
  if mock -r "$ATLAS_HYPR_MOCK_CHROOT" --resultdir="$_HAB_BUILD_ROOT/mock-result" --rebuild "$_HAB_TAGGED_SRPM"; then
    _HAB_BUILT_RPM="$_HAB_BUILD_ROOT/mock-result/$_HAB_RPM_NAME"
    [ -f "$_HAB_BUILT_RPM" ] || _HAB_BUILT_RPM=""
  else
    _hab_log "mock build failed; falling back to host rpmbuild + dnf builddep"
  fi
else
  _hab_log "mock not found on PATH; falling back to host rpmbuild + dnf builddep"
fi

if [ -z "$_HAB_BUILT_RPM" ]; then
  dnf builddep -y "$_HAB_SPEC" || _hab_die "dnf builddep failed"
  rpmbuild --define "_topdir $_HAB_BUILD_ROOT" -bb "$_HAB_SPEC" || _hab_die "host rpmbuild -bb failed"
  _HAB_BUILT_RPM="$(find "$_HAB_BUILD_ROOT/RPMS" -type f -name "$_HAB_RPM_NAME" -print -quit 2>/dev/null || true)"
fi

[ -n "$_HAB_BUILT_RPM" ] && [ -f "$_HAB_BUILT_RPM" ] || _hab_die "neither mock nor host rpmbuild produced $_HAB_RPM_NAME"

_hab_gate "$_HAB_BUILT_RPM" || _hab_die "GATE FAILED: built RPM has wrong linkage ($_HAB_BUILT_RPM)"

cp -f "$_HAB_BUILT_RPM" "$_HAB_OUT_RPM" || _hab_die "failed to stage the built RPM into $ATLAS_HYPR_RPM_DIR"
_hab_gate "$_HAB_OUT_RPM" || _hab_die "GATE FAILED after staging: $_HAB_OUT_RPM"

_hab_log "built and gated: $_HAB_OUT_RPM"
