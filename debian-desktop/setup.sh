#!/usr/bin/env bash
# Add an Arch-style Sway desktop to Debian 13. Run as the desktop user.
set -euo pipefail

PROFILE_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=0
PHASES=packages,services,links
[[ $EUID -ne 0 ]] || PHASES=packages,services

PACKAGES=(
    sway swaybg swayidle swaylock autotiling waybar xwayland
    alacritty bemenu libbemenu-wayland mako-notifier mate-polkit
    dbus-user-session libpam-systemd xdg-utils xdg-user-dirs
    # PipeWire carries screen captures; PulseAudio continues to handle sound.
    pipewire wireplumber xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk
    firefox-esr thunar fonts-jetbrains-mono fonts-dejavu-core fonts-font-awesome
    network-manager network-manager-applet nm-connection-editor
    bluez blueman pulseaudio-utils pulseaudio-module-bluetooth pavucontrol
    brightnessctl brightness-udev playerctl grim slurp wl-clipboard
    libnotify-bin jq python3
)
LINKS=(
    '.config/wireplumber/wireplumber.conf.d/90-preserve-pulseaudio.conf|config/wireplumber/90-preserve-pulseaudio.conf'
    '.config/sway/config|config/sway/config'
    '.config/waybar/config|config/waybar/config'
    '.config/waybar/style.css|config/waybar/style.css'
    '.config/alacritty/alacritty.toml|config/alacritty/alacritty.toml'
    '.config/mako/config|config/mako/config'
    '.config/swaylock/config|config/swaylock/config'
    '.config/xdg-desktop-portal/sway-portals.conf|config/xdg-desktop-portal/sway-portals.conf'
    '.config/xdg-desktop-portal-wlr/sway|config/xdg-desktop-portal-wlr/sway'
    '.config/debian-desktop/bashrc|config/bashrc'
    '.local/bin/desktop-session|bin/desktop-session'
    '.local/bin/desktop-terminal|bin/desktop-terminal'
    '.local/bin/desktop-menu|bin/desktop-menu'
    '.local/bin/desktop-control|bin/desktop-control'
    '.local/bin/desktop-screenshot|bin/desktop-screenshot'
    '.local/bin/desktop-swap|bin/desktop-swap'
)
COMMANDS=(sway swaymsg swaybg swayidle swaylock autotiling waybar alacritty wireplumber
    bemenu bemenu-run mako firefox-esr thunar nm-applet blueman-applet
    pactl pavucontrol brightnessctl playerctl grim slurp wl-copy jq)

usage() {
    printf '%s\n' \
        'Usage: ./setup.sh [--dry-run] [--phase packages,services,links|check]' \
        'Default: authenticate once for packages/services, then link user config.' \
        '  --dry-run       Preview packages and links without changes or root.' \
        '  --phase links   Link config only; no root.' \
        '  --phase check   Check installed packages and links; no changes.' \
        'As root, the default is packages,services; never creates root dotfiles.'
}
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
wants() { [[ ,$PHASES, == *,$1,* ]]; }
while (($#)); do
    case "$1" in
        --dry-run|-n) DRY_RUN=1 ;;
        --phase|-p) (($# >= 2)) || die '--phase needs a value'; PHASES=$2; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
    shift
done
IFS=, read -r -a selected <<< "$PHASES"
[[ -n $PHASES && $PHASES != ,* && $PHASES != *, && $PHASES != *,,* ]] || die 'Empty phase'
for phase in "${selected[@]}"; do
    case "$phase" in packages|services|links|check) ;; *) die "Unknown phase: $phase" ;; esac
done
# shellcheck source=/etc/os-release
. /etc/os-release
[[ ${ID:-} == debian && ${VERSION_ID:-} == 13 ]] || die 'This profile targets Debian 13.'
[[ $EUID -ne 0 ]] || ! wants links || die 'Run the links phase as your desktop user.'

