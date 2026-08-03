#!/usr/bin/env bash
#
# Provisions an Arch machine from this repo.
#
# Replaces install1.sh .. install5.sh, which were seven files with overlapping
# jobs, two of them near-identical forks, and two of them containing no
# executable code at all. What those scripts did is preserved here as phases;
# what they only described in comments moved to notes/arch-install.md.
#
#   ./setup.sh --dry-run          show what would change, touch nothing
#   ./setup.sh                    do it
#   ./setup.sh --phase links      run one phase (repeatable, or comma-separated)
#   ./setup.sh --machine asus     provision the ASUS laptop instead of the desktop
#
# MACHINE VARIANTS
#
# Two machines share this directory. They differ in exactly two configs, so
# rather than the old approach -- a whole forked copy of the link script per
# machine -- $MACHINE selects between them:
#
#   desktop   config/hypr        config/alacritty       (font 10.666666)
#   asus      config/hypr-asus   config/alacritty-4k    (font 11)
#
# Everything else is identical between them. If it is not detected correctly,
# pass --machine explicitly.
#
# ZONE RULE: linux/ is self-contained. Every file this script links is under
# linux/config/, and nothing here reads a sibling OS directory.

set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#---------------------------------------------------------------------------
# Configuration
#---------------------------------------------------------------------------

# pacman packages. Taken verbatim from install3_amd.sh / install3_intel.sh,
# which were 110 lines each and differed by exactly one word: the microcode
# package. That word is now detected at run time -- see $UCODE below -- so
# there is one list instead of two copies drifting apart.
PACKAGES=(
    neovim dolphin yazi bemenu unzip wl-clipboard tree less hwinfo
    bluez bluez-utils blueman
    pipewire pipewire-pulse pipewire-alsa wireplumber pipewire-audio
    nvidia nvidia-utils brightnessctl github-cli waybar firefox man-db alacritty
    firejail proton-vpn-gtk-app mesa-demos mesa-utils
    noto-fonts ttf-dejavu ttf-liberation archlinux-keyring
    plasma-workspace gwenview hyprpaper lsd
    testdisk rsync zip gzip p7zip dosfstools hyprshot ddrescue iotop
    usbutils exfatprogs freerdp wlr-randr ntfs-3g nmap vulkan-tools sbctl tmux
    cups cups-filters avahi nss-mdns ghostscript nvme-cli
)

# Services to enable. From install4.sh.
USER_SERVICES=(pipewire.service pipewire-pulse.service wireplumber.service)
SYSTEM_SERVICES=(bluetooth.service)

# Links common to both machines, as "link location|file in this repo".
#
# The old install2.sh pointed BASE_SOURCE at
# $HOME/source/repos-spencermx/linux/config -- a path that did not exist, in a
# repo that did not exist, expecting a config/ directory that did not exist
# either. It had been broken for a long time. This resolves paths from the
# script's own location instead, so it cannot drift again.
#
# It also linked workspace/, ultimate/ and gitrip.sh out of the repo. Those are
# personal documents and now live in the private `personal` repo, so they are
# deliberately absent.
LINKS_COMMON=(
    "$HOME/.vimrc|$REPO_ROOT/config/.vimrc"
    "$HOME/.bashrc|$REPO_ROOT/config/.bashrc"
    "$HOME/.gitconfig|$REPO_ROOT/config/.gitconfig"
    "$HOME/.tmux.conf|$REPO_ROOT/config/.tmux.conf"
    "$HOME/.config/nvim|$REPO_ROOT/config/nvim"
    "$HOME/.config/kdeglobals|$REPO_ROOT/config/kdeglobals"
    "$HOME/.config/waybar|$REPO_ROOT/config/waybar"
)

ENSURE_DIRS=(
    "$HOME/.config"
    "$HOME/.local/share"
    "$HOME/.local/bin"
)

EXPECTED_COMMANDS=(nvim git gh tmux alacritty waybar lsd yazi)

#---------------------------------------------------------------------------
# Helpers
#---------------------------------------------------------------------------

