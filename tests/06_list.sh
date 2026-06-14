#!/usr/bin/env bash
. "$(dirname "$0")/_harness.sh"

secret set TEST_A <<< 'valueA' >/dev/null 2>&1
printf '%s\n' 'TEST_MISSING' >> "$SHELL_SECRET_MANIFEST"

out="$(secret list 2>/dev/null)"
printf '%s\n' "$out" | grep -q '✓ TEST_A';            assert_eq "present key marked ✓" "0" "$?"
printf '%s\n' "$out" | grep -q '✗ TEST_MISSING';      assert_eq "missing key marked ✗" "0" "$?"

_report
