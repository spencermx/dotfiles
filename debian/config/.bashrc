# Interactive bash config for the console-only ThinkPad.
#
# This zone's own copy. The aliases here were carried from mac/config/.zshrc
# and archlinux/config/.bashrc, minus everything that needs a display server.
# A change here does not reach either of them.

case $- in
	*i*) ;;
	  *) return ;;
esac

#---------------------------------------------------------------------------
# History
#---------------------------------------------------------------------------

HISTCONTROL=ignoreboth
HISTSIZE=100000
HISTFILESIZE=200000
shopt -s histappend checkwinsize

#---------------------------------------------------------------------------
# PATH
#---------------------------------------------------------------------------

# ~/.local/bin first and deliberately: claude, gh, nvim, yazi and node all live
# under $HOME so they can be updated after sudo is purged. Anything apt
# installs is frozen at security patches, so a user-local copy must win.
export PATH="$HOME/.local/bin:$HOME/.local/share/nvim/mason/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# Nothing here can open a browser, and some tools will hang trying.
export BROWSER=
export EDITOR=nvim

#---------------------------------------------------------------------------
# Aliases
#---------------------------------------------------------------------------

alias ls='lsd -l'
alias ll='lsd -la'
alias la='lsd -a'
alias l='lsd'
alias cls='clear'
alias vim=nvim
alias laude='clear && claude'

alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

alias ct='RUSTFLAGS="-Awarnings" cargo test --lib -- --format pretty'
alias treenod="tree -I 'node_modules'"

# Debian renames both of these to avoid clashing with existing packages.
# Aliased rather than symlinked into /usr/local/bin, because that would need
# root and so could never be fixed after the gate.
command -v fdfind >/dev/null && alias fd=fdfind
command -v batcat >/dev/null && alias bat=batcat

# The mac copy is `sudo shutdown -h now`, which is dead here -- sudo is purged.
# logind's polkit action allows an active local session to do this unprivileged,
# and that path has to keep working: it is how kernel security updates from
# unattended-upgrades actually take effect.
alias poweroff='systemctl poweroff'
alias reboot='systemctl reboot'

#---------------------------------------------------------------------------
# Functions
#---------------------------------------------------------------------------

# yazi, then follow it to wherever you quit. A child process cannot change its
# parent's directory, so yazi writes its exit directory to a temp file and the
# function does the cd itself.
e() {
	local tmp cwd
	tmp="$(mktemp -t yazi-cwd.XXXXXX)"
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd" || return
		[ -n "$TMUX" ] && tmux refresh-client -c /home
	fi
	rm -f -- "$tmp"
}

# tmux session named after the current directory, created if absent.
ts() {
	local session_name
	session_name="$(printf '%s' "$PWD" | tr '/ ' '__' | tr -C '[:alnum:]_-' '_' | sed 's/_*$//')"
	[ -n "$session_name" ] || { echo "ts: empty session name for $PWD" >&2; return 1; }

	if tmux has-session -t "=$session_name" 2>/dev/null; then
		if [ -n "$TMUX" ]; then
			tmux switch-client -t "=$session_name"
		else
			tmux attach-session -t "=$session_name"
		fi
		return
	fi

	if [ -n "$TMUX" ]; then
		tmux new-session -d -s "$session_name" -c "$PWD" && \
			tmux switch-client -t "=$session_name"
	else
		tmux new-session -s "$session_name" -c "$PWD"
	fi
}

#---------------------------------------------------------------------------
# Keys and completions
#---------------------------------------------------------------------------

# ctrl-l is bound to window switching in tmux, so clear moves to ctrl-o.
bind -r "\C-l"
bind -x '"\C-o":clear'

command -v zoxide >/dev/null && eval "$(zoxide init bash)"

# fzf: ctrl-r history, ctrl-t files. Guard on a real tty -- the key-binding
# script touches readline state that does not exist when bash is driven by a
# pipe, and prints errors on every start if it is not there.
if [ -t 1 ]; then
	[ -f /usr/share/doc/fzf/examples/key-bindings.bash ] && \
		. /usr/share/doc/fzf/examples/key-bindings.bash
	[ -f /usr/share/bash-completion/completions/fzf ] && \
		. /usr/share/bash-completion/completions/fzf
fi

[ -f /usr/share/bash-completion/bash_completion ] && \
	. /usr/share/bash-completion/bash_completion
