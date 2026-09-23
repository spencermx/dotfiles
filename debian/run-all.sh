#!/usr/bin/env bash
# Runs every enabled step in order, and stops at the first one that fails.
#
# Run as yourself, NOT as root:   ./run-all.sh
#
# It asks for your password for step 1, which needs root, and runs the rest as
# you. Steps reuse installed components where possible; after fixing a failure,
# run this again to finish setup.
#
# Step 2 links desktop/editor settings. Step 7 installs Aivim before activating
# the Claude settings that call it, verifies its integrations, and reloads Sway.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

if [ $# -gt 0 ]; then
    echo "usage: ./run-all.sh   (it takes no options)" >&2
    exit 2
fi

if [ "$(id -u)" -eq 0 ]; then
    echo "run this as yourself, not as root. It asks for root only where it is needed." >&2
    exit 1
fi

# A machine without sudo: su asks for the root password instead.
as_root() {
    if command -v sudo >/dev/null; then
        sudo "$@"
    else
        su -c "$(printf '%q ' "$@")"
    fi
}

step() { printf '\n========== %s ==========\n' "$1"; }

step "1-install-debian-packages.sh";   as_root ./1-install-debian-packages.sh
step "2-link-dotfiles.sh";             ./2-link-dotfiles.sh
step "3-download-programs.sh";         ./3-download-programs.sh
step "4-git-clones.sh";                ./4-git-clones.sh
step "5-neovim-plugins.sh";            ./5-neovim-plugins.sh
# Optional language servers are disabled; step 6's server list is commented out too.
# step "6-language-servers.sh";        ./6-language-servers.sh
step "7-setup-tools.sh";              ./7-setup-tools.sh

printf '\nall steps finished.\n'
