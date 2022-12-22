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
source $HOME/.shells/prompt   # Fancy prompt with time and current working dir
source $HOME/.shells/git      # Conveniences - Display current branch etc

# Welcome message
cur_hour=`date "+%H"`
if [ $cur_hour -ge 6 ] && [ $cur_hour -lt 12 ]; then
    WELCOME_SENTENCE="Good Morning"
elif [ $cur_hour -ge 12 ] && [ $cur_hour -lt 18 ]; then
    WELCOME_SENTENCE="Good Afternoon"
else
    WELCOME_SENTENCE="Good Evening"
fi

echo -ne "$WELCOME_SENTENCE, $NICKNAME! It's "; date '+%A, %B %-d %Y'

