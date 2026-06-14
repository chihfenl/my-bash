#!/usr/bin/env bash
. "$(dirname "$0")/_harness.sh"

type secret       >/dev/null 2>&1; assert_eq "secret is defined"        "0" "$?"
type load_secrets >/dev/null 2>&1; assert_eq "load_secrets is defined"  "0" "$?"

secret bogus 2>/dev/null;          assert_eq "unknown subcommand exits 2" "2" "$?"
secret 2>/dev/null;                assert_eq "no subcommand exits 2"      "2" "$?"

# invalid env-var names are rejected by set/get
secret get "1bad" 2>/dev/null;     assert_eq "leading-digit name rejected" "1" "$?"
secret get "a-b"  2>/dev/null;     assert_eq "hyphen name rejected"        "1" "$?"

_report
