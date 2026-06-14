# Shared harness for keychain tests. SOURCE me from a tests/NN_*.sh file.
# Isolates side effects: a throwaway Keychain service + a temp manifest, so
# tests never read or write your real secrets. Cleans up on exit.
set -u

# NOTE: assumes test files live directly in tests/ (siblings of this harness),
# so $0's dirname is tests/ under both bash and zsh. Don't nest test files in
# subdirectories without revisiting this.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
export SHELL_SECRET_SERVICE="shell-secret-test-$$"
TEST_MANIFEST="$(mktemp)"
export SHELL_SECRET_MANIFEST="$TEST_MANIFEST"

_FAILS=0
assert_eq() { # desc expected actual
  if [ "$2" = "$3" ]; then
    printf 'ok   - %s\n' "$1"
  else
    printf 'FAIL - %s\n        expected=[%s]\n        actual=  [%s]\n' "$1" "$2" "$3"
    _FAILS=$((_FAILS + 1))
  fi
}
_report() {
  if [ "$_FAILS" -eq 0 ]; then
    printf 'PASS\n'; exit 0
  else
    printf '%d FAILURES\n' "$_FAILS"; exit 1
  fi
}

_keychain_cleanup() {
  if [ -f "$TEST_MANIFEST" ]; then
    while IFS= read -r _n || [ -n "$_n" ]; do
      case "$_n" in ""|'#'*) continue ;; esac
      security delete-generic-password -s "$SHELL_SECRET_SERVICE" -a "$_n" >/dev/null 2>&1 || true
    done < "$TEST_MANIFEST"
  fi
  for _n in TEST_KEY TEST_A TEST_B TEST_MISSING; do
    security delete-generic-password -s "$SHELL_SECRET_SERVICE" -a "$_n" >/dev/null 2>&1 || true
  done
  rm -f "$TEST_MANIFEST"
}
trap _keychain_cleanup EXIT

# Source the unit under test (picks up the isolated service + temp manifest).
. "$REPO/shells/keychain"
