# Design: Keychain-backed secret management for `my-bash`

**Date:** 2026-06-14
**Status:** Approved (pending spec review)
**Repo:** https://github.com/chihfenl/my-bash

## Goal

Provide one reusable, scalable way to store API keys (Anthropic, OpenAI, LangChain,
AWS, …) on this Mac and auto-export them as environment variables at shell startup,
so individual projects no longer need their own `.env` files. Secret **values** must
never live in a file or in this (public) repo.

## Context

`my-bash` is a symlink-based dotfiles repo for macOS, shared across bash and zsh:

- `install.sh` idempotently symlinks `shells/*` into `~/.shells/` and `bashrc`/`zshrc`
  into `~/`, backing up any real file in the way to `*.bak`.
- `bashrc`/`zshrc` source `~/.shells/{functions,exports,alias}`, run Starship + a
  greeting, then source `~/.shells/tools` last.
- Secrets today: a single local, untracked `~/.shells/aws` holding plaintext AWS keys.
  `.gitignore` already reserves the local-only names `aws`, `shells/aws`, `secrets`,
  `*.secret`, `*.local`, `.env`.

The user clones the repo (to `~/.dotfiles/my-bash`) and runs `install.sh` rather than
hard-copying, so edits in the repo go live immediately.

## Decisions (resolved during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Storage backend | **macOS Keychain** | Encrypted at rest, auto-unlocks at login (no passphrase prompts), native `security` CLI, zero extra dependencies. |
| Load model | **One Keychain item per secret + a manifest** | Granular: add/rotate/remove one key independently. |
| Manifest visibility | **Local-only file + committed `.example`** | The name list is value-free but advertises the provider inventory; keep the real one off the public repo, ship a template. |
| `aws` file | **Fold into the pattern, then delete** | Removes the plaintext-on-disk special case. |
| Deployment | **Clone + `install.sh` symlinks** | Already supported; extend it by one line. |
| Loader filename | **`keychain`** (not `secrets`) | `.gitignore` reserves `secrets` as a local-only name, so a committed file named `secrets` would be silently un-committable. `keychain` matches the role-based naming (`functions`/`exports`/`tools`). |

## Non-goals

- Cross-platform encrypted secret store (Linux). The loader is a clean no-op where
  `security` is absent; a portable backend is out of scope.
- Automatic secret rotation or expiry.
- Syncing secret **values** across machines. Keychain is per-machine by design; on a
  new Mac you re-run `secret set`. This is intentional, not a gap.
- Per-project / per-directory secret scoping. Everything in the manifest is ambient.

## Architecture

```
                 committed (public repo)          local-only (never committed)
                 ┌───────────────────────┐        ┌──────────────────────────┐
   ~/.shells/    │ keychain   (symlink) ─┼──────▶ │ ~/.shells/secrets.local  │  (manifest:
                 │ functions  (symlink)  │  reads │   env-var NAMES, no values)  names only)
                 │ exports    (symlink)  │        └──────────────────────────┘
                 │ ...                   │                     ▲
                 └──────────┬────────────┘                     │ secret set / rm edit it
                            │ load_secrets()                    │
                            ▼ for each NAME                     │
                 ┌───────────────────────────────────────────────────────────┐
                 │ macOS login Keychain  (service = "shell-secret")           │
                 │   account=ANTHROPIC_API_KEY  → <value>   (encrypted)       │
                 │   account=OPENAI_API_KEY     → <value>                     │
                 └───────────────────────────────────────────────────────────┘
```

Secret values exist only inside the Keychain. The repo holds logic; `secrets.local`
holds names. Neither holds a value.

## Components

### 1. `shells/keychain` — the tool (committed; symlinked to `~/.shells/keychain`)

Sourced by both shells from the shared-config block. Contains no values. Behavior:

- **Guard:** `command -v security >/dev/null 2>&1 || return 0` — inert on non-macOS.
- **Config:**
  - `SHELL_SECRET_SERVICE="shell-secret"` (Keychain generic-password *service*)
  - `SHELL_SECRET_MANIFEST="${SHELL_SECRET_MANIFEST:-$HOME/.shells/secrets.local}"`
- **`secret` command** dispatching to:
  - `secret set NAME` — validate `NAME` matches `^[A-Za-z_][A-Za-z0-9_]*$`; prompt for
    the value with `read -rs` (silent, never in shell history); store with
    `security add-generic-password -U -s "$SHELL_SECRET_SERVICE" -a "$NAME" -w "$value"`;
    append `NAME` to the manifest if not already present (creating the manifest with a
    header comment on first use); `unset value`. Idempotent.
  - `secret get NAME` — print one value:
    `security find-generic-password -s "$SHELL_SECRET_SERVICE" -a "$NAME" -w`. For
    ad-hoc/script use.
  - `secret list` — for each manifest name, mark `✓`/`✗` by probing the Keychain. The
    audit tool, since startup is silent.
  - `secret rm NAME` — `security delete-generic-password` (tolerate absent item) and
    remove the line from the manifest.
  - `secret reload` — re-run `load_secrets` in the current shell.
