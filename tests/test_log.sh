#!/usr/bin/env bash
source "$ATLAS_ROOT/internal/log.sh"

# info is emitted at default level
out="$(ATLAS_LOG_LEVEL=info log::info "hello" 2>&1 1>/dev/null)"
assert_contains "info line has level"   "$out" "INFO"
assert_contains "info line has message" "$out" "hello"
assert_contains "info line has scope"   "$out" "[atlas]"

# debug is suppressed when the floor is info
out="$(ATLAS_LOG_LEVEL=info log::debug "quiet" 2>&1 1>/dev/null)"
assert_eq "debug suppressed at info level" "$out" ""

# scope override is honored
out="$(ATLAS_LOG_SCOPE=git log::info "scoped" 2>&1 1>/dev/null)"
assert_contains "scope override applies" "$out" "[git]"

# every call persists to the logfile
logf="$ATLAS_STATE_DIR/logs/atlas-$(date +%Y%m%d).log"
log::warn "persist-me" 2>/dev/null
assert_contains "logfile captured the line" "$(cat "$logf")" "persist-me"
