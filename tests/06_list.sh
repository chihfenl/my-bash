#!/usr/bin/env bash
. "$(dirname "$0")/_harness.sh"

secret set TEST_A <<< 'valueA' >/dev/null 2>&1
printf '%s\n' 'TEST_MISSING' >> "$SHELL_SECRET_MANIFEST"

out="$(secret list 2>/dev/null)"
printf '%s\n' "$out" | grep -q '✓ TEST_A';            assert_eq "present key marked ✓" "0" "$?"
printf '%s\n' "$out" | grep -q '✗ TEST_MISSING';      assert_eq "missing key marked ✗" "0" "$?"


# An invalid shell identifier must be skipped (consistent with load_secrets),
# not shown in the listing.
printf '%s\n' 'BAD-NAME' >> "$SHELL_SECRET_MANIFEST"
out2="$(secret list 2>/dev/null)"
printf '%s\n' "$out2" | grep -q 'BAD-NAME'; assert_eq "invalid name not listed" "1" "$?"

# No-manifest path returns 0.
SHELL_SECRET_MANIFEST="/nonexistent/path/secrets" secret list >/dev/null 2>&1
assert_eq "no-manifest list exits 0" "0" "$?"

_report
