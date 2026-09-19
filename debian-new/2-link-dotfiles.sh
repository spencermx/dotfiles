#!/usr/bin/env bash
# Step 2: link your dotfiles into your home folder.
#
# Run as yourself, NOT as root:   ./2-link-dotfiles.sh
#
# Each line in LINKS is:   <link in your home folder>   <file in this repo>
# If something is already at the link path, it is moved to <name>.bak first.
# Safe to run again: links that are already correct are left alone.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LINKS=(
    # shell (.bashrc loads .bashrc.repo, which is the `repo` command)
    "$HOME/.bashrc                 $REPO/debian/config/.bashrc"
    "$HOME/.bashrc.repo            $REPO/common/config/shell/repo.bash"

    # git (.gitconfig loads .gitconfig.common)
    "$HOME/.gitconfig              $REPO/debian/config/.gitconfig"
    "$HOME/.gitconfig.common       $REPO/common/config/.gitconfig"
    "$HOME/.config/git/ignore      $REPO/common/config/git/ignore"

    # tmux (.tmux.conf loads .tmux.conf.common)
    "$HOME/.tmux.conf              $REPO/debian/config/.tmux.conf"
    "$HOME/.tmux.conf.common       $REPO/common/config/.tmux.conf"
    "$HOME/.local/bin/tmux-battery $REPO/debian/bin/tmux-battery"

    # editors and file manager
    "$HOME/.vimrc                  $REPO/common/config/.vimrc"
    "$HOME/.config/nvim            $REPO/common/config/nvim"
    "$HOME/.config/yazi/theme.toml $REPO/debian/config/yazi/theme.toml"

    # your helper commands
    "$HOME/.local/bin/portal       $REPO/debian/bin/portal"
    "$HOME/.local/bin/printers     $REPO/debian/bin/printers"
    "$HOME/.local/bin/netreport    $REPO/debian/bin/netreport"
    "$HOME/.local/bin/gatecheck    $REPO/debian/bin/gatecheck"
    "$HOME/.local/bin/diskreport   $REPO/debian/bin/diskreport"
    "$HOME/.local/bin/toolcheck    $REPO/debian/bin/toolcheck"
    "$HOME/.local/share/man/man1/notes-tmux.1 $REPO/debian/man/man1/notes-tmux.1"

    # Claude Code. settings.json has hooks that run `aivim`, from your tools repo.
    "$HOME/.claude/CLAUDE.md       $REPO/common/config/claude/CLAUDE.md"
    "$HOME/.claude/settings.json   $REPO/common/config/claude/settings.json"
)

if [ "$(id -u)" -eq 0 ]; then
    echo "run this as yourself, not as root" >&2
    exit 1
fi

for pair in "${LINKS[@]}"; do
    read -r link target <<< "$pair"

    if [ ! -e "$target" ]; then
        echo "missing from the repo: $target" >&2
        exit 1
    fi

    if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
        echo "ok      $link"
        continue
    fi

    mkdir -p "$(dirname "$link")"

    if [ -L "$link" ]; then
        rm "$link"
    elif [ -e "$link" ]; then
        if [ -e "$link.bak" ]; then
            echo "stopping: $link.bak already exists, move it out of the way first" >&2
            exit 1
        fi
        mv "$link" "$link.bak"
        echo "backup  $link -> $link.bak"
    fi

    ln -s "$target" "$link"
    echo "linked  $link"
done
