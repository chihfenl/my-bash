#!/usr/bin/env bash
# install.sh — symlink this repo's shell config into your home directory.
#
# Idempotent: safe to re-run. If a real file/dir is already in the way it is
# backed up to <name>.bak before being replaced with a symlink; existing
# symlinks are simply refreshed.
#
# NOTE: the entry points (bashrc/zshrc) do NOT source any secrets. Keep local
# credentials in an untracked file (e.g. ~/.shells/aws) — see README "Secrets".
set -euo pipefail

# Repo root = the directory this script lives in.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {
  # link <source-relative-to-repo> <absolute-target>
  local src="$REPO/$1" dst="$2"
  if [ ! -e "$src" ]; then
    echo "skip:   $src does not exist"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    mv "$dst" "$dst.bak"
    echo "backup: $dst -> $dst.bak"
  fi
  ln -sf "$src" "$dst"
  echo "link:   $dst -> $src"
}

echo "Installing from $REPO"
echo

# Shared shell snippets (sourced by both bash and zsh)
link shells/functions "$HOME/.shells/functions"
link shells/exports   "$HOME/.shells/exports"
link shells/alias     "$HOME/.shells/alias"

# Shell entry points
link bashrc "$HOME/.bashrc"
link zshrc  "$HOME/.zshrc"

# Prompt
link starship.toml "$HOME/.config/starship.toml"

echo
if command -v starship >/dev/null 2>&1; then
  echo "starship: $(starship --version | head -1)"
else
  echo "NOTE: starship is not installed — run 'brew install starship'."
fi

echo "Done. Reload your shell:  exec \$SHELL -l"
