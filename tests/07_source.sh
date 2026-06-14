#!/usr/bin/env bash
. "$(dirname "$0")/_harness.sh"

# Seed a real item + manifest, then source the module fresh in a child shell
# and confirm the value lands in the environment with NO explicit load call.
security add-generic-password -U -s "$SHELL_SECRET_SERVICE" -a TEST_A -w 'srcval' 2>/dev/null
printf '%s\n' 'TEST_A' >> "$SHELL_SECRET_MANIFEST"

got="$(
  SHELL_SECRET_SERVICE="$SHELL_SECRET_SERVICE" \
  SHELL_SECRET_MANIFEST="$SHELL_SECRET_MANIFEST" \
  bash -c '. "'"$REPO"'/shells/keychain"; printf %s "$TEST_A"'
)"
assert_eq "value auto-exported on source" "srcval" "$got"

# Module must parse cleanly in BOTH shells.
bash -n "$REPO/shells/keychain"; assert_eq "bash parses keychain" "0" "$?"
zsh  -n "$REPO/shells/keychain"; assert_eq "zsh parses keychain"  "0" "$?"

_report
