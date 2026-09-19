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
# Each line in a list is:   <link in your home folder>   <file in this repo>
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

#---------------------------------------------------------------------------
# SWAY DESKTOP
#
# Sway is put together from separate small programs, each with its own config
# file, so there are a lot of them. The files themselves live in
# debian-desktop/. None of this affects GNOME: only Sway's programs read these.
#
# NOT linked, on purpose: debian-desktop/config/wireplumber/90-preserve-pulseaudio.conf
# It switches off WirePlumber's sound and bluetooth handling so that PulseAudio
# can do it. This machine has no PulseAudio, so linking it would mean no sound.
#---------------------------------------------------------------------------
SWAY_LINKS=(
    # config files
    "$HOME/.config/sway/config                        $REPO/debian-desktop/config/sway/config"            # key bindings, workspaces; starts desktop-session
    "$HOME/.config/waybar/config                      $REPO/debian-desktop/config/waybar/config"          # the top bar: what it shows
    "$HOME/.config/waybar/style.css                   $REPO/debian-desktop/config/waybar/style.css"       # the top bar: colours and fonts
    "$HOME/.config/alacritty/alacritty.toml           $REPO/debian-desktop/config/alacritty/alacritty.toml" # the terminal
    "$HOME/.config/mako/config                        $REPO/debian-desktop/config/mako/config"            # notification pop-ups
    "$HOME/.config/swaylock/config                    $REPO/debian-desktop/config/swaylock/config"        # the lock screen
    "$HOME/.config/xdg-desktop-portal/sway-portals.conf $REPO/debian-desktop/config/xdg-desktop-portal/sway-portals.conf" # screen sharing
    "$HOME/.config/xdg-desktop-portal-wlr/sway        $REPO/debian-desktop/config/xdg-desktop-portal-wlr/sway"            # screen sharing: pick a monitor
    "$HOME/.config/debian-desktop/bashrc              $REPO/debian-desktop/config/bashrc"                 # loaded by the Sway terminal after .bashrc

    # helper commands that the Sway key bindings call
    "$HOME/.local/bin/desktop-session                 $REPO/debian-desktop/bin/desktop-session"           # runs at login: tray icons, notifications, idle lock
    "$HOME/.local/bin/desktop-terminal                $REPO/debian-desktop/bin/desktop-terminal"          # Alt+Enter
    "$HOME/.local/bin/desktop-menu                    $REPO/debian-desktop/bin/desktop-menu"              # Alt+D program launcher
    "$HOME/.local/bin/desktop-control                 $REPO/debian-desktop/bin/desktop-control"           # lock, suspend, log out, reboot, power off
    "$HOME/.local/bin/desktop-screenshot              $REPO/debian-desktop/bin/desktop-screenshot"        # Print key
    "$HOME/.local/bin/desktop-swap                    $REPO/debian-desktop/bin/desktop-swap"              # Alt+S swap two windows
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
