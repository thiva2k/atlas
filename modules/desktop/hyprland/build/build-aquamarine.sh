#!/usr/bin/env bash
# Atlas — rebuild aquamarine 0.9.5 against Fedora 44's libdisplay-info.so.3.
# Produces ~/atlas-hypr-rpms/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm.
# Idempotent: if the artifact already exists and passes the gate, it exits 0.
set -euo pipefail
REPO="copr:copr.fedorainfracloud.org:solopasha:hyprland"
OUT="$HOME/atlas-hypr-rpms"
RPM="$OUT/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm"

gate() {  # passes iff it links .so.3, not .so.2, and provides .so.8
  local req prov
  req="$(rpm -qp --requires "$1" 2>/dev/null)"
  prov="$(rpm -qp --provides "$1" 2>/dev/null)"
  printf '%s\n' "$req"  | grep -q 'libdisplay-info.so.3' &&
  ! printf '%s\n' "$req"  | grep -q 'libdisplay-info.so.2' &&
  printf '%s\n' "$prov" | grep -q 'libaquamarine.so.8'
}

command -v dnf >/dev/null || { echo "dnf required" >&2; exit 1; }
. /etc/os-release 2>/dev/null || true
[ "${ID:-}" = fedora ] && [ "${VERSION_ID:-}" = 44 ] || { echo "Fedora 44 host required" >&2; exit 1; }

if [ -f "$RPM" ] && gate "$RPM"; then echo "already built: $RPM"; exit 0; fi

mkdir -p "$OUT"; cd "$OUT"
[ -f aquamarine-0.9.5-2.fc44.src.rpm ] || \
  dnf download --source --repoid="$REPO" aquamarine
WORK="$(mktemp -d "${TMPDIR:-/tmp}/atlas-aqua.XXXXXX")" || { echo "mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT
TOP="$WORK/rpmbuild"
rpm -i --define "_topdir $TOP" "$OUT/aquamarine-0.9.5-2.fc44.src.rpm"
sed -i 's/^Release:.*/Release:        2%{?dist}.atlas1/' "$TOP/SPECS/aquamarine.spec"
rpmbuild -bs --define "_topdir $TOP" "$TOP/SPECS/aquamarine.spec"
mock -r fedora-44-x86_64 --rebuild "$TOP/SRPMS/aquamarine-0.9.5-2.fc44.atlas1.src.rpm"
cp /var/lib/mock/fedora-44-x86_64/result/aquamarine-0.9.5-2.fc44.atlas1.x86_64.rpm "$OUT/"
gate "$RPM" || { echo "GATE FAILED: built RPM has wrong linkage" >&2; exit 1; }
echo "built and gated: $RPM"
