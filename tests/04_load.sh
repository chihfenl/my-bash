#!/usr/bin/env bash
. "$(dirname "$0")/_harness.sh"

# Two real items + one manifest name with no Keychain item.
secret set TEST_A <<< 'valueA' >/dev/null 2>&1
secret set TEST_B <<< 'valueB' >/dev/null 2>&1
printf '%s\n' 'TEST_MISSING' >> "$SHELL_SECRET_MANIFEST"

unset TEST_A TEST_B TEST_MISSING
load_secrets

assert_eq "present key A exported"          "valueA" "${TEST_A:-}"
assert_eq "present key B exported"          "valueB" "${TEST_B:-}"
assert_eq "missing item left unset (empty)" ""       "${TEST_MISSING:-}"

# Missing manifest => clean no-op, returns 0.
SHELL_SECRET_MANIFEST="/nonexistent/path/secrets.local" load_secrets
assert_eq "missing manifest is a no-op"     "0"      "$?"

_report
