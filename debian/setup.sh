#!/usr/bin/env bash
#
# Provisions the console-only Debian ThinkPad from this repo.
#
#   ./setup.sh --dry-run              preview, changes nothing
#   ./setup.sh                        every phase the current user can run
#   ./setup.sh --phase packages       apt packages                (needs root)
#   ./setup.sh --phase system         console, clock, network, updates (root)
#   ./setup.sh --phase links          symlink dotfiles            (no root)
#   ./setup.sh --phase tools          user-local binaries         (no root)
#   ./setup.sh --phase links,tools    both no-root phases
#
# There is no sudo on this machine, by design. Run the root phases from a root
# shell (`su -`), and the user phases as yourself. Running everything as root
# would write $HOME links into /root, so the script refuses.
#
# Read debian/notes/build-plan.md before changing anything here. The machine is
# provisioned once behind a one-way gate; after it, packages/system can never
# run again and links/tools must keep working forever.

set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_ROOT="$(dirname "$REPO_ROOT")/common"

#---------------------------------------------------------------------------
# Configuration
#---------------------------------------------------------------------------

# Everything apt supplies. Nothing here pulls X or Wayland -- verify with
# `apt-get -s install ... | grep -iE 'xorg|wayland|libx11'` before adding.
#
# Absent on purpose: neovim, nodejs, gh, yazi (all user-local, see $TOOLS, so
# they stay updatable after the gate), sudo, and anything graphical.
PACKAGES=(
    # firmware and microcode, pinned to this machine: AMD Ryzen 5 PRO 7530U,
    # MediaTek MT7922 wifi, Realtek gigabit ethernet.
    firmware-mediatek firmware-realtek firmware-misc-nonfree amd64-microcode
    # not optional despite there being no display server: amdgpu registers
    # /sys/class/backlight/amdgpu_bl0, and will not init without firmware.
    firmware-amd-graphics

    # system services
    unattended-upgrades systemd-timesyncd network-manager tlp fwupd

    # console, locale, input
    console-setup kbd locales

    # toolchain
    tmux vim git openssh-client build-essential python3 curl wget
    ca-certificates gnupg ripgrep fd-find fzf zoxide lsd tree less jq
    man-db manpages manpages-dev unzip zip xz-utils rsync file psmisc
    procps lsof strace htop ncdu bat brightnessctl acpi
)

# "link location|file in this repo"
LINKS=(
    "$HOME/.bashrc|$REPO_ROOT/config/.bashrc"
    "$HOME/.gitconfig|$REPO_ROOT/config/.gitconfig"
    "$HOME/.gitconfig.common|$SHARED_ROOT/config/.gitconfig"

    # This zone's own tmux config -- no clipboard exists here. It source-files
    # the shared one, so both links are required.
    "$HOME/.tmux.conf|$REPO_ROOT/config/.tmux.conf"
    "$HOME/.tmux.conf.common|$SHARED_ROOT/config/.tmux.conf"

    "$HOME/.vimrc|$SHARED_ROOT/config/.vimrc"
    "$HOME/.config/nvim|$SHARED_ROOT/config/nvim"
    "$HOME/.config/git/ignore|$SHARED_ROOT/config/git/ignore"

    "$HOME/.claude/CLAUDE.md|$SHARED_ROOT/config/claude/CLAUDE.md"
    "$HOME/.claude/settings.json|$SHARED_ROOT/config/claude/settings.json"
)

ENSURE_DIRS=(
    "$HOME/.config"
    "$HOME/.config/git"
    "$HOME/.local/share"
    "$HOME/.local/bin"
    "$HOME/.claude"
    "$HOME/source/repos"
)

# User-local binaries, as "command|installer function". Everything here lives
# under $HOME so it can be updated with no root for the life of the machine.
TOOLS=(nvim gh yazi)

EXPECTED_COMMANDS=(git tmux nvim lsd rg fzf zoxide bat fdfind brightnessctl claude)

# Console font. The default 8x16 at 1080p on a 14" panel is punishing for a
# full day, and /etc/default/console-setup needs root to change.
CONSOLE_FONTFACE="Terminus"
CONSOLE_FONTSIZE="16x32"

#---------------------------------------------------------------------------
# Helpers
#---------------------------------------------------------------------------

if [ -t 1 ]; then
    C_STEP=$'\033[36m'; C_ADD=$'\033[32m'; C_SKIP=$'\033[90m'
    C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_OFF=$'\033[0m'
