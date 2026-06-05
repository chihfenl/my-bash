#!/usr/bin/env bash
# ${HOME}/.bashrc: executed by bash(1) for non-login shells.
# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# User Info

USERNAME="Chih-Feng Lin"
NICKNAME="Chih-Feng"

# Distribute bashrc into smaller, more specific files

#source $HOME/.shells/defaults
source $HOME/.shells/functions
source $HOME/.shells/exports
source $HOME/.shells/alias

# Prompt (cross-shell, via Starship) — replaces the old prompt/git PS1 files
eval "$(starship init bash)"

# Welcome message (time-aware greeting, defined in ~/.shells/functions)
greeting

. "$HOME/.local/bin/env"

