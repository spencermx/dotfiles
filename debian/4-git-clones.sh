#!/usr/bin/env bash
# Step 4: everything that is cloned from git.
#
# Run as yourself, NOT as root:   ./4-git-clones.sh
#
# Each repository is cloned and set to ONE exact commit. A commit id names the
# exact content, so running this again never brings newer code. To move one,
# change its commit at the bottom of this file and run this again.
#
#   tpm              tmux's plugin loader          (your tmux config loads it)
#   tmux-resurrect   save and restore tmux sessions
#   lazy.nvim        Neovim's plugin manager       (your init.lua loads it)
#
# The ~30 Neovim plugins themselves are step 5.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "run this as yourself, not as root" >&2
    exit 1
fi

# clone_at_commit <name> <repo url> <commit> <folder to put it in>
clone_at_commit() {
    local name="$1" url="$2" commit="$3" dest="$4"

    if [ -d "$dest/.git" ] && [ "$(git -C "$dest" rev-parse HEAD)" = "$commit" ]; then
        echo "ok         $name at ${commit:0:12}"
        return
    fi

    if [ -d "$dest/.git" ]; then
        git -C "$dest" fetch --quiet origin
    else
        mkdir -p "$(dirname "$dest")"
        git clone --quiet "$url" "$dest"
    fi
    git -C "$dest" -c advice.detachedHead=false checkout --quiet --detach "$commit"

    if [ "$(git -C "$dest" rev-parse HEAD)" != "$commit" ]; then
        echo "$name: could not get to commit $commit. Stopping." >&2
        exit 1
    fi
    echo "installed  $name at ${commit:0:12}"
}

# tpm v3.1.0, from 2023-01-03
clone_at_commit tpm \
    https://github.com/tmux-plugins/tpm \
    7bdb7ca33c9cc6440a600202b50142f401b6fe21 \
    "$HOME/.tmux/plugins/tpm"

# tmux-resurrect v4.0.0, from 2022-04-10
clone_at_commit tmux-resurrect \
    https://github.com/tmux-plugins/tmux-resurrect \
    e87d7d592cac97fa38c12395ebec042c154a1844 \
    "$HOME/.tmux/plugins/tmux-resurrect"

# lazy.nvim v11.17.5, from 2025-11-06. Your init.lua expects exactly this folder.
clone_at_commit lazy.nvim \
    https://github.com/folke/lazy.nvim.git \
    85c7ff3711b730b4030d03144f6db6375044ae82 \
    "$HOME/.local/share/nvim/lazy/lazy.nvim"