if [ -t 1 ]; then
    C_STEP=$'\033[36m'; C_ADD=$'\033[32m'; C_SKIP=$'\033[90m'
    C_WARN=$'\033[33m'; C_OFF=$'\033[0m'
else
    C_STEP=''; C_ADD=''; C_SKIP=''; C_WARN=''; C_OFF=''
fi

step()   { printf '\n%s== %s%s\n' "$C_STEP" "$*" "$C_OFF"; }
change() { printf '%s   + %s%s\n' "$C_ADD"  "$*" "$C_OFF"; }
skip()   { printf '%s   . %s%s\n' "$C_SKIP" "$*" "$C_OFF"; }
warn()   { printf '%s   ! %s%s\n' "$C_WARN" "$*" "$C_OFF"; }

DRY_RUN=0
MACHINE=""
PHASES="packages links services"
FAILED_PHASES=""
PROBLEM_COUNT=0

fail_phase() {
    case " $FAILED_PHASES " in
        *" $1 "*) ;;
        *) FAILED_PHASES="$FAILED_PHASES $1" ;;
    esac
}

wants_phase() {
    case " $PHASES " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

PAIR_L=""; PAIR_R=""
split_pair() { PAIR_L="${1%%|*}"; PAIR_R="${1#*|}"; }

tilde() {
    case "$1" in
        "$HOME") printf '~' ;;
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

has() { command -v "$1" >/dev/null 2>&1; }
problem() { PROBLEM_COUNT=$((PROBLEM_COUNT + 1)); }

# Intel and AMD ship different microcode packages, and installing the wrong one
# is the single difference that used to justify two copies of a 110-line
# script.
detect_ucode() {
    if grep -qi 'GenuineIntel' /proc/cpuinfo 2>/dev/null; then
        printf 'intel-ucode'
    elif grep -qi 'AuthenticAMD' /proc/cpuinfo 2>/dev/null; then
        printf 'amd-ucode'
    fi
}

# The ASUS laptop is the 4k machine. Detected from the DMI product name, which
# is readable without root on any modern kernel.
detect_machine() {
    local vendor=""
    [ -r /sys/class/dmi/id/sys_vendor ] && vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)"
    case "$vendor" in
        *[Aa][Ss][Uu][Ss]*) printf 'asus' ;;
        *) printf 'desktop' ;;
    esac
}

#---------------------------------------------------------------------------
# Argument parsing
#---------------------------------------------------------------------------

parse_args() {
    local phases_set=0 p
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run|-n) DRY_RUN=1 ;;
            --machine|-m)
                shift
                [ $# -gt 0 ] || { echo "--machine needs a value" >&2; exit 2; }
                MACHINE="$1"
                ;;
            --phase|-p)
                shift
                [ $# -gt 0 ] || { echo "--phase needs a value" >&2; exit 2; }
                if [ "$phases_set" -eq 0 ]; then PHASES=""; phases_set=1; fi
                PHASES="$PHASES $(printf '%s' "$1" | tr ',' ' ')"
                ;;
            --help|-h)
                sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,2\} \{0,1\}//'
                exit 0
                ;;
            *) echo "unknown argument: $1" >&2; exit 2 ;;
        esac
        shift
    done

    for p in $PHASES; do
        case "$p" in
            packages|links|services) ;;
            *) echo "unknown phase: $p (packages links services)" >&2; exit 2 ;;
        esac
    done

    [ -n "$MACHINE" ] || MACHINE="$(detect_machine)"
    case "$MACHINE" in
        desktop|asus) ;;
        *) echo "unknown machine: $MACHINE (desktop asus)" >&2; exit 2 ;;
    esac
}

# The per-machine half of the link table, appended to LINKS_COMMON.
machine_links() {
    case "$MACHINE" in
        asus)
            echo "$HOME/.config/hypr|$REPO_ROOT/config/hypr-asus"
            echo "$HOME/.config/alacritty|$REPO_ROOT/config/alacritty-4k"
            ;;
        *)
            echo "$HOME/.config/hypr|$REPO_ROOT/config/hypr"
            echo "$HOME/.config/alacritty|$REPO_ROOT/config/alacritty"
            ;;
    esac
}

