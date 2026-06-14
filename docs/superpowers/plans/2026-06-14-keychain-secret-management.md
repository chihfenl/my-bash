# Keychain-Backed Secret Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a reusable `keychain` shell module to the `my-bash` repo that stores API keys in the macOS Keychain and auto-exports them as environment variables at shell startup, replacing the plaintext `~/.shells/aws` file and per-project `.env` files.

**Architecture:** A single value-free file `shells/keychain` (symlinked to `~/.shells/keychain` by `install.sh`, sourced by both `bashrc` and `zshrc`) provides a `secret` command and a `load_secrets` startup loader. Each secret is one login-Keychain generic-password item (`service=$SHELL_SECRET_SERVICE`, `account=`env-var name). A local untracked manifest (`~/.shells/secrets.local`) lists which names to auto-export. Secret values live only in the Keychain.

**Tech Stack:** POSIX-compatible shell (works in bash + zsh), macOS `security(1)` CLI, a homegrown shell test harness.

**Spec:** `docs/superpowers/specs/2026-06-14-keychain-secret-management-design.md`

**Conventions for every commit in this plan:** keep `-m` messages lowercase-type style (`feat:`, `test:`, `docs:`, `chore:`) matching the repo, and end each commit message with the trailer:
```
Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
```
Work happens on branch `keychain-secret-management` (already created).

---

## File Structure

| File | Create/Modify | Responsibility |
|---|---|---|
| `shells/keychain` | Create | The whole feature: `secret` dispatcher, helpers, `load_secrets`. Value-free. |
| `shells/secrets.local.example` | Create | Committed manifest template/checklist. |
| `tests/_harness.sh` | Create | Shared test setup: isolated Keychain service + temp manifest + asserts + cleanup. |
| `tests/run.sh` | Create | Runs every `tests/NN_*.sh` under both bash and zsh. |
| `tests/01_dispatch.sh` … `tests/07_source.sh` | Create | One behavioral test file per task. |
| `bashrc`, `zshrc` | Modify | Source `~/.shells/keychain` after the `exports` line. |
| `install.sh` | Modify | Add one `link shells/keychain …` line. |
| `README.md` | Modify | Rewrite "Secrets" section; add `keychain` to layout table. |
| `.gitignore` | Verify | Already covers `secrets.local` (`*.local`); confirm no change needed. |

---

## Task 1: Test harness + `keychain` skeleton

**Files:**
- Create: `tests/_harness.sh`
- Create: `tests/run.sh`
- Create: `tests/01_dispatch.sh`
- Create: `shells/keychain`

- [ ] **Step 1: Write the shared harness**

Create `tests/_harness.sh`:

```sh
# Shared harness for keychain tests. SOURCE me from a tests/NN_*.sh file.
# Isolates side effects: a throwaway Keychain service + a temp manifest, so
# tests never read or write your real secrets. Cleans up on exit.
set -u

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
_report() { if [ "$_FAILS" -eq 0 ]; then printf 'PASS\n'; else printf '%d FAILURES\n' "$_FAILS"; exit 1; fi; }

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
```

- [ ] **Step 2: Write the runner**

Create `tests/run.sh`:

```sh
#!/usr/bin/env bash
# Run every tests/NN_*.sh under both bash and zsh (cross-shell guarantee).
cd "$(dirname "$0")" || exit 1
status=0
for f in [0-9]*_*.sh; do
  [ -e "$f" ] || continue
  for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || continue
    printf '== %s (%s) ==\n' "$f" "$sh"
    "$sh" "$f" || status=1
  done
done
[ "$status" -eq 0 ] && printf '\nSUITE PASS\n' || printf '\nSUITE FAIL\n'
exit "$status"
```

- [ ] **Step 3: Write the failing test**

Create `tests/01_dispatch.sh`:

```sh
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
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/01_dispatch.sh`
Expected: FAIL — `shells/keychain` does not exist, so sourcing errors / `secret` undefined.

- [ ] **Step 5: Write the minimal implementation**

Create `shells/keychain`:

