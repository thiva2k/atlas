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
# (default $ATLAS_HYPR_RPM_DIR: $HOME/atlas-hypr-rpms), validated as a whole
# NEVRA + soname + integrity gate (see _hab_gate).
# Idempotent: exits 0 immediately if a gated artifact is already staged.
#
# The binary RPM is built through mock ONLY (RFC-0038 §5): mock builds inside a
# disposable chroot and resolves its build requirements there, never on the
# host, so this script creates no second unrecorded host dnf/rpm transaction.
# Host rpmbuild is used only to re-roll the modified *source* RPM (source-only,
# -bs) inside a private, disposable _topdir under $TMPDIR — that mutates no
# packages. There is no host binary-rebuild fallback; when mock or its
# prerequisites are missing the build fails clearly. Nothing here touches
# ~/rpmbuild or any path outside the disposable workspace and
# $ATLAS_HYPR_RPM_DIR, and the final artifact is staged atomically only after
# the gate passes.
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
_HAB_NAME="aquamarine"
_HAB_VERSION="0.9.5"
_HAB_RENDERED_RELEASE="2.fc44.atlas1"
_HAB_ARCH="x86_64"
_HAB_SRPM_NAME="aquamarine-0.9.5-2.fc44.src.rpm"
_HAB_TAGGED_SRPM_NAME="aquamarine-0.9.5-2.fc44.atlas1.src.rpm"
_HAB_RPM_NAME="aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"
_HAB_OUT_RPM="$ATLAS_HYPR_RPM_DIR/$_HAB_RPM_NAME"

_hab_log() { printf 'build-aquamarine: %s\n' "$*" >&2; }
_hab_die() { _hab_log "$*"; exit 1; }

# A built RPM passes the gate iff, as a whole (RFC-0038 §5):
#   - name/version/release/arch are EXACTLY aquamarine-0.9.5-2.fc44.atlas1.x86_64
#     (the release pin is also the RPM version-ordering guarantee),
#   - requires libdisplay-info.so.3 and NEVER libdisplay-info.so.2,
#   - provides libaquamarine.so.8 (the soname Hyprland hard-links),
#   - passes rpm payload/header digest integrity (--nosignature: the artifact
#     is a locally mock-built, intentionally unsigned RPM).
# A pre-existing artifact is always re-validated here, never trusted by name.
_hab_gate() {
  local rpm_path="$1" nevra name ver rel arch
  [ -f "$rpm_path" ] || return 1
  nevra="$(rpm -qp --qf '%{NAME} %{VERSION} %{RELEASE} %{ARCH}\n' "$rpm_path" 2>/dev/null)" || return 1
  read -r name ver rel arch <<<"$nevra" || return 1
  [ "$name" = "$_HAB_NAME" ] || return 1
  [ "$ver" = "$_HAB_VERSION" ] || return 1
  [ "$rel" = "$_HAB_RENDERED_RELEASE" ] || return 1
  [ "$arch" = "$_HAB_ARCH" ] || return 1
  rpm -qp --requires "$rpm_path" 2>/dev/null | grep -q 'libdisplay-info\.so\.3' || return 1
  rpm -qp --requires "$rpm_path" 2>/dev/null | grep -q 'libdisplay-info\.so\.2' && return 1
  rpm -qp --provides "$rpm_path" 2>/dev/null | grep -q 'libaquamarine\.so\.8' || return 1
  rpm -K --nosignature "$rpm_path" >/dev/null 2>&1 || return 1
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

# Host rpmbuild here only re-rolls the *source* RPM (-bs) — no package is
# installed, nothing on the host mutates, and everything lands in the private
# disposable _topdir.
rpmbuild --define "_topdir $_HAB_BUILD_ROOT" -bs "$_HAB_SPEC" || _hab_die "failed to rebuild the tagged source RPM"
_HAB_TAGGED_SRPM="$_HAB_BUILD_ROOT/SRPMS/$_HAB_TAGGED_SRPM_NAME"
[ -f "$_HAB_TAGGED_SRPM" ] || _hab_die "expected tagged source RPM not found: $_HAB_TAGGED_SRPM"

# Binary build is mock-only: it happens in a disposable chroot, so build
# requirements never touch the host and no unrecorded host transaction is
# created. There is NO host binary-rebuild fallback (RFC-0038 §5).
command -v mock >/dev/null 2>&1 ||
  _hab_die "mock is required to build aquamarine; host build fallback is not permitted (RFC-0038 §5). Install: sudo dnf install mock && sudo usermod -aG mock \"\$USER\""

# Fresh result dir per run — never reuse stale mock output.
_HAB_MOCK_RESULT="$_HAB_BUILD_ROOT/mock-result"
rm -rf "$_HAB_MOCK_RESULT"
mkdir -p "$_HAB_MOCK_RESULT"

_hab_log "building in mock chroot $ATLAS_HYPR_MOCK_CHROOT"
mock -r "$ATLAS_HYPR_MOCK_CHROOT" --resultdir="$_HAB_MOCK_RESULT" --rebuild "$_HAB_TAGGED_SRPM" ||
  _hab_die "mock build failed in chroot $ATLAS_HYPR_MOCK_CHROOT"

_HAB_BUILT_RPM="$_HAB_MOCK_RESULT/$_HAB_RPM_NAME"
[ -f "$_HAB_BUILT_RPM" ] || _hab_die "mock did not produce $_HAB_RPM_NAME"

_hab_gate "$_HAB_BUILT_RPM" || _hab_die "GATE FAILED: built RPM did not pass NEVRA/soname/integrity gate ($_HAB_BUILT_RPM)"

# Stage atomically: copy into a same-dir temp, gate it there, then mv into
# place so a concurrent reader never sees a half-written artifact.
_HAB_STAGE_TMP="$(mktemp "$ATLAS_HYPR_RPM_DIR/.stage.XXXXXX")" || _hab_die "cannot create staging temp in $ATLAS_HYPR_RPM_DIR"
cp -f "$_HAB_BUILT_RPM" "$_HAB_STAGE_TMP" || { rm -f "$_HAB_STAGE_TMP"; _hab_die "failed to copy built RPM to staging temp"; }
_hab_gate "$_HAB_STAGE_TMP" || { rm -f "$_HAB_STAGE_TMP"; _hab_die "GATE FAILED on staged copy"; }
mv -f "$_HAB_STAGE_TMP" "$_HAB_OUT_RPM" || { rm -f "$_HAB_STAGE_TMP"; _hab_die "failed to stage the built RPM into $ATLAS_HYPR_RPM_DIR"; }
_hab_gate "$_HAB_OUT_RPM" || _hab_die "GATE FAILED after staging: $_HAB_OUT_RPM"

_hab_log "built and gated: $_HAB_OUT_RPM"
