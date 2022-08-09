#!/usr/bin/env bash
# ${HOME}/.bashrc: executed by bash(1) for non-login shells.
# If not running interactively, don't do anything
[ -z "$PS1" ] && return

# User Info

export USERNAME="Chih-Feng Lin"
export NICKNAME="Chih-Feng"

# Distribute bashrc into smaller, more specific files

#source $HOME/.shells/defaults
source $HOME/.shells/functions
source $HOME/.shells/exports
source $HOME/.shells/alias
source $HOME/.shells/prompt   # Fancy prompt with time and current working dir
source $HOME/.shells/git      # Conveniences - Display current branch etc

# Welcome message
echo -ne "Good Morning, $NICKNAME! It's "; date '+%A, %B %-d %Y'

