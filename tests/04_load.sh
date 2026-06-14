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


# A manifest name that is a valid Keychain account but NOT a valid shell
# identifier must be skipped silently (no `export: not a valid identifier`).
security add-generic-password -U -s "$SHELL_SECRET_SERVICE" -a 'MY-VAR' -w 'x' 2>/dev/null
printf '%s\n' 'MY-VAR' >> "$SHELL_SECRET_MANIFEST"
_errf="$(mktemp)"
load_secrets 2>"$_errf"
assert_eq "invalid manifest name: silent startup" "" "$(cat "$_errf")"
rm -f "$_errf"

_report