else
    C_STEP=''; C_ADD=''; C_SKIP=''; C_WARN=''; C_ERR=''; C_OFF=''
fi

DRY_RUN=0
PHASES=""
FAILED_PHASES=""
PROBLEM_COUNT=0

step()    { printf '\n%s== %s%s\n' "$C_STEP" "$*" "$C_OFF"; }
added()   { printf '   %s+ %s%s\n' "$C_ADD"  "$*" "$C_OFF"; }
skipped() { printf '   %s. %s%s\n' "$C_SKIP" "$*" "$C_OFF"; }
warned()  { printf '   %s! %s%s\n' "$C_WARN" "$*" "$C_OFF"; }
problem() { printf '   %sx %s%s\n' "$C_ERR"  "$*" "$C_OFF"; PROBLEM_COUNT=$((PROBLEM_COUNT + 1)); }

fail_phase() {
    case " $FAILED_PHASES " in
        *" $1 "*) ;;
        *) FAILED_PHASES="$FAILED_PHASES $1" ;;
    esac
}

wants_phase() {
    [ -z "$PHASES" ] && return 0
    case ",$PHASES," in *",$1,"*) return 0 ;; esac
    return 1
}

is_root() { [ "$(id -u)" -eq 0 ]; }

# The account the machine is actually used from. Under `su -` neither $SUDO_USER
# nor $USER names it, so fall back to the single UID>=1000 account -- which is
# what this machine has, and the script says which one it picked rather than
# assuming silently.
target_user() {
    if [ -n "$SUDO_USER" ]; then
        printf '%s' "$SUDO_USER"
        return
    fi
    local u
    u="$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1 }' /etc/passwd | head -1)"
    printf '%s' "$u"
}

run() {
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '   %s? %s%s\n' "$C_SKIP" "$*" "$C_OFF"
        return 0
    fi
    "$@"
}

# Write $2 to file $1 only when the content differs. Returns 0 if it wrote.
write_file() {
    local path="$1" content="$2"
    if [ -f "$path" ] && [ "$(cat "$path")" = "$content" ]; then
        skipped "$path already correct"
        return 1
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '   %s? write %s%s\n' "$C_SKIP" "$path" "$C_OFF"
        return 0
    fi
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path" || return 1
    added "wrote $path"
    return 0
}

#---------------------------------------------------------------------------
# Phase: packages
#---------------------------------------------------------------------------

