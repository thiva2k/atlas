#!/usr/bin/env bash
# Proves the assertion library itself works.
assert_eq       "assert_eq matches equal strings"      "abc" "abc"
assert_contains "assert_contains finds a substring"    "hello world" "world"
assert_status   "assert_status reads true's exit code" 0 true
assert_status   "assert_status reads false's exit code" 1 false
