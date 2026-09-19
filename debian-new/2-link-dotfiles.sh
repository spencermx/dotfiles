#!/usr/bin/env bash
# Step 2: link your dotfiles into your home folder.
#
# Run as yourself, NOT as root:   ./2-link-dotfiles.sh
#
# Two lists, both always linked:
#
#   LINKS        shell, git, tmux, editors, your helper commands, Claude Code
#   SWAY_LINKS   the Sway desktop's config and helper commands
#
# Each line in a list is:   <link in your home folder>   <file it points to>
# Every file is inside this folder (debian-new/), except the ones shared with
# your other machines, which stay in common/.
# If something is already at the link path, it is moved to <name>.bak first.
# Safe to run again: links that are already correct are left alone.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"      # this folder, debian-new/
REPO="$(dirname "$HERE")"                                   # the repo root, only for common/

LINKS=(
    # shell (.bashrc loads .bashrc.repo, which is the `repo` command)
    "$HOME/.bashrc                 $HERE/config/.bashrc"
    "$HOME/.bashrc.repo            $REPO/common/config/shell/repo.bash"

    # git (.gitconfig loads .gitconfig.common)
    "$HOME/.gitconfig              $HERE/config/.gitconfig"
    "$HOME/.gitconfig.common       $REPO/common/config/.gitconfig"
    "$HOME/.config/git/ignore      $REPO/common/config/git/ignore"

    # tmux (.tmux.conf loads .tmux.conf.common)
    "$HOME/.tmux.conf              $HERE/config/.tmux.conf"
    "$HOME/.tmux.conf.common       $REPO/common/config/.tmux.conf"
    "$HOME/.local/bin/tmux-battery $HERE/bin/tmux-battery"

    # editors and file manager
    "$HOME/.vimrc                  $REPO/common/config/.vimrc"
    "$HOME/.config/nvim            $REPO/common/config/nvim"
    "$HOME/.config/yazi/theme.toml $HERE/config/yazi/theme.toml"

    # your helper commands
    "$HOME/.local/bin/portal       $HERE/bin/portal"
    "$HOME/.local/bin/printers     $HERE/bin/printers"
    "$HOME/.local/bin/netreport    $HERE/bin/netreport"
    "$HOME/.local/bin/gatecheck    $HERE/bin/gatecheck"
    "$HOME/.local/bin/diskreport   $HERE/bin/diskreport"
    "$HOME/.local/bin/toolcheck    $HERE/bin/toolcheck"
    "$HOME/.local/share/man/man1/notes-tmux.1 $HERE/man/man1/notes-tmux.1"

    # Claude Code. settings.json has hooks that run `aivim`, from your tools repo.
    "$HOME/.claude/CLAUDE.md       $REPO/common/config/claude/CLAUDE.md"
    "$HOME/.claude/settings.json   $REPO/common/config/claude/settings.json"
)

#---------------------------------------------------------------------------
# SWAY DESKTOP
#
# Sway is put together from separate small programs, each with its own config
# file, so there are a lot of them. The files themselves live in sway/ in this
# folder. None of this affects GNOME: only Sway's programs read these.
#---------------------------------------------------------------------------
SWAY_LINKS=(
    # config files
    "$HOME/.config/sway/config                        $HERE/sway/config/sway/config"            # key bindings, workspaces; starts desktop-session
    "$HOME/.config/waybar/config                      $HERE/sway/config/waybar/config"          # the top bar: what it shows
    "$HOME/.config/waybar/style.css                   $HERE/sway/config/waybar/style.css"       # the top bar: colours and fonts
    "$HOME/.config/alacritty/alacritty.toml           $HERE/sway/config/alacritty/alacritty.toml" # the terminal
    "$HOME/.config/mako/config                        $HERE/sway/config/mako/config"            # notification pop-ups
    "$HOME/.config/swaylock/config                    $HERE/sway/config/swaylock/config"        # the lock screen
    "$HOME/.config/xdg-desktop-portal/sway-portals.conf $HERE/sway/config/xdg-desktop-portal/sway-portals.conf" # screen sharing
    "$HOME/.config/xdg-desktop-portal-wlr/sway        $HERE/sway/config/xdg-desktop-portal-wlr/sway"            # screen sharing: pick a monitor

    # helper commands that the Sway key bindings call
    "$HOME/.local/bin/desktop-session                 $HERE/sway/bin/desktop-session"           # runs at login: tray icons, notifications, idle lock
    "$HOME/.local/bin/desktop-terminal                $HERE/sway/bin/desktop-terminal"          # Alt+Enter
    "$HOME/.local/bin/desktop-menu                    $HERE/sway/bin/desktop-menu"              # Alt+D program launcher
    "$HOME/.local/bin/desktop-control                 $HERE/sway/bin/desktop-control"           # lock, suspend, log out, reboot, power off
    "$HOME/.local/bin/desktop-screenshot              $HERE/sway/bin/desktop-screenshot"        # Print key
    "$HOME/.local/bin/desktop-swap                    $HERE/sway/bin/desktop-swap"              # Alt+S swap two windows
)

if [ "$(id -u)" -eq 0 ]; then
    echo "run this as yourself, not as root" >&2
    exit 1
fi

# link_all <list...>: make every link in the list.
link_all() {
    local pair link target
    for pair in "$@"; do
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
}

link_all "${LINKS[@]}"
link_all "${SWAY_LINKS[@]}"