#---------------------------------------------------------------------------
# Phase: packages
#---------------------------------------------------------------------------

phase_packages() {
    step "Packages ($MACHINE)"

    if ! has pacman; then
        warn 'pacman not found -- this is not an Arch system. Skipping.'
        fail_phase packages
        return
    fi

    local ucode to_install="" count=0 p
    ucode="$(detect_ucode)"
    if [ -n "$ucode" ]; then
        skip "microcode: $ucode"
    else
        warn 'could not detect CPU vendor -- no microcode package selected'
    fi

    for p in $ucode "${PACKAGES[@]}"; do
        if pacman -Qi "$p" >/dev/null 2>&1; then
            skip "$p already installed"
        else
            to_install="$to_install $p"
            count=$((count + 1))
        fi
    done

    if [ "$count" -eq 0 ]; then
        skip 'everything declared is installed'
        return
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        change "would install $count package(s):$to_install"
        return
    fi

    # One pacman call rather than one per package: it resolves the whole set
    # together and asks for confirmation once.
    change "installing $count package(s)"
    # shellcheck disable=SC2086
    sudo pacman -S --needed $to_install || {
        warn 'pacman reported errors -- check the output above'
        fail_phase packages
    }
}

#---------------------------------------------------------------------------
# Phase: links
#---------------------------------------------------------------------------

link_one() {
    local link=$1 target=$2 short
    short="$(tilde "$link")"

    if [ ! -e "$target" ]; then
        warn "target missing, skipping: $(tilde "$target")"
        fail_phase links
        return
    fi

    if [ -L "$link" ] && [ "$(readlink "$link")" = "$target" ]; then
        skip "$short already linked"
        return
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        change "would link $short -> $(tilde "$target")"
        return
    fi

    mkdir -p "$(dirname "$link")"

    # A real file is backed up before replacement. A symlink is not -- copying
    # one copies its target, which is wrong and pointless.
    if [ -e "$link" ] && [ ! -L "$link" ]; then
        if cp -R "$link" "$link.bak"; then
            warn "backed up existing file to $short.bak"
        else
            warn "could not back up $short -- skipping it to be safe"
            fail_phase links
            return
        fi
    fi

    rm -rf "$link"
    if ln -s "$target" "$link"; then
        change "$short -> $(tilde "$target")"
    else
        warn "FAILED: $short"
        fail_phase links
    fi
}

phase_links() {
    step "Links ($MACHINE)"

    local d entry
    for d in "${ENSURE_DIRS[@]}"; do
        [ -d "$d" ] && continue
        if [ "$DRY_RUN" -eq 1 ]; then change "would create $(tilde "$d")"; continue; fi
        mkdir -p "$d" && change "created $(tilde "$d")"
    done

    for entry in "${LINKS_COMMON[@]}"; do
        split_pair "$entry"
        link_one "$PAIR_L" "$PAIR_R"
    done

    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        split_pair "$entry"
        link_one "$PAIR_L" "$PAIR_R"
    done <<EOF
$(machine_links)
EOF
}

#---------------------------------------------------------------------------
# Phase: services
#---------------------------------------------------------------------------