```sh
# keychain — macOS Keychain-backed secret loading. Sourced by both bash & zsh.
#
# Stores NO secret values; this file is pure logic. Each secret is one login-
# Keychain generic-password item (service = $SHELL_SECRET_SERVICE, account =
# the env-var name). A local, untracked manifest ($SHELL_SECRET_MANIFEST) lists
# which names to auto-export at shell startup. Inert if `security` is absent.
#
#   secret set NAME    store/update a value (hidden prompt) + add to manifest
#   secret get NAME    print one value
#   secret list        show manifest names, ✓ present / ✗ missing in Keychain
#   secret rm  NAME    delete the Keychain item + remove from manifest
#   secret reload      re-run the startup loader in the current shell

command -v security >/dev/null 2>&1 || return 0   # non-macOS: no-op

: "${SHELL_SECRET_SERVICE:=shell-secret}"
: "${SHELL_SECRET_MANIFEST:=$HOME/.shells/secrets.local}"

# 0 if $1 is a valid POSIX env-var name, non-zero otherwise.
_secret_valid_name() {
  case "$1" in
    ""|[!A-Za-z_]*)  return 1 ;;
    *[!A-Za-z0-9_]*) return 1 ;;
  esac
  return 0
}

secret() {
  local cmd="${1:-}"
  [ "$#" -gt 0 ] && shift
  case "$cmd" in
    set)    _secret_set  "$@" ;;
    get)    _secret_get  "$@" ;;
    list)   _secret_list "$@" ;;
    rm)     _secret_rm   "$@" ;;
    reload) load_secrets ;;
    *) printf 'usage: secret {set|get|list|rm|reload} [NAME]\n' >&2; return 2 ;;
  esac
}

# Stubs filled in by later tasks; defined now so `secret` and the harness load.
_secret_set()  { printf 'not implemented\n' >&2; return 1; }
_secret_get()  { _secret_valid_name "${1:-}" || { printf 'invalid name\n' >&2; return 1; }; return 1; }
_secret_list() { printf 'not implemented\n' >&2; return 1; }
_secret_rm()   { printf 'not implemented\n' >&2; return 1; }
load_secrets() { return 0; }
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/01_dispatch.sh && zsh tests/01_dispatch.sh`
Expected: both print `PASS`.

- [ ] **Step 7: Commit**

```bash
cd "$HOME/.dotfiles/my-bash"
chmod +x tests/run.sh
git add tests/_harness.sh tests/run.sh tests/01_dispatch.sh shells/keychain
git commit -m "feat: keychain module skeleton + shell test harness

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `secret get`

**Files:**
- Modify: `shells/keychain` (replace the `_secret_get` stub)
- Create: `tests/02_get.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/02_get.sh`:

```sh
#!/usr/bin/env bash
. "$(dirname "$0")/_harness.sh"

# Seed an item directly via security (bypassing secret set, not built yet).
security add-generic-password -U -s "$SHELL_SECRET_SERVICE" -a TEST_KEY -w 'abc=12/3+x' 2>/dev/null

assert_eq "get returns exact value (round-trips =,/,+)" "abc=12/3+x" "$(secret get TEST_KEY)"

secret get TEST_MISSING >/dev/null 2>&1
assert_eq "get of missing item is non-zero" "1" "$?"

