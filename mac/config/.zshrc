# Interactive shell config. PATH and login-time environment live in .zprofile.

# .zprofile only runs for login shells. Terminal.app and tmux both start one,
# but some editors' embedded terminals do not -- and without it every alias
# below points at a Homebrew binary that is not on PATH yet.
if [ -z "$HOMEBREW_PREFIX" ] && [ -r "$HOME/.zprofile" ]; then
	source "$HOME/.zprofile"
fi

alias ll='lsd -la'
alias ls='lsd -l'
alias cls='clear'
alias vim=nvim
alias poweroff='sudo shutdown -h now'
alias laude='clear && claude'

# yazi, then follow it to wherever you quit. A child process cannot change its
# parent's directory, so yazi writes its exit directory to a temp file and the
# function does the cd itself.
function e() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# open Finder here
function fe() {
	open "${1:-.}"
}

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"                    # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# zoxide and fzf were both installed as deliberate brew leaves and neither was
# ever initialised, so neither was reachable through the interface it exists
# for -- `z` for zoxide, ctrl-r / ctrl-t for fzf.
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# fzf's key-bindings.zsh calls `setopt` on zle options, which do not exist when
# there is no terminal -- an interactive shell driven by a script (zsh -i in a
# pipe) then prints "can't change option: zle" twice on every start. Guard on a
# real tty rather than on interactivity.
if [ -t 0 ]; then
	[ -r "$HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.zsh" ] && source "$HOMEBREW_PREFIX/opt/fzf/shell/key-bindings.zsh"
	[ -r "$HOMEBREW_PREFIX/opt/fzf/shell/completion.zsh" ] && source "$HOMEBREW_PREFIX/opt/fzf/shell/completion.zsh"
fi

# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
fpath=(~/.grok/completions/zsh $fpath)
autoload -Uz compinit && compinit -C
# <<< grok installer <<<