phase_packages() {
    step "Packages"

    if ! is_root; then
        problem "packages needs root -- run it from \`su -\`"
        fail_phase packages
        return
    fi

    local missing=()
    local p
    for p in "${PACKAGES[@]}"; do
        if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed"; then
            continue
        fi
        missing+=("$p")
    done

    # Name anything apt does not have before trying, so a single absent package
    # does not fail the whole transaction with a confusing message. On this
    # machine that matters: a package missing here cannot be added later.
    local unavailable=()
    for p in "${missing[@]}"; do
        if [ -z "$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/ { print $2 }' | grep -v '(none)')" ]; then
            unavailable+=("$p")
        fi
    done

    if [ ${#unavailable[@]} -gt 0 ]; then
        problem "not in the archive: ${unavailable[*]}"
        warned "install a user-local build instead, or fix sources.list -- do not skip and move on"
        fail_phase packages
        return
    fi

    if [ ${#missing[@]} -eq 0 ]; then
        skipped "all ${#PACKAGES[@]} packages present"
    else
        added "installing ${#missing[@]}: ${missing[*]}"
        run apt-get update -qq || { fail_phase packages; return; }
        run env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}" \
            || { fail_phase packages; return; }
    fi

    added "upgrading what is behind"
    run apt-get update -qq
    run env DEBIAN_FRONTEND=noninteractive apt-get -y upgrade || fail_phase packages
}

#---------------------------------------------------------------------------
# Phase: system
#---------------------------------------------------------------------------

phase_system() {
    step "System"

    if ! is_root; then
        problem "system needs root -- run it from \`su -\`"
        fail_phase system
        return
    fi

    local user
    user="$(target_user)"
    if [ -z "$user" ]; then
        problem "could not identify the non-root account"
        fail_phase system
        return
    fi
    added "configuring for user: $user"

    # -- console font -------------------------------------------------------
    if grep -q "^FONTFACE=\"$CONSOLE_FONTFACE\"" /etc/default/console-setup 2>/dev/null &&
       grep -q "^FONTSIZE=\"$CONSOLE_FONTSIZE\"" /etc/default/console-setup 2>/dev/null; then
        skipped "console font already $CONSOLE_FONTFACE $CONSOLE_FONTSIZE"
    else
        run sed -i "s/^FONTFACE=.*/FONTFACE=\"$CONSOLE_FONTFACE\"/; s/^FONTSIZE=.*/FONTSIZE=\"$CONSOLE_FONTSIZE\"/" \
            /etc/default/console-setup && added "console font -> $CONSOLE_FONTFACE $CONSOLE_FONTSIZE"
        run setupcon --save 2>/dev/null || warned "setupcon deferred to next boot"
    fi

    # -- clock --------------------------------------------------------------
    # Not cosmetic. If the clock drifts far enough, TLS certificate validation
    # fails and git, apt and claude all stop at once with errors that never
    # mention the clock -- and fixing it needs root.
    if systemctl is-enabled systemd-timesyncd >/dev/null 2>&1; then
        skipped "systemd-timesyncd already enabled"
    else
        run systemctl enable --now systemd-timesyncd || fail_phase system
        added "systemd-timesyncd enabled"
    fi

    # -- groups -------------------------------------------------------------
    # video: brightnessctl's udev rule grants this group write access to
    # /sys/class/backlight. netdev: NetworkManager convention.
    local g
    for g in video netdev; do
        if id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
            skipped "$user already in $g"
        else
            run usermod -aG "$g" "$user" && added "$user added to $g"
        fi
    done

    # -- polkit: join new wifi without an administrator ----------------------
    # THE one that decides whether this machine works in a library. With root
    # locked and no admin group, NetworkManager's default auth_admin rules make
    # connecting to an unseen network impossible. trixie's polkit does not read
    # the old .pkla files, so this must be a .rules file.
    write_file /etc/polkit-1/rules.d/50-nm-console.rules \
"// Written by debian/setup.sh. Lets $user manage NetworkManager with no
// administrator present, which is the state this machine ends in.
polkit.addRule(function(action, subject) {
    if (action.id.indexOf(\"org.freedesktop.NetworkManager.\") === 0 &&
        subject.user === \"$user\") {
        return polkit.Result.YES;
    }
});"

    # -- unattended-upgrades ------------------------------------------------
    write_file /etc/apt/apt.conf.d/20auto-upgrades \
'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";'

    write_file /etc/apt/apt.conf.d/52unattended-upgrades-local \
'// Written by debian/setup.sh. Overrides 50unattended-upgrades, which is a
// conffile and would prompt on upgrade if edited in place.

Unattended-Upgrade::Origins-Pattern {
    "origin=Debian,codename=${distro_codename},label=Debian-Security";
    "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
    "origin=Debian,codename=${distro_codename}-updates";
};

// Without this /boot fills, apt starts failing on every run, and there is no
// root left to clean it up. The most likely way this machine dies quietly.
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";

// A conffile prompt with nobody to answer it stalls the upgrade forever.
Dpkg::Options {
    "--force-confdef";
    "--force-confold";
};

// Rebooting mid-sentence in a library is worse than a delayed kernel patch.
// systemctl reboot still works unprivileged through logind, so this is manual.
Unattended-Upgrade::Automatic-Reboot "false";'

    if systemctl is-enabled unattended-upgrades >/dev/null 2>&1; then
        skipped "unattended-upgrades already enabled"
    else
        run systemctl enable --now unattended-upgrades || fail_phase system
    fi

    # -- power --------------------------------------------------------------
    if systemctl is-enabled tlp >/dev/null 2>&1; then
        skipped "tlp already enabled"
    else
        run systemctl enable --now tlp || warned "tlp did not enable"
    fi
}

#---------------------------------------------------------------------------
# Phase: links
#---------------------------------------------------------------------------

link_one() {
    local dest="$1" src="$2"

    if [ ! -e "$src" ]; then
        problem "source missing: $src"
        return 1
    fi

    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        skipped "$dest"
        return 0
    fi

    run mkdir -p "$(dirname "$dest")" || return 1

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        if [ -L "$dest" ]; then
            run rm -f "$dest" || return 1
        else
            run mv "$dest" "$dest.bak" || return 1
            warned "backed up $dest -> $dest.bak"
        fi
    fi

    run ln -s "$src" "$dest" || return 1
    added "$dest -> $src"
}

phase_links() {
    step "Links"

    if is_root; then
        problem "links must run as your normal user, not root -- it writes into \$HOME"
        fail_phase links
        return
    fi

    if [ ! -d "$SHARED_ROOT" ]; then
        problem "common/ not found beside this zone at $SHARED_ROOT"
        fail_phase links
        return
    fi

    local d
    for d in "${ENSURE_DIRS[@]}"; do
        if [ -d "$d" ]; then
            skipped "$d"
        else
            run mkdir -p "$d" && added "mkdir $d"
        fi
    done

    local entry dest src
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        dest="${entry%%|*}"
        src="${entry#*|}"
        link_one "$dest" "$src" || fail_phase links
    done <<EOF
$(printf '%s\n' "${LINKS[@]}")
EOF
}

#---------------------------------------------------------------------------
# Phase: tools
#---------------------------------------------------------------------------

# Latest release asset URL for owner/repo matching a filename pattern.
gh_latest_asset() {
    local repo="$1" pattern="$2"
    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | grep -o "\"browser_download_url\": *\"[^\"]*$pattern[^\"]*\"" \
        | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/'
}

install_nvim() {
    local url tmp
    url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz"
    tmp="$(mktemp -d)" || return 1
    curl -fsSL "$url" -o "$tmp/nvim.tar.gz" || { rm -rf "$tmp"; return 1; }
    tar -xzf "$tmp/nvim.tar.gz" -C "$tmp" || { rm -rf "$tmp"; return 1; }
    rm -rf "$HOME/.local/share/nvim-dist"
    mv "$tmp"/nvim-linux-x86_64 "$HOME/.local/share/nvim-dist" || { rm -rf "$tmp"; return 1; }
    ln -sf "$HOME/.local/share/nvim-dist/bin/nvim" "$HOME/.local/bin/nvim"
    rm -rf "$tmp"
}

install_gh() {
    local url tmp dir
    url="$(gh_latest_asset cli/cli 'linux_amd64.tar.gz')"
    [ -n "$url" ] || return 1
    tmp="$(mktemp -d)" || return 1
    curl -fsSL "$url" -o "$tmp/gh.tar.gz" || { rm -rf "$tmp"; return 1; }
    tar -xzf "$tmp/gh.tar.gz" -C "$tmp" || { rm -rf "$tmp"; return 1; }
    dir="$(find "$tmp" -maxdepth 1 -type d -name 'gh_*' | head -1)"
    [ -n "$dir" ] || { rm -rf "$tmp"; return 1; }
    cp "$dir/bin/gh" "$HOME/.local/bin/gh" || { rm -rf "$tmp"; return 1; }
    chmod +x "$HOME/.local/bin/gh"
    rm -rf "$tmp"
}

install_yazi() {
    local url tmp dir
    url="$(gh_latest_asset sxyazi/yazi 'x86_64-unknown-linux-gnu.zip')"
    [ -n "$url" ] || return 1
    tmp="$(mktemp -d)" || return 1
    curl -fsSL "$url" -o "$tmp/yazi.zip" || { rm -rf "$tmp"; return 1; }
    unzip -q "$tmp/yazi.zip" -d "$tmp" || { rm -rf "$tmp"; return 1; }
    dir="$(find "$tmp" -maxdepth 1 -type d -name 'yazi-*' | head -1)"
    [ -n "$dir" ] || { rm -rf "$tmp"; return 1; }
    cp "$dir/yazi" "$dir/ya" "$HOME/.local/bin/" 2>/dev/null || cp "$dir/yazi" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/yazi"
    rm -rf "$tmp"
}

phase_tools() {
    step "Tools"

    if is_root; then
        problem "tools must run as your normal user, not root -- it writes into \$HOME"
        fail_phase tools
        return
    fi

    mkdir -p "$HOME/.local/bin"

    local t
    for t in "${TOOLS[@]}"; do
        if command -v "$t" >/dev/null 2>&1; then
            skipped "$t present ($(command -v "$t"))"
            continue
        fi
        if [ "$DRY_RUN" -eq 1 ]; then
            printf '   %s? install %s into ~/.local/bin%s\n' "$C_SKIP" "$t" "$C_OFF"
            continue
        fi
        added "installing $t"
        if "install_$t"; then
            added "$t -> $HOME/.local/bin/$t"
        else
            problem "$t install failed"
            fail_phase tools
        fi
    done

    if command -v claude >/dev/null 2>&1; then
        skipped "claude present ($(command -v claude))"
    else
        warned "claude not installed -- curl -fsSL https://claude.ai/install.sh | bash"
    fi
}

#---------------------------------------------------------------------------
# Health check -- always runs
#---------------------------------------------------------------------------

verify() {
    step "Verify"

    local entry dest src
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        dest="${entry%%|*}"
        src="${entry#*|}"
        if [ ! -L "$dest" ]; then
            problem "not a symlink: $dest"
        elif [ "$(readlink "$dest")" != "$src" ]; then
            problem "points elsewhere: $dest -> $(readlink "$dest")"
        elif [ ! -e "$dest" ]; then
            problem "dangling: $dest"
        fi
    done <<EOF
$(printf '%s\n' "${LINKS[@]}")
EOF

    local p missing=0
    for p in "${PACKAGES[@]}"; do
        dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed" || {
            problem "package not installed: $p"
            missing=$((missing + 1))
        }
    done
    [ "$missing" -eq 0 ] && skipped "all ${#PACKAGES[@]} packages installed"

    local c
    for c in "${EXPECTED_COMMANDS[@]}"; do
        command -v "$c" >/dev/null 2>&1 || problem "command not found: $c"
    done

    # A display server on this machine is a build failure, not a preference.
    if command -v Xorg >/dev/null 2>&1 || [ -d /usr/lib/xorg ] || command -v weston >/dev/null 2>&1; then
        problem "a display server is installed -- this machine is supposed to be incapable of running one"
    else
        skipped "no display server present"
    fi

    if [ -e /sys/class/backlight ] && [ -n "$(ls -A /sys/class/backlight 2>/dev/null)" ]; then
        skipped "backlight present: $(ls /sys/class/backlight | tr '\n' ' ')"
    else
        problem "no /sys/class/backlight -- brightness cannot be controlled (firmware-amd-graphics?)"
    fi

    if systemctl is-active systemd-timesyncd >/dev/null 2>&1; then
        skipped "clock sync active"
    else
        problem "systemd-timesyncd not active -- TLS will fail once the clock drifts"
    fi

    if systemctl is-enabled unattended-upgrades >/dev/null 2>&1; then
        skipped "unattended-upgrades enabled"
    else
        problem "unattended-upgrades not enabled -- no patches after the gate"
    fi

    [ -f /etc/polkit-1/rules.d/50-nm-console.rules ] \
        && skipped "NetworkManager polkit rule present" \
        || problem "no NetworkManager polkit rule -- cannot join a new wifi network after the gate"

    [ "$PROBLEM_COUNT" -gt 0 ] && fail_phase verify
    return 0
}

#---------------------------------------------------------------------------
# Main
#---------------------------------------------------------------------------

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

main() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run|-n) DRY_RUN=1 ;;
            --phase)
                shift
                [ $# -gt 0 ] || { echo "--phase needs a value" >&2; exit 2; }
                PHASES="$1"
                ;;
            -h|--help) usage; exit 0 ;;
            *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
        esac
        shift
    done

    if [ "$(uname -s)" != "Linux" ] || [ ! -f /etc/debian_version ]; then
        echo "this is the debian setup; /etc/debian_version is absent. Refusing to run." >&2
        exit 1
    fi

    if [ ! -d "$SHARED_ROOT" ]; then
        echo "common/ not found at $SHARED_ROOT -- this zone needs it beside debian/." >&2
        exit 1
    fi

    printf '%sdebian setup - %s%s\n' "$C_STEP" "$REPO_ROOT" "$C_OFF"
    [ "$DRY_RUN" -eq 1 ] && printf '%s(dry run -- nothing will change)%s\n' "$C_WARN" "$C_OFF"
    is_root && printf '%s(running as root -- packages and system only)%s\n' "$C_WARN" "$C_OFF"

    # Phases are isolated: one failing does not stop the others. When no --phase
    # is given, run the ones this user can actually do, so a plain ./setup.sh is
    # correct both from `su -` and from your own account.
    if [ -n "$PHASES" ]; then
        wants_phase packages && phase_packages
        wants_phase system   && phase_system
        wants_phase links    && phase_links
        wants_phase tools    && phase_tools
    elif is_root; then
        phase_packages
        phase_system
    else
        phase_links
        phase_tools
    fi

    verify

    step "Summary"
    if [ -n "$FAILED_PHASES" ]; then
        printf '   %sproblems in:%s%s\n' "$C_ERR" "$FAILED_PHASES" "$C_OFF"
        printf '   %s%d issue(s) named above%s\n' "$C_ERR" "$PROBLEM_COUNT" "$C_OFF"
        exit 1
    fi
    printf '   %sok%s\n' "$C_ADD" "$C_OFF"
}

main "$@"
