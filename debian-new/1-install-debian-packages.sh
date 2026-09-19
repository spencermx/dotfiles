#!/usr/bin/env bash
# New Debian setup, built one small step at a time.
#
# Step 1: install packages from Debian.
#
# Run as root:   sudo ./1-install-debian-packages.sh

set -euo pipefail

PACKAGES=(
    # firmware for this ThinkPad
    firmware-mediatek firmware-realtek firmware-misc-nonfree amd64-microcode
    firmware-amd-graphics

    # system services
    unattended-upgrades systemd-timesyncd network-manager tlp fwupd

    # console
    console-setup kbd locales physlock

    # tools
    tmux vim git openssh-client build-essential python3 luarocks curl wget
    ca-certificates gnupg ripgrep fd-find fzf zoxide lsd tree less jq
    man-db manpages manpages-dev unzip zip xz-utils rsync file psmisc
    procps lsof strace htop ncdu bat brightnessctl brightness-udev acpi
    python3-venv pipx cmake libfontconfig1

    # GitHub CLI, for the `repo` command and git logins
    gh
)

if [ "$(id -u)" -ne 0 ]; then
    echo "run this as root:  sudo $0" >&2
    exit 1
fi

apt-get update
apt-get install -y --no-install-recommends "${PACKAGES[@]}"
