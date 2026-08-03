# Login shell environment. Read once per login shell, before .zshrc.
#
# PATH is assembled here and nowhere else. .zshrc is for interactive things --
# aliases, functions, completions -- and assumes this file already ran.

# Homebrew.
#
# `brew shellenv` PREPENDS the brew prefix, and that ordering is the entire
# reason this line exists. This machine used to reach Homebrew through
# /etc/paths.d/homebrew, which path_helper appends AFTER /usr/bin. macOS ships
# its own jq, python3, pip3 and openssl there, so every brew formula sharing a
# name with a system binary was installed and then permanently shadowed --
# brew's jq 1.8.1 lost to /usr/bin/jq 1.7.1-apple on every single invocation.
#
# The prefix is not hardcoded: Apple Silicon uses /opt/homebrew, Intel
# /usr/local.
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Personal binaries. claude and grok symlink themselves in here.
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"

# .NET global tools.
#
# /etc/paths.d/dotnet-cli-tools contains the literal text "~/.dotnet/tools",
# and path_helper does not expand ~ -- so that entry has always resolved to a
# relative directory named "~" and has never worked. This adds the real path.
# `setup.sh --fix-paths` removes the broken file.
[ -d "$HOME/.dotnet/tools" ] && PATH="$HOME/.dotnet/tools:$PATH"

# pip install --user, against whichever system python is current. Globbed
# rather than pinned to 3.9 so a macOS upgrade doesn't silently drop it.
for _py in "$HOME"/Library/Python/*/bin(N); do
    [ -d "$_py" ] && PATH="$PATH:$_py"
done
unset _py

# Build output from the prismora repo. Conditional, so this file is still
# correct on a machine that has never cloned it.
[ -d "$HOME/source/repos/prismora/src/pipeline/bin" ] &&
    PATH="$PATH:$HOME/source/repos/prismora/src/pipeline/bin"

export PATH
