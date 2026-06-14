#!/usr/bin/env bash
. "$(dirname "$0")/_harness.sh"

# Seed an item directly via security (bypassing secret set, not built yet).
security add-generic-password -U -s "$SHELL_SECRET_SERVICE" -a TEST_KEY -w 'abc=12/3+x' 2>/dev/null

assert_eq "get returns exact value (round-trips =,/,+)" "abc=12/3+x" "$(secret get TEST_KEY)"

secret get TEST_MISSING >/dev/null 2>&1
assert_eq "get of missing item is non-zero" "1" "$?"

_report