_report
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/02_get.sh`
Expected: FAIL — stub `_secret_get` returns 1 and prints nothing, so the round-trip assert fails.

- [ ] **Step 3: Write the implementation**

In `shells/keychain`, replace the `_secret_get` stub line:

```sh
_secret_get()  { _secret_valid_name "${1:-}" || { printf 'invalid name\n' >&2; return 1; }; return 1; }
```

with:

```sh
_secret_get() {
  local name="${1:-}" value
  if ! _secret_valid_name "$name"; then
    printf 'secret get: invalid name %s\n' "${name:-<empty>}" >&2; return 1
  fi
  # `security` exits 44 (not 1) when the item is missing — normalize to 0/1
  # so callers get a predictable contract.
  value=$(security find-generic-password -s "$SHELL_SECRET_SERVICE" -a "$name" -w 2>/dev/null) || return 1
  printf '%s\n' "$value"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/02_get.sh && zsh tests/02_get.sh`
Expected: both `PASS`.

- [ ] **Step 5: Commit**

```bash
cd "$HOME/.dotfiles/my-bash"
git add shells/keychain tests/02_get.sh
git commit -m "feat: secret get reads one value from the Keychain

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `secret set` + manifest append

**Files:**
- Modify: `shells/keychain` (replace `_secret_set` stub; add `_secret_manifest_add`)
- Create: `tests/03_set.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/03_set.sh`:

```sh
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/03_set.sh`
Expected: FAIL — stub `_secret_set` prints "not implemented" and stores nothing.

- [ ] **Step 3: Write the implementation**

In `shells/keychain`, replace the `_secret_set` stub line:

```sh
_secret_set()  { printf 'not implemented\n' >&2; return 1; }
```

with these two functions:

```sh
_secret_manifest_add() {
  local name="$1"
  if [ ! -f "$SHELL_SECRET_MANIFEST" ]; then
    mkdir -p "$(dirname "$SHELL_SECRET_MANIFEST")"
    {
      printf '# Auto-loaded into every shell from the macOS Keychain (service "%s").\n' "$SHELL_SECRET_SERVICE"
      printf '# One env-var name per line. Manage with `secret set` / `secret rm`.\n'
      printf '# Values live ONLY in the Keychain — never here.\n'
    } > "$SHELL_SECRET_MANIFEST"
  fi
  grep -qxF "$name" "$SHELL_SECRET_MANIFEST" 2>/dev/null \
    || printf '%s\n' "$name" >> "$SHELL_SECRET_MANIFEST"
}

_secret_set() {
  local name="${1:-}" value
  if ! _secret_valid_name "$name"; then
    printf 'secret set: invalid name %s\n' "${name:-<empty>}" >&2; return 1
  fi
  printf 'Value for %s (input hidden): ' "$name" >&2
  IFS= read -rs value
  printf '\n' >&2
  if [ -z "$value" ]; then
    printf 'secret set: empty value, aborted\n' >&2; return 1
  fi
  if ! security add-generic-password -U -s "$SHELL_SECRET_SERVICE" -a "$name" -w "$value" 2>/dev/null; then
    printf 'secret set: keychain store failed\n' >&2; unset value; return 1
  fi
  _secret_manifest_add "$name"
  printf 'stored %s\n' "$name" >&2
  unset value
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/03_set.sh && zsh tests/03_set.sh`
Expected: both `PASS`.

- [ ] **Step 5: Commit**

```bash
cd "$HOME/.dotfiles/my-bash"
git add shells/keychain tests/03_set.sh
git commit -m "feat: secret set stores in Keychain and tracks the manifest

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `load_secrets` startup loader

**Files:**
- Modify: `shells/keychain` (replace the `load_secrets` stub)
- Create: `tests/04_load.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/04_load.sh`:

```sh
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/04_load.sh`
Expected: FAIL — stub `load_secrets` exports nothing, so `TEST_A`/`TEST_B` are empty.

- [ ] **Step 3: Write the implementation**

In `shells/keychain`, replace the `load_secrets` stub line:

```sh
load_secrets() { return 0; }
```

with:

```sh
load_secrets() {
  [ -r "$SHELL_SECRET_MANIFEST" ] || return 0
  local name value
  while IFS= read -r name || [ -n "$name" ]; do
    case "$name" in ""|'#'*) continue ;; esac
    value=$(security find-generic-password -s "$SHELL_SECRET_SERVICE" -a "$name" -w 2>/dev/null) || continue
    [ -n "$value" ] && export "$name=$value"
  done < "$SHELL_SECRET_MANIFEST"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/04_load.sh && zsh tests/04_load.sh`
Expected: both `PASS`.

- [ ] **Step 5: Commit**

```bash
cd "$HOME/.dotfiles/my-bash"
git add shells/keychain tests/04_load.sh
git commit -m "feat: load_secrets exports manifest keys, skips missing/empty

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `secret rm`

**Files:**
- Modify: `shells/keychain` (replace the `_secret_rm` stub)
- Create: `tests/05_rm.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/05_rm.sh`:

```sh
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/05_rm.sh`
Expected: FAIL — stub `_secret_rm` removes nothing.

- [ ] **Step 3: Write the implementation**

In `shells/keychain`, replace the `_secret_rm` stub line:

```sh
_secret_rm()   { printf 'not implemented\n' >&2; return 1; }
```

with:

```sh
_secret_rm() {
  local name="${1:-}" tmp
  if ! _secret_valid_name "$name"; then
    printf 'secret rm: invalid name %s\n' "${name:-<empty>}" >&2; return 1
  fi
  security delete-generic-password -s "$SHELL_SECRET_SERVICE" -a "$name" >/dev/null 2>&1
  if [ -f "$SHELL_SECRET_MANIFEST" ]; then
    tmp="$(mktemp)"
    grep -vxF "$name" "$SHELL_SECRET_MANIFEST" > "$tmp" 2>/dev/null
    mv "$tmp" "$SHELL_SECRET_MANIFEST"
  fi
  printf 'removed %s\n' "$name" >&2
  return 0
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/05_rm.sh && zsh tests/05_rm.sh`
Expected: both `PASS`.

- [ ] **Step 5: Commit**

```bash
cd "$HOME/.dotfiles/my-bash"
git add shells/keychain tests/05_rm.sh
git commit -m "feat: secret rm deletes the Keychain item and manifest line

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `secret list`

**Files:**
- Modify: `shells/keychain` (replace the `_secret_list` stub)
- Create: `tests/06_list.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/06_list.sh`:

```sh
#!/usr/bin/env bash
. "$(dirname "$0")/_harness.sh"

secret set TEST_A <<< 'valueA' >/dev/null 2>&1
printf '%s\n' 'TEST_MISSING' >> "$SHELL_SECRET_MANIFEST"

out="$(secret list 2>/dev/null)"
printf '%s\n' "$out" | grep -q '✓ TEST_A';            assert_eq "present key marked ✓" "0" "$?"
printf '%s\n' "$out" | grep -q '✗ TEST_MISSING';      assert_eq "missing key marked ✗" "0" "$?"

_report
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/06_list.sh`
Expected: FAIL — stub `_secret_list` prints "not implemented".

- [ ] **Step 3: Write the implementation**

In `shells/keychain`, replace the `_secret_list` stub line:

```sh
_secret_list() { printf 'not implemented\n' >&2; return 1; }
```

with:

```sh
_secret_list() {
  if [ ! -r "$SHELL_SECRET_MANIFEST" ]; then
    printf 'no manifest (%s)\n' "$SHELL_SECRET_MANIFEST" >&2; return 0
  fi
  local name
  while IFS= read -r name || [ -n "$name" ]; do
    case "$name" in ""|'#'*) continue ;; esac
    if security find-generic-password -s "$SHELL_SECRET_SERVICE" -a "$name" -w >/dev/null 2>&1; then
      printf '  ✓ %s\n' "$name"
    else
      printf '  ✗ %s (not set)\n' "$name"
    fi
  done < "$SHELL_SECRET_MANIFEST"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/06_list.sh && zsh tests/06_list.sh`
Expected: both `PASS`.

- [ ] **Step 5: Commit**

```bash
cd "$HOME/.dotfiles/my-bash"
git add shells/keychain tests/06_list.sh
git commit -m "feat: secret list audits manifest vs Keychain presence

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Auto-load at source time + cross-shell parse check

**Files:**
- Modify: `shells/keychain` (append the source-time `load_secrets` call)
- Create: `tests/07_source.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/07_source.sh`:

```sh
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/07_source.sh`
Expected: FAIL — the module defines `load_secrets` but never calls it at source time, so `TEST_A` is empty.

- [ ] **Step 3: Write the implementation**

Append to the very end of `shells/keychain`:

```sh

load_secrets   # run at source time so every new shell gets the keys
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd "$HOME/.dotfiles/my-bash" && bash tests/07_source.sh && zsh tests/07_source.sh`
Expected: both `PASS`.

- [ ] **Step 5: Run the full suite**

Run: `cd "$HOME/.dotfiles/my-bash" && ./tests/run.sh`
Expected: every test file prints `PASS` under both bash and zsh; ends with `SUITE PASS`.

- [ ] **Step 6: Commit**

```bash
cd "$HOME/.dotfiles/my-bash"
git add shells/keychain tests/07_source.sh
git commit -m "feat: auto-load secrets at source time

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Wire into the repo (install.sh, rc files, template, README)

**Files:**
- Create: `shells/secrets.local.example`
- Modify: `install.sh` (add one `link` line)
- Modify: `zshrc` (add source line after exports)
- Modify: `bashrc` (add source line after exports)
- Modify: `README.md` (layout table row + Secrets section)
- Verify: `.gitignore`

- [ ] **Step 1: Create the manifest template**

Create `shells/secrets.local.example`:

```sh
# Copy to ~/.shells/secrets.local (or just run `secret set NAME`, which creates it).
# One env-var name per line; values live in the macOS Keychain, never here.
# This .example file is committed; the real secrets.local is git-ignored (*.local).
#
# ANTHROPIC_API_KEY
# OPENAI_API_KEY
# LANGCHAIN_API_KEY
# AWS_ACCESS_KEY_ID
# AWS_SECRET_ACCESS_KEY
```

- [ ] **Step 2: Add the install.sh symlink line**

In `install.sh`, find:

```bash
link shells/tools     "$HOME/.shells/tools"
```

and add immediately after it:

```bash
link shells/keychain  "$HOME/.shells/keychain"
```

- [ ] **Step 3: Add the source line to zshrc**

In `zshrc`, find:

```sh
source $HOME/.shells/exports
```

and add immediately after it:

```sh
source $HOME/.shells/keychain
```

- [ ] **Step 4: Add the source line to bashrc**

In `bashrc`, find:

```sh
source $HOME/.shells/exports
```

and add immediately after it:

```sh
source $HOME/.shells/keychain
```

- [ ] **Step 5: Update the README layout table**

In `README.md`, find the table row:

```
| `shells/tools` | `~/.shells/tools` | interactive extras (`fzf`, `zoxide`, `eza`, `bat`, zsh plugins) — sourced last, no-op if not installed |
```

and add immediately after it:

```
| `shells/keychain` | `~/.shells/keychain` | `secret` command + startup loader that exports API keys from the macOS Keychain (see Secrets) |
```

- [ ] **Step 6: Replace the README "Secrets" section**

In `README.md`, replace this block:

```
## Secrets

Keep credentials **out of this repo.** Anything sensitive (AWS keys, API tokens, etc.)
belongs in a local, untracked file — e.g. `~/.shells/aws` — that you source from your
own machine only. Never commit secret files; add them to `.gitignore`.
```

with:

```
## Secrets

API keys and tokens are stored in the **macOS Keychain** (encrypted, unlocked at
login) and auto-exported into every shell by `shells/keychain` — so projects can read
them from the environment instead of carrying their own `.env` files. No secret value
ever lives in a file or in this repo.

```bash
secret set OPENAI_API_KEY     # hidden prompt; stores in Keychain + ~/.shells/secrets.local
secret list                   # ✓ present / ✗ missing for each tracked name
secret get OPENAI_API_KEY     # print one value (for scripts)
secret rm  OPENAI_API_KEY     # delete from Keychain + manifest
exec $SHELL -l                # new shells now export the key
```

Which names auto-load is tracked in `~/.shells/secrets.local` (git-ignored via
`*.local`; `shells/secrets.local.example` is the committed template). The loader is a
no-op on machines without the `security` CLI, and silently skips names that aren't set
(use `secret list` to audit).
```

- [ ] **Step 7: Verify `.gitignore` needs no change**

Run:
```bash
cd "$HOME/.dotfiles/my-bash"
git check-ignore -v shells/secrets.local.example || echo "OK: template is committable"
printf 'secrets.local\n' | git check-ignore --stdin -v && echo "OK: secrets.local is ignored"
```
Expected: the template is NOT ignored (`echo` line prints), and `secrets.local` IS ignored by the `*.local` rule. If `secrets.local.example` is unexpectedly ignored, stop and report.

- [ ] **Step 8: Syntax-check the edited entry points and rerun the suite**

Run:
```bash
cd "$HOME/.dotfiles/my-bash"
bash -n bashrc && zsh -n zshrc && bash -n install.sh && echo "parse OK"
grep -q 'source \$HOME/.shells/keychain' zshrc && grep -q 'source \$HOME/.shells/keychain' bashrc && echo "rc wired"
grep -q 'link shells/keychain' install.sh && echo "install wired"
./tests/run.sh
```
Expected: `parse OK`, `rc wired`, `install wired`, then `SUITE PASS`.

- [ ] **Step 9: Commit**

```bash
cd "$HOME/.dotfiles/my-bash"
git add shells/secrets.local.example install.sh zshrc bashrc README.md
git commit -m "feat: wire keychain module into install.sh, rc files, and docs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Migration runbook (manual — operator enters real secrets)

> This task is performed by the user/operator because it involves pasting real
> credentials. The executing agent should present these steps and pause; it must NOT
> type real key values. Order matters: load secrets into the Keychain BEFORE switching
> the rc files to symlinks, or AWS keys briefly stop loading.

- [ ] **Step 1: Apply the symlinks from the clone**

```bash
cd "$HOME/.dotfiles/my-bash"
./install.sh
```
This symlinks `shells/*` (incl. `keychain`) into `~/.shells/` and `bashrc`/`zshrc` into
`~/`, backing up your current hard-copied files to `*.bak`.

- [ ] **Step 2: Store every key in the Keychain (operator)**

```bash
secret set ANTHROPIC_API_KEY
secret set OPENAI_API_KEY
secret set LANGCHAIN_API_KEY
secret set AWS_ACCESS_KEY_ID        # paste the current value from ~/.shells/aws
secret set AWS_SECRET_ACCESS_KEY    # paste the current value from ~/.shells/aws
```

- [ ] **Step 3: Reload and verify**

```bash
exec $SHELL -l
secret list                                   # every expected name should be ✓
printf '%s\n' "${ANTHROPIC_API_KEY:+ANTHROPIC set}" "${AWS_ACCESS_KEY_ID:+AWS set}"
```
Expected: all `✓`, and the keys are present in the environment.

- [ ] **Step 4: Remove the plaintext aws file**

Only after Step 3 confirms the AWS keys load from the Keychain:

```bash
rm -f "$HOME/.shells/aws" "$HOME/.shells/aws.bak"
exec $SHELL -l && printf '%s\n' "${AWS_ACCESS_KEY_ID:+AWS still set}"
```
Expected: `AWS still set` — proving the keys now come from the Keychain, not the file.

- [ ] **Step 5: (Recommended) Rotate the previously-plaintext AWS keys**

The old AWS keys lived in plaintext on disk. If this machine was ever shared or backed
up unencrypted, rotate them in the AWS console, then `secret set AWS_ACCESS_KEY_ID` /
`secret set AWS_SECRET_ACCESS_KEY` with the new values.

---

## Final Verification

- [ ] `cd "$HOME/.dotfiles/my-bash" && ./tests/run.sh` ends with `SUITE PASS`.
- [ ] A brand-new terminal exports the expected keys (`secret list` all `✓`).
- [ ] `git status` is clean; `git log --oneline` shows the feature commits.
- [ ] No secret value appears anywhere under `git ls-files` (spot check: `git grep -nE 'API_KEY=|AKIA' $(git rev-parse HEAD) -- . ':!docs'` returns nothing).
- [ ] Hand off via `superpowers:finishing-a-development-branch` to decide merge/PR.
