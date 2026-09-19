#!/usr/bin/env bash
# Step 5: Neovim plugins.
#
# Run as yourself, NOT as root:   ./5-neovim-plugins.sh
# Run steps 1 to 4 first: this needs a compiler, your nvim config linked into
# place, nvim, tree-sitter and node installed, and lazy.nvim cloned.
#
# Neovim installs your ~30 plugins at the exact commits recorded in
# common/config/nvim/lazy-lock.json.
#
# The command used is `Lazy! restore`, NOT `Lazy! sync`. sync UPDATES every
# plugin to whatever is newest and rewrites lazy-lock.json. restore puts every
# plugin on the commit the lockfile names.
#
# Running this again never brings newer code. Plugins only move when you run
# :Lazy update inside nvim yourself. That rewrites lazy-lock.json, which lives
# in this repo, so `git status` shows you it happened.

set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
    echo "run this as yourself, not as root" >&2
    exit 1
fi

# nvim, tree-sitter and node live here, and a fresh shell may not have it on PATH yet.
export PATH="$HOME/.local/bin:$PATH"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCKFILE="$REPO/common/config/nvim/lazy-lock.json"
PLUGIN_DIR="$HOME/.local/share/nvim/lazy"

if ! command -v nvim >/dev/null; then
    echo "nvim not found. Run ./3-download-programs.sh first." >&2
    exit 1
fi
if [ ! -e "$HOME/.config/nvim/init.lua" ]; then
    echo "~/.config/nvim is not linked. Run ./2-link-dotfiles.sh first." >&2
    exit 1
fi
if [ ! -d "$PLUGIN_DIR/lazy.nvim/.git" ]; then
    echo "lazy.nvim is not there. Run ./4-git-clones.sh first." >&2
    exit 1
fi

#---------------------------------------------------------------------------
# 1. Install. When nvim starts it installs any plugin that is missing, using
#    the lockfile. `Lazy! restore` then forces every installed plugin onto its
#    locked commit. The first run takes a few minutes.
#---------------------------------------------------------------------------
echo "installing plugins at the commits in lazy-lock.json ..."
nvim --headless "+Lazy! restore" +qa

#---------------------------------------------------------------------------
# 2. Check the result ourselves instead of trusting it, and show the list:
#    every installed plugin must be on exactly the commit the lockfile names.
#---------------------------------------------------------------------------
matched=0; differ=0; absent=0
while IFS=$'\t' read -r name commit; do
    if [ ! -d "$PLUGIN_DIR/$name/.git" ]; then
        absent=$((absent + 1))
        printf '  --     %-30s not installed (disabled in your config)\n' "$name"
    elif [ "$(git -C "$PLUGIN_DIR/$name" rev-parse HEAD)" = "$commit" ]; then
        matched=$((matched + 1))
        printf '  ok     %-30s %s\n' "$name" "${commit:0:12}"
    else
        differ=$((differ + 1))
        printf '  WRONG  %-30s is at %s, locked at %s\n' "$name" \
            "$(git -C "$PLUGIN_DIR/$name" rev-parse --short=12 HEAD)" "${commit:0:12}"
    fi
done < <(jq -r 'to_entries[] | "\(.key)\t\(.value.commit)"' "$LOCKFILE")

echo "plugins on their locked commit: $matched    not installed: $absent    wrong commit: $differ"
[ "$differ" -eq 0 ]