- **`load_secrets`** (run once at source time):
  - `[ -r "$SHELL_SECRET_MANIFEST" ] || return 0` (missing manifest ⇒ no-op).
  - For each non-blank, non-`#` line `NAME`:
    `value=$(security find-generic-password -s "$SHELL_SECRET_SERVICE" -a "$NAME" -w 2>/dev/null)`;
    `[ -n "$value" ] && export "$NAME=$value"`. Never exports an empty value; never
    errors on a missing item (silent skip — `secret list` surfaces gaps).

### 2. `~/.shells/secrets.local` — the manifest (local-only, untracked)

Plain text, one env-var name per line; `#` comments allowed. Created/edited by
`secret set`/`secret rm`. Matched by `.gitignore`'s `*.local`, and physically lives
outside the repo working tree, so it cannot be `git add`ed. Example contents:

```
# Auto-loaded into every shell from the macOS Keychain (service "shell-secret").
# One env-var name per line. Manage with `secret set` / `secret rm`.
# Values live ONLY in the Keychain — never here.
ANTHROPIC_API_KEY
OPENAI_API_KEY
LANGCHAIN_API_KEY
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

### 3. `shells/secrets.local.example` — manifest template (committed)

A commented checklist of common names so a fresh machine knows what to `secret set`.
Filename ends in `.example`, so it is **not** caught by `*.local` and is committable.

### 4. Edits to existing committed files

- **`bashrc` and `zshrc`** — add `source "$HOME/.shells/keychain"` immediately after
  the `source $HOME/.shells/exports` line (keychain exports env vars; it belongs in the
  shared-config block). The repo versions have no `aws` source line, so nothing to
  remove there.
- **`install.sh`** — add one line in the shared-snippets group:
  `link shells/keychain "$HOME/.shells/keychain"`. It must **not** link
  `secrets.local` (that is machine-local).
- **`README.md`** — rewrite the "Secrets" section to document the Keychain workflow;
  add a `shells/keychain` row to the layout table.
- **`.gitignore`** — no change required. `keychain` and `secrets.local.example` are not
  matched by any rule; `secrets.local` is matched by `*.local`.

## Data flow

**Store:** `secret set OPENAI_API_KEY` → silent prompt → Keychain item
(`service=shell-secret`, `account=OPENAI_API_KEY`) + append name to `secrets.local`.

**Startup:** `source ~/.shells/keychain` → `load_secrets` reads `secrets.local` → one
`security` fetch per name → `export NAME=value` (skip empty/missing).

**Use:** every project/process started from the shell inherits the keys — no `.env`.

## Security model & caveats

- **At rest:** values are in the encrypted login Keychain; the repo and all files are
  value-free. Relies on the standard macOS posture (login Keychain + FileVault).
- **Ambient exposure:** once exported, every child process inherits the keys. Inherent
  to "load at startup," which is the requested behavior.
- **`ps` window:** `security add-generic-password -w "$value"` makes the value briefly
  visible in the process list *during `secret set` only*. Negligible on a single-user
  Mac; documented for honesty. `read -rs` keeps the value out of shell history.
- **Keychain ACL:** the item is created and read by the same `/usr/bin/security`
  binary, so reads are normally non-interactive. If macOS ever prompts, choose "Always
  Allow" once. Startup must never block on a GUI prompt.
- **Existing AWS keys:** currently plaintext in `~/.shells/aws`. The repo excludes
  `aws`, so they were not committed publicly. Still, rotate them if this machine has
  been shared or backed up unencrypted.

## Migration plan (ordering matters)

The repo `bashrc`/`zshrc` do not source `aws`; once `install.sh` symlinks them in, the
old local rc files (which sourced `aws`) are backed up and the aws keys stop loading
from the file. So secrets must be in the Keychain **before** the symlink switch:

1. Land the code changes (keychain file, rc edits, install.sh line, README) on the
   feature branch.
2. `secret set` every key, **including** `AWS_ACCESS_KEY_ID` and
   `AWS_SECRET_ACCESS_KEY` (paste current values) → populates Keychain + `secrets.local`.
3. Run `./install.sh` from `~/.dotfiles/my-bash` (symlinks new files; backs up current
   `~/.shells/*` and `~/.{bash,zsh}rc` to `*.bak`).
4. `exec $SHELL -l` → verify every expected key is exported (`secret list` all `✓`).
5. Delete the plaintext `~/.shells/aws` (and its `.bak` once confident). The `aws`
   `.gitignore` lines become harmless legacy.

## Testing

Behavioral checks (drive implementation TDD-style):

1. `secret set TEST_KEY` (value `abc=123`) → new shell → `echo $TEST_KEY` prints
   exactly `abc=123` (round-trips `=`, spaces, `/`, `+`).
2. `secret set TEST_KEY` twice → `secrets.local` lists `TEST_KEY` exactly once.
3. `secret rm TEST_KEY` → new shell → `TEST_KEY` unset; name gone from manifest.
4. Manifest name with no Keychain item → `load_secrets` skips it, no empty export, no
   error; `secret list` shows `✗`.
5. Missing manifest file → sourcing `keychain` is a clean no-op.
6. `secret get TEST_KEY` prints the exact stored value.
7. Non-macOS (no `security`) → sourcing `keychain` returns cleanly. (Noted; verified by
   the guard, hard to exercise on the Mac itself.)

## Open questions

None — all resolved during brainstorming.