phase_services() {
    step 'Services'

    if ! has systemctl; then
        warn 'systemctl not found -- skipping'
        fail_phase services
        return
    fi

    local s
    for s in "${USER_SERVICES[@]}"; do
        if ! systemctl --user cat "$s" >/dev/null 2>&1; then
            warn "$s (user) does not exist -- skipping"
            continue
        fi
        if systemctl --user is-enabled --quiet "$s" 2>/dev/null; then
            skip "$s (user) already enabled"
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then change "would enable $s (user)"; continue; fi
        change "enabling $s (user)"
        systemctl --user enable "$s" || warn "failed to enable $s (user) -- continuing"
    done

    for s in "${SYSTEM_SERVICES[@]}"; do
        if ! systemctl cat "$s" >/dev/null 2>&1; then
            warn "$s (system) does not exist -- skipping"
            continue
        fi
        if sudo systemctl is-enabled --quiet "$s" 2>/dev/null; then
            skip "$s (system) already enabled"
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then change "would enable $s (system)"; continue; fi
        change "enabling $s (system)"
        sudo systemctl enable "$s" || warn "failed to enable $s (system) -- continuing"
    done

    # From install5.sh: make `vim` resolve to nvim system-wide. Only meaningful
    # once neovim is installed, which is why it runs after packages.
    if has nvim; then
        local vim_path nvim_path
        nvim_path="$(command -v nvim)"
        vim_path="$(command -v vim 2>/dev/null)"
        if [ -n "$vim_path" ] && [ "$(readlink -f "$vim_path" 2>/dev/null)" = "$nvim_path" ]; then
            skip 'vim already resolves to nvim'
        elif [ "$DRY_RUN" -eq 1 ]; then
            change 'would point vim at nvim'
        elif [ -n "$vim_path" ]; then
            change "vim -> nvim"
            sudo ln -sf "$nvim_path" "$vim_path" || warn 'could not repoint vim'
        else
            skip 'no vim on PATH to repoint'
        fi
    fi
}

#---------------------------------------------------------------------------
# Health check
#---------------------------------------------------------------------------

verify() {
    step 'Health check'

    local entry link target short c
    for entry in "${LINKS_COMMON[@]}" $(machine_links); do
        split_pair "$entry"
        link="$PAIR_L"; target="$PAIR_R"
        short="$(tilde "$link")"
        if [ -L "$link" ]; then
            if [ ! -e "$link" ]; then
                problem; warn "DANGLING           $short"
            elif [ "$(readlink "$link")" != "$target" ]; then
                problem; warn "WRONG TARGET       $short -> $(readlink "$link")"
            else
                skip "link ok            $short"
            fi
        elif [ -e "$link" ]; then
            problem; warn "NOT A LINK         $short"
        else
            problem; warn "missing            $short"
        fi
    done

    if has pacman; then
        local missing="" mcount=0 p
        for p in "$(detect_ucode)" "${PACKAGES[@]}"; do
            [ -n "$p" ] || continue
            pacman -Qi "$p" >/dev/null 2>&1 || { missing="$missing $p"; mcount=$((mcount + 1)); }
        done
        if [ "$mcount" -gt 0 ]; then
            problem; warn "$mcount package(s) missing:$missing"
        else
            skip 'all declared packages installed'
        fi
    fi

    for c in "${EXPECTED_COMMANDS[@]}"; do
        if has "$c"; then skip "command ok         $c  ($(command -v "$c"))"
        else problem; warn "NOT ON PATH        $c"; fi
    done

    [ "$PROBLEM_COUNT" -gt 0 ] && fail_phase verify
    return 0
}

#---------------------------------------------------------------------------
# Main
#---------------------------------------------------------------------------

main() {
    parse_args "$@"

    if [ "$(uname -s)" != "Linux" ]; then
        echo "this is the linux setup; uname says $(uname -s). Refusing to run." >&2
        exit 2
    fi

    printf '%slinux setup - %s  (machine: %s)%s\n' "$C_STEP" "$REPO_ROOT" "$MACHINE" "$C_OFF"
    [ "$DRY_RUN" -eq 1 ] && printf '%sDRY RUN - nothing will be changed%s\n' "$C_WARN" "$C_OFF"

    wants_phase packages && phase_packages
    wants_phase links    && phase_links
    wants_phase services && phase_services

    verify

    if [ -n "$FAILED_PHASES" ]; then
        printf '\n%sFinished with problems in:%s%s\n' "$C_WARN" "$FAILED_PHASES" "$C_OFF"
        exit 1
    fi

    printf '\n%sAll good.%s\n' "$C_STEP" "$C_OFF"
    exit 0
}

main "$@"
