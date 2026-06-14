#!/usr/bin/env bash
. "$(dirname "$0")/_harness.sh"

secret set TEST_A <<< 'valueA' >/dev/null 2>&1
secret set TEST_B <<< 'valueB' >/dev/null 2>&1

secret rm TEST_A >/dev/null 2>&1
secret get TEST_A >/dev/null 2>&1
assert_eq "removed item gone from Keychain" "1" "$?"
assert_eq "removed name gone from manifest" "0" "$(grep -cxF TEST_A "$SHELL_SECRET_MANIFEST")"
assert_eq "other name still in manifest"    "1" "$(grep -cxF TEST_B "$SHELL_SECRET_MANIFEST")"

# Removing something absent is tolerated (returns 0).
secret rm TEST_MISSING >/dev/null 2>&1
assert_eq "rm of absent name is tolerated"  "0" "$?"

_report
