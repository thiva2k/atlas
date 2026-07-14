#!/usr/bin/env bash
# RFC-0028: the RPM query cache. `rpm`, `dnf` and `sudo` are shadowed with shell
# FUNCTIONS (functions beat PATH), so no real package manager is touched. A mock
# `rpm` appends one byte per call to $RPM_CALLS, so `wc -c` is the fork count.
# Each case runs in a child bash so the stubs never leak into the suite shell.

SRC='source "$ATLAS_ROOT/internal/log.sh"; source "$ATLAS_ROOT/internal/error.sh"; source "$ATLAS_ROOT/internal/os.sh"'

# --- 1. presence is memoised: two queries, one fork, same answer ---------------
out="$(bash -c "$SRC"'
  RPM_CALLS="$(mktemp)"; PRESENT="git"
  rpm() { printf x >> "$RPM_CALLS"; [ "$1" = "-q" ] && case " $PRESENT " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }
  os::pkg_installed git; r1=$?
  os::pkg_installed git; r2=$?
  printf "%s %s %s\n" "$r1" "$r2" "$(wc -c < "$RPM_CALLS" | tr -d " ")"
')"
assert_eq "presence: installed pkg memoised (2 queries, 1 fork)" "$out" "0 0 1"

# --- 2. a NEGATIVE result is memoised too (rc 1 cached, still one fork) ---------
out="$(bash -c "$SRC"'
  RPM_CALLS="$(mktemp)"; PRESENT=""
  rpm() { printf x >> "$RPM_CALLS"; [ "$1" = "-q" ] && case " $PRESENT " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }
  os::pkg_installed absentpkg; r1=$?
  os::pkg_installed absentpkg; r2=$?
  printf "%s %s %s\n" "$r1" "$r2" "$(wc -c < "$RPM_CALLS" | tr -d " ")"
')"
assert_eq "presence: absent pkg memoised (rc 1 cached, 1 fork)" "$out" "1 1 1"

# --- 3. os::dnf_install flushes on SUCCESS: the next query re-forks and re-reads -
out="$(bash -c "$SRC"'
  RPM_CALLS="$(mktemp)"; PRESENT=""
  rpm() { printf x >> "$RPM_CALLS"; [ "$1" = "-q" ] && case " $PRESENT " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }
  dnf() { PRESENT="foo"; return 0; }        # the install makes foo present
  sudo() { "$@"; }
  os::pkg_installed foo; before=$?           # caches "absent"
  os::dnf_install foo >/dev/null 2>&1        # success -> flush
  os::pkg_installed foo; after=$?            # must re-fork and see present
  printf "%s %s %s\n" "$before" "$after" "$(wc -c < "$RPM_CALLS" | tr -d " ")"
')"
assert_eq "flush on dnf success: stale 'absent' is dropped (re-forks to present)" "$out" "1 0 2"

# --- 4. the sharp one: dnf FAILS after mutating state -> flush still happens -----
out="$(bash -c "$SRC"'
  RPM_CALLS="$(mktemp)"; PRESENT=""
  rpm() { printf x >> "$RPM_CALLS"; [ "$1" = "-q" ] && case " $PRESENT " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }
  dnf() { PRESENT="foo"; return 1; }         # packages landed, but dnf exits non-zero
  sudo() { "$@"; }
  os::pkg_installed foo                       # caches "absent"
  os::dnf_install foo >/dev/null 2>&1; irc=$? # returns 1, MUST still flush
  os::pkg_installed foo; after=$?             # must re-read reality: present
  printf "install_rc=%s after=%s\n" "$irc" "$after"
')"
assert_eq "flush on dnf FAILURE: invalidation does not depend on dnf success" "$out" "install_rc=1 after=0"

# --- 5. owner: stdout + rc contract preserved (no memoisation asserted) --------
out="$(bash -c "$SRC"'
  rpm() { [ "$1" = "-qf" ] && case "$2" in /owned) printf "ownerpkg-1.0\n"; return 0 ;; *) return 1 ;; esac; }
  o1="$(os::pkg_owner /owned)"; r1=$?
  o2="$(os::pkg_owner /nope)";  r2=$?
  printf "[%s] %s [%s] %s\n" "$o1" "$r1" "$o2" "$r2"
')"
assert_eq "owner: prints pkg & rc0 when owned, prints empty & rc1 when not" "$out" "[ownerpkg-1.0] 0 [] 1"

# --- 6. subshell isolation AND intra-subshell memoisation, together -------------
# Each ( … ) inherits only a copy of the map, so two sibling subshells cannot
# share a cached answer (each forks once); within a subshell the second query is
# memoised. Two subshells, two queries each => exactly two forks.
out="$(bash -c "$SRC"'
  RPM_CALLS="$(mktemp)"; PRESENT="git"
  rpm() { printf x >> "$RPM_CALLS"; [ "$1" = "-q" ] && case " $PRESENT " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }
  ( os::pkg_installed git; os::pkg_installed git )   # subshell A: 1 fork (2nd memoised)
  ( os::pkg_installed git; os::pkg_installed git )   # subshell B: 1 fork (fresh copy)
  printf "%s\n" "$(wc -c < "$RPM_CALLS" | tr -d " ")"
')"
assert_eq "subshell isolation: siblings each fork once, memoised within (2 total)" "$out" "2"
