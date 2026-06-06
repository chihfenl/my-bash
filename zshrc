# ${HOME}/.zshrc: executed by zsh for interactive shells.

# Shared, portable shell config (user info, PATH, functions, aliases)
source $HOME/.shells/functions
source $HOME/.shells/exports
source $HOME/.shells/alias

# Prompt (cross-shell, via Starship)
eval "$(starship init zsh)"

# Welcome message (time-aware greeting, defined in ~/.shells/functions)
greeting

[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# Interactive enhancements (fzf, zoxide, eza, bat, zsh-autosuggestions,
# zsh-syntax-highlighting) — sourced last so highlighting wraps all widgets
source $HOME/.shells/tools
