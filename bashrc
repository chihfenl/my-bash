#!/usr/bin/env bash
# ${HOME}/.bashrc: executed by bash(1) for non-login shells.
# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# Shared, portable shell config (user info, PATH, functions, aliases)
source $HOME/.shells/functions
source $HOME/.shells/exports
source $HOME/.shells/keychain
source $HOME/.shells/alias

# Prompt (cross-shell, via Starship)
eval "$(starship init bash)"

# Welcome message (time-aware greeting, defined in ~/.shells/functions)
greeting

[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# Interactive enhancements (fzf, zoxide, eza, bat) — sourced last on purpose
source $HOME/.shells/tools
