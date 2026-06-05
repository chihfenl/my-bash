# ${HOME}/.zshrc: executed by zsh for interactive shells.

# User Info
export USERNAME="Chih-Feng Lin"
export NICKNAME="Chih-Feng"

# Shared, portable shell config (also sourced by ~/.bashrc)
source $HOME/.shells/functions
source $HOME/.shells/exports
source $HOME/.shells/alias

# Prompt (cross-shell, via Starship)
eval "$(starship init zsh)"

# Welcome message (time-aware greeting, defined in ~/.shells/functions)
greeting

. "$HOME/.local/bin/env"