packages() {
    if ((DRY_RUN)); then
        printf 'Would refresh apt and install/update these desktop packages:\n%s\n' "${PACKAGES[*]}"
        apt-get -s --no-remove --no-install-recommends install "${PACKAGES[@]}"
    else
        apt-get update
        # Refuse transactions which would remove Xfce or replace the audio stack.
        apt-get install -y --no-remove --no-install-recommends "${PACKAGES[@]}"
    fi
}
services() {
    local service
    for service in NetworkManager.service bluetooth.service; do
        if ((DRY_RUN)); then
            printf 'Would enable and start %s (does not restart an active service).\n' "$service"
        else
            systemctl enable --now "$service"
        fi
    done
}
links() {
    local scope=${1:-all} entry relative target destination parent backup_root=''
    for entry in "${LINKS[@]}"; do
        relative=${entry%%|*}
        if [[ $scope == audio && $relative != .config/wireplumber/* ]]; then continue; fi
        target="$PROFILE_ROOT/${entry#*|}"
        destination="$HOME/$relative"
        [[ -f $target ]] || die "Missing source: $target"
        if [[ -L $destination && $(readlink -- "$destination") == "$target" ]]; then
            printf 'Already linked: %s\n' "$destination"
            continue
        fi
        # Never write through a config-directory symlink into another profile.
        parent=$(dirname -- "$destination")
        while [[ $parent != "$HOME" && $parent != / ]]; do
            [[ ! -L $parent ]] || die "Symlinked parent $parent; resolve it before linking $destination"
            parent=$(dirname -- "$parent")
        done
        if ((DRY_RUN)); then
            printf 'Would back up if present, then link: %s -> %s\n' "$destination" "$target"
            continue
        fi
        mkdir -p -- "$(dirname -- "$destination")"
        if [[ -e $destination || -L $destination ]]; then
            if [[ -z $backup_root ]]; then
                mkdir -p -- "$HOME/.local/state/debian-desktop/backups"
                backup_root=$(mktemp -d "$HOME/.local/state/debian-desktop/backups/$(date +%Y%m%d-%H%M%S).XXXXXX")
            fi
            mkdir -p -- "$backup_root/$(dirname -- "$relative")"
            mv -- "$destination" "$backup_root/$relative"
        fi
        ln -s -- "$target" "$destination"
        printf 'Linked: %s\n' "$destination"
    done
    [[ -z $backup_root ]] || printf 'Previous files preserved at: %s\n' "$backup_root"
}
check() {
    local failures=0 package command entry destination target
    for package in "${PACKAGES[@]}"; do
        if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) != 'install ok installed' ]]; then
            printf 'Missing package: %s\n' "$package" >&2; failures=$((failures + 1))
        fi
    done
    for command in "${COMMANDS[@]}"; do
        if ! command -v "$command" >/dev/null; then
            printf 'Missing command: %s\n' "$command" >&2; failures=$((failures + 1))
        fi
    done
    if [[ ! -f /usr/share/wayland-sessions/sway.desktop ]]; then
        printf 'Missing Sway login session.\n' >&2; failures=$((failures + 1))
    fi
    if ((EUID != 0)); then
        for entry in "${LINKS[@]}"; do
            destination="$HOME/${entry%%|*}"
            target="$PROFILE_ROOT/${entry#*|}"
            if [[ ! -L $destination || ! -e $destination || $(readlink -- "$destination") != "$target" ]]; then
                printf 'Incorrect link: %s\n' "$destination" >&2; failures=$((failures + 1))
            fi
        done
    fi
    if ((failures)); then
        printf '%s check(s) failed.\n' "$failures" >&2
        return 1
    fi
    printf 'Desktop packages, commands and applicable links are ready.\n'
}

# Elevate only the system phases and return to this user's HOME for links.
root_phases=''
for phase in packages services; do
    if wants "$phase"; then root_phases+="${root_phases:+,}$phase"; fi
done
if [[ -n $root_phases && $EUID -ne 0 && $DRY_RUN == 0 ]]; then
    # Apply audio coexistence before a newly installed WirePlumber can start.
    if wants packages; then links audio; fi
    printf 'Installing desktop packages/services. Authentication happens locally.\n'
    if command -v sudo >/dev/null && sudo -n true 2>/dev/null; then
        sudo /usr/bin/bash "$PROFILE_ROOT/setup.sh" --phase "$root_phases"
    else
        printf 'Enter the root password at the su prompt.\n'
        printf -v root_command '%q ' /usr/bin/bash "$PROFILE_ROOT/setup.sh" --phase "$root_phases"
        su -c "$root_command"
    fi
else
    if wants packages; then packages; fi
    if wants services; then services; fi
fi
if wants links; then links; fi
if ((DRY_RUN)); then
    printf '\nPreview complete; nothing changed.\n'
else
    check
    if ((EUID != 0)); then
        printf '\nReady for login: select Sway in LightDM. Alt+Enter opens a terminal.\n'
        printf 'Xfce remains available. This script never logs out the running session.\n'
    fi
fi
