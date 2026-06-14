# my-bash

Personal shell configuration for **macOS**, shared across **bash** and **zsh**.

One set of portable files (PATH, environment, aliases) is sourced by both shells,
and the prompt is drawn by [Starship](https://starship.rs) so it looks identical in
either shell.

## Layout

| Repo file | Installs to | Purpose |
|-----------|-------------|---------|
| `bashrc` | `~/.bashrc` | bash entry point |
| `zshrc` | `~/.zshrc` | zsh entry point |
| `shells/exports` | `~/.shells/exports` | user info, PATH, Homebrew prefix detection, version managers (`pyenv`/`jenv`/`scalaenv`/`sbtenv`) |
| `shells/alias` | `~/.shells/alias` | aliases + `ls`/`grep` colors (works on GNU **and** BSD/macOS) |
| `shells/functions` | `~/.shells/functions` | shared shell functions (e.g. the time-aware greeting) |
| `shells/tools` | `~/.shells/tools` | interactive extras (`fzf`, `zoxide`, `eza`, `bat`, zsh plugins) — sourced last, no-op if not installed |
| `shells/keychain` | `~/.shells/keychain` | `secret` command + startup loader that exports API keys from the macOS Keychain (see Secrets) |
| `starship.toml` | `~/.config/starship.toml` | prompt config, shared by both shells |
| `install.sh` | — | idempotent symlink installer (see Setup) |
| `vscode-dark.terminal` | import into Terminal.app | optional macOS Terminal.app profile — VS Code Dark+ palette + FiraCode Nerd Font |

Both `bashrc` and `zshrc` do the same thing: set user info → source the shared
`functions`/`exports`/`alias` → `eval "$(starship init <shell>)"` → print a time-aware
welcome banner.

## Prerequisites

- macOS (Intel **or** Apple Silicon — the Homebrew prefix is detected automatically)
- [Homebrew](https://brew.sh)
- [Starship](https://starship.rs) — `brew install starship`
- *Optional* interactive tools, wired up automatically by `shells/tools` only if present:

  ```bash
  brew install eza bat zoxide fzf zsh-autosuggestions zsh-syntax-highlighting
  ```

  | Tool | Adds |
  |------|------|
  | [`eza`](https://eza.rocks) | modern `ls` (icons, `--git`, `--tree`); aliased to `ls`/`ll`/`la`/`lt` |
  | [`bat`](https://github.com/sharkdp/bat) | syntax-highlighted `cat` (use `\cat` for the plain builtin) |
  | [`zoxide`](https://github.com/ajeetdsouza/zoxide) | smarter `cd` — `z foo` jumps, `zi` picks interactively |
  | [`fzf`](https://github.com/junegunn/fzf) | fuzzy finder — `Ctrl-R` history, `Ctrl-T` files, `Alt-C` cd |
  | `zsh-autosuggestions` | fish-style history suggestion as you type (zsh) |
  | `zsh-syntax-highlighting` | live command coloring (zsh) |

- *Optional* version managers, auto-loaded only if present: `pyenv`, `jenv`, `scalaenv`, `sbtenv`

## Setup

Clone the repo, then run the installer. It symlinks everything into place (so the
repo stays the single source of truth — edits go live with no copying) and is safe
to re-run: any real file already in the way is backed up to `*.bak` first.

```bash
git clone <this-repo> ~/code/my-bash
cd ~/code/my-bash
brew install starship   # if you don't have it yet
./install.sh
```

Reload your shell — `exec zsh` (or `exec bash`), or just open a new terminal.

<details>
<summary>Manual setup (what <code>install.sh</code> does)</summary>

```bash
# 1. shared shell snippets (sourced by both shells)
mkdir -p ~/.shells
for f in functions exports alias tools keychain; do ln -sf "$PWD/shells/$f" ~/.shells/"$f"; done

# 2. shell entry points
ln -sf "$PWD/bashrc" ~/.bashrc
ln -sf "$PWD/zshrc"  ~/.zshrc

# 3. prompt
brew install starship
mkdir -p ~/.config
ln -sf "$PWD/starship.toml" ~/.config/starship.toml
```
</details>

To make zsh your login shell (it's the macOS default since Catalina):

```bash
chsh -s /bin/zsh
```

## The prompt

Starship draws a two-line prompt that mirrors the original hand-rolled bash style:

```
user@host  ~/current/dir  (branch)*
❯
```

- bold **green** `user@host`
- bold **red** working directory
- `(branch)` in the default color
- bold **blue** dirty marker — `*` = unstaged changes, `^` = staged-only, nothing = clean working tree

Contextual modules appear only when relevant, so plain dirs stay minimal:

- **language versions** (`python`/`java`/`scala`) — only inside a matching project
- **`☸ kubernetes`** context + namespace — only inside an infra/deploy dir
  (`Chart.yaml`, `k8s/`, `helm/`, …); remove the `detect_*` lines to show it everywhere
- **terraform** workspace — only inside a `.tf` project
- **git state** (`REBASING 2/5`, `MERGING`, …) — only mid-operation
- **`✘ 1`** exit code — only after a failing command

Tweak `starship.toml` to customize; see <https://starship.rs/config/>.

## Terminal.app theme (optional)

`vscode-dark.terminal` is a macOS **Terminal.app** profile matching VS Code's **Dark+**
palette, with **FiraCode Nerd Font Mono** baked in so the prompt glyphs and `eza` icons
render. To use it:

1. Double-click `vscode-dark.terminal` (or `open vscode-dark.terminal`).
2. **Terminal → Settings → Profiles →** select **Dark+ (VS Code) →** click **Default**.

It sets only Terminal.app's 16 ANSI colors + background/foreground + font; the 256-color
`eza` palette (in `shells/tools`) is independent and layers on top. Not needed for VS Code's
integrated terminal, which already follows your editor theme.

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
exec $SHELL                   # new shells now export the key
```

Which names auto-load is tracked in `~/.shells/secrets.local` (git-ignored via
`*.local`; `shells/secrets.local.example` is the committed template). The loader is a
no-op on machines without the `security` CLI, and silently skips names that aren't set
(use `secret list` to audit).

## Notes

- The greeting changes with the time of day (morning / afternoon / evening / night),
  driven by the `greeting` function in `shells/functions`.
- The shell entry points end with `. "$HOME/.local/bin/env"` (added by tools like `uv`).
  If that file doesn't exist on your machine, remove the line or guard it with
  `[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"` to avoid a startup error.
