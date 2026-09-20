#!/usr/bin/env bash
# Step 1: install packages from Debian.
#
# Run as root:   sudo ./1-install-debian-packages.sh
#
# Three lists, all always installed:
#
#   PACKAGES           the base machine: firmware, services, command-line tools
#   SWAY_PACKAGES      the Sway desktop
#   RECOVERY_PACKAGES  virtualization and disk recovery tools
#
# It then switches on automatic security updates.
#
# Everything here comes from Debian and is not pinned: Debian 13 freezes the
# versions and only ships security patches for them.

set -euo pipefail

PACKAGES=(
    # firmware for this ThinkPad
    firmware-mediatek firmware-realtek firmware-misc-nonfree amd64-microcode
    firmware-amd-graphics

    # system services
    unattended-upgrades systemd-timesyncd network-manager fwupd nftables

    # console
    console-setup kbd locales physlock

    # tools
    tmux vim git openssh-client build-essential python3 luarocks curl wget
    ca-certificates gnupg ripgrep fd-find fzf zoxide lsd tree less jq
    man-db manpages manpages-dev unzip zip xz-utils rsync file psmisc
    procps lsof strace htop ncdu bat brightnessctl brightness-udev acpi
    python3-venv pipx cmake libfontconfig1
)

#---------------------------------------------------------------------------
# SWAY DESKTOP
#
# Adds a Sway session NEXT TO the desktop you already have. It does not remove
# GNOME or change what starts at boot: you pick Sway at the login screen (the
# gear icon). Its config files are linked by step 2.
#---------------------------------------------------------------------------
SWAY_PACKAGES=(
    # the desktop itself
    sway swaybg swayidle swaylock autotiling waybar xwayland
    alacritty bemenu libbemenu-wayland mako-notifier mate-polkit
    dbus-user-session libpam-systemd xdg-utils xdg-user-dirs

    # screen sharing
    pipewire wireplumber xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk

    # apps and fonts
    firefox-esr thunar fonts-jetbrains-mono fonts-dejavu-core fonts-font-awesome

    # network and bluetooth
    network-manager-applet nm-connection-editor
    bluez blueman

    # sound controls. pactl (in pulseaudio-utils) is what the volume keys run;
    # it talks to PipeWire fine. Do not add pulseaudio-module-bluetooth: it
    # drags in PulseAudio, and apt would have to remove GNOME's audio to fit it.
    pulseaudio-utils pavucontrol

    # media keys, screenshots, clipboard, notifications
    playerctl grim slurp wl-clipboard
    libnotify-bin
)

#---------------------------------------------------------------------------
# VIRTUALIZATION / DISK RECOVERY
#
# Tools for inspecting disks through a small VM. Debian installs QEMU,
# qemu-utils and supermin as dependencies.
#---------------------------------------------------------------------------
RECOVERY_PACKAGES=(
    guestfish python3-guestfs
)

if [ "$(id -u)" -ne 0 ]; then
    echo "run this as root:  sudo $0" >&2
    exit 1
fi

apt-get update

apt-get install -y --no-install-recommends "${PACKAGES[@]}"

# --no-remove: if installing the desktop would REMOVE anything, apt refuses
# and nothing changes.
apt-get install -y --no-remove --no-install-recommends "${SWAY_PACKAGES[@]}"
systemctl enable --now NetworkManager.service bluetooth.service

apt-get install -y --no-remove --no-install-recommends "${RECOVERY_PACKAGES[@]}"

#---------------------------------------------------------------------------
# AUTOMATIC SECURITY UPDATES
#
# Installing unattended-upgrades is not enough. Debian only runs it each night
# if this file says so; without it, nothing is ever updated automatically.
# What gets installed is Debian's default choice: security updates only.
#---------------------------------------------------------------------------
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
CONF
chmod 644 /etc/apt/apt.conf.d/20auto-upgrades
echo "automatic security updates: on"
