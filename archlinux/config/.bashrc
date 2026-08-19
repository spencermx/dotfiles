# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='lsd -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi



################################################################# CUSTOM ##################################################################
export PATH="$HOME/.local/share/nvim/mason/bin:/opt/dotnet:$HOME/.local/bin:$PATH"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk/
export DOTNET_ROOT=/opt/dotnet
export XDG_MENU_PREFIX=plasma-
#export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$HOME/myapps/bin:$PATH"
#alias ls="lsd"
# alias fe="nautilus . & disown"
alias fe="dolphin . & disown"
alias cls='clear'
alias ct='RUSTFLAGS="-Awarnings" cargo test --lib -- --format pretty'
alias treenod="tree -I 'node_modules'"
alias ytd='yt-dlp -x --audio-format mp3'


# TMUX FIX - because we've added bindings for windows switching in tmux ctrl+l, clear screen no longer works so we must bind it to ctrl+o
bind -r "\C-l" # Unbind Ctrl+L  
bind -r "\C-L" #(Optional) Unbind the uppercase version as well (usually not needed)
bind -x '"\C-o":/bin/clear'


# YAZI - Shell wrapper
function e() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
        if [ -n "$TMUX" ]; then
            tmux refresh-client -c /home 
        fi
	fi
	rm -f -- "$tmp"
}

ts() {
    # Validate the current directory
    if [[ ! -d "$PWD" ]]; then
        echo "Error: Current directory '$PWD' does not exist or is not a directory."
        return 1
    fi

    # Get the current directory's base name
    local dir_name=$(basename "$PWD")

    # Sanitize the directory name: replace spaces with underscores and remove special characters
    # local session_name=$(echo "$dir_name" | tr ' ' '_' | tr -C '[:alnum:]_-' '_' | sed 's/_*$//')
    local session_name=$(echo "$PWD" | tr '/' '_' | tr ' ' '_' | tr -C '[:alnum:]_-' '_' | sed 's/_*$//')

    # Ensure session_name is not empty
    if [[ -z "$session_name" ]]; then
        echo "Error: Sanitized session name is empty. Please use a directory with a valid name."
        return 1
    fi
    
    # Session doesn't exist, create a new one
    if [[ -n "$TMUX" ]]; then
        # Inside tmux: create a new session in the background and switch to it
        if ! tmux new-session -d -s "$session_name" -c "$PWD" 2>/dev/null; then
            echo "Error: Failed to create session '$session_name'."
            return 1
        fi
        if ! tmux switch-client -t "$session_name" 2>/dev/null; then
            echo "Error: Failed to switch to session '$session_name'."
            return 1
        fi
    else
        # Outside tmux: create and attach to a new session
        if ! tmux new-session -s "$session_name" -c "$PWD" 2>/dev/null; then
            echo "Error: Failed to create session '$session_name'."
            return 1
        fi
    fi
}
## eval "$(zoxide init bash)"

# `repo` -- one word for every git repo below here: status, checkout-and-pull
# across all of them, and PR review in a throwaway clone under ~/.prs. The
# implementation is shared with debian/ and lives in common/, linked to
# ~/.bashrc.repo, the same include pattern .gitconfig uses.
#
# $REPO_OPEN is the one thing the two zones disagree about: what to launch on
# the review clone once the PR is checked out. Debian is a text console and
# opens nvim. It is checked with command -v before it runs, so this is inert
# rather than fatal on a machine without VS Code installed.
REPO_OPEN=code
[ -r "$HOME/.bashrc.repo" ] && . "$HOME/.bashrc.repo"

################################################################# CUSTOM ##################################################################

##. "$HOME/.cargo/env"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
