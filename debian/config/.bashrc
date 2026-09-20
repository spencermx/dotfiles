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
export PATH="$HOME/.local/bin:$HOME/.local/share/nvim/mason/bin:$HOME/.cargo/bin:$PATH"

# Programs started here are displayed on the Linux text console, even when
# tmux makes TERM look like an ordinary screen-256color terminal. Shared
# configs use this explicit marker instead of guessing from TERM and changing
# their appearance on graphical machines or over SSH.
export DOTFILES_CONSOLE=1

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

# aivim, from the tools repo: one key to the agent sessions. Declared here
# rather than left to `aivim --install`, which would otherwise append it to
# ~/.bashrc -- a symlink into this repo.
alias a=aivim

# These were aliases to `systemctl reboot` / `systemctl poweroff`, on the
# assumption that logind lets an active local session do it unprivileged. It
# does -- through a *polkit* action, and there is no polkit on this machine.
# Both fail with:
#
#   Failed to execute /usr/bin/pkttyagent: No such file or directory
#   Call to Reboot failed: Access denied
#
# The power button is the path that works and always will: logind handles the
# key press itself, so nothing is authorised and nothing can deny it, and it is
# a clean shutdown rather than a power cut. That matters more than convenience
# -- it is how a kernel security update from unattended-upgrades takes effect.
#
# Try the command anyway: it succeeds while root still exists to be `su`d to,
# and once it stops working it says what to do instead.
# The mechanism is /run/user-power, a directory this account owns, watched by
# root-owned path units that setup.sh installs. Touching a file in it is the
# whole request. That exists because the obvious routes are both closed here:
# `systemctl reboot` needs polkit, which this machine does not have, and after
# the gate there is no root to su to.
_power_request() {
	local act="$1"
	if [ -d /run/user-power ] && touch "/run/user-power/$act" 2>/dev/null; then
		printf '%s requested.\n' "$act"
		return 0
	fi
	# Before setup.sh has run, or if the path units are gone.
	systemctl "$act" 2>/dev/null && return 0
	printf '%s: no mechanism available.\n' "$act" >&2
	printf '  /run/user-power is missing -- run debian/setup.sh as root\n' >&2
	printf "  meanwhile, while root exists:  su -c 'systemctl %s'\n" "$act" >&2
	return 1
}

reboot()   { _power_request reboot;   }
poweroff() { _power_request poweroff; }

# loginctl can only ask a session's existing screen locker to engage. There is
# no session manager on a bare Linux console, so physlock owns the actual lock
# and PAM password prompt. It locks every virtual console, not just tmux or the
# current shell.
lock() { command physlock; }

# `suspend` is a bash *builtin* -- it SIGSTOPs the shell itself, which is how
# you get back to a parent shell you shelled out of. Defining a function by
# that name shadows it. That is the intended trade: the builtin refuses in a
# login shell anyway, and `builtin suspend` still reaches it if it is ever
# wanted. Sleep is the machine-level meaning of the word here.
#
# -d detaches only after physlock has secured the consoles. The root-owned path
# unit cannot race ahead of the lock, and failure to lock prevents suspend
# rather than leaving the live tmux session exposed on resume.
suspend() {
	command physlock -d || {
		printf 'suspend: console lock failed; not suspending.\n' >&2
		return 1
	}
	_power_request suspend
}

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

# `repo` -- one word for every git repo below here: status, checkout-and-pull
# across all of them, and PR review in a throwaway clone under ~/.prs. The
# implementation is shared with archlinux/ and lives in common/, linked to
# ~/.bashrc.repo, the same include pattern .tmux.conf and .gitconfig use.
#
# $REPO_OPEN is the one thing the two zones disagree about: what to launch on
# the review clone once the PR is checked out. Arch opens VS Code; there is no
# display server here, so it is the editor this machine actually has. Set it
# empty to check out the PR and just leave you standing in the tree.
REPO_OPEN=nvim
[ -r "$HOME/.bashrc.repo" ] && . "$HOME/.bashrc.repo"

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

#---------------------------------------------------------------------------
# Inside a graphical session (Sway, GNOME)
#---------------------------------------------------------------------------

# Everything above assumes the plain text console. When there is a display,
# undo the console-only parts. This runs last so that it wins.
if [ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ]; then
	unset DOTFILES_CONSOLE              # nvim and yazi use their normal colours
	export BROWSER=firefox-esr

	# open Thunar here, same name as Arch's dolphin alias and mac's Finder function
	fe() { thunar "${1:-.}" >/dev/null 2>&1 & disown; }

	# Inside Sway, these go through the Sway lock screen and its confirm menu.
	if [ -n "${SWAYSOCK:-}" ]; then
		lock()     { "$HOME/.local/bin/desktop-control" lock; }
		suspend()  { "$HOME/.local/bin/desktop-control" suspend; }
		reboot()   { "$HOME/.local/bin/desktop-control" reboot; }
		poweroff() { "$HOME/.local/bin/desktop-control" poweroff; }
	fi
fi
