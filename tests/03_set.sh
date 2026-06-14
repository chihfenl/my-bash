#!/usr/bin/env bash
. "$(dirname "$0")/_harness.sh"

# Hidden-prompt input is fed via herestring (works in bash and zsh).
secret set TEST_KEY <<< 'abc=12/3+x' >/dev/null 2>&1
assert_eq "set then get round-trips"        "abc=12/3+x" "$(secret get TEST_KEY)"
assert_eq "set added name to manifest"      "1"          "$(grep -cxF TEST_KEY "$SHELL_SECRET_MANIFEST")"

# Idempotent: setting again must not duplicate the manifest line.
secret set TEST_KEY <<< 'newval' >/dev/null 2>&1
assert_eq "set updates value"               "newval"     "$(secret get TEST_KEY)"
assert_eq "manifest name not duplicated"    "1"          "$(grep -cxF TEST_KEY "$SHELL_SECRET_MANIFEST")"

# Empty value is rejected (no item, no manifest line).
secret set TEST_A <<< '' >/dev/null 2>&1
assert_eq "empty value aborts (non-zero)"   "1"          "$?"
assert_eq "aborted name not in manifest"    "0"          "$(grep -cxF TEST_A "$SHELL_SECRET_MANIFEST")"

# Invalid name rejected.
secret set "bad-name" <<< 'x' >/dev/null 2>&1
assert_eq "invalid name rejected"           "1"          "$?"

_report
