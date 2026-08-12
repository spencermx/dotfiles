#!/usr/bin/env bash
#
# Provisions the console-only Debian ThinkPad from this repo.
#
#   su -c ./setup.sh                  provisions the whole machine
#   ./setup.sh                        links and tools; all a normal user can do
#   ./setup.sh --dry-run              preview, changes nothing
#   ./setup.sh --phase packages,system,links,tools     pick phases by hand
#
# There is no sudo on this machine, by design, so there is no single command
# that can do everything from one account. `su -c ./setup.sh` gets closest:
# it runs the two root phases itself, then hands links and tools back to your
# own account, because as root $HOME is /root and the links would land there.
#
# After the gate there is no root, and plain ./setup.sh is the whole story.
#
# Read debian/notes/build-plan.md before changing anything here. The machine is
# provisioned once behind a one-way gate; after it, packages/system can never
# run again and links/tools must keep working forever.

set -o pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_ROOT="$(dirname "$REPO_ROOT")/common"

# Everything user-local lives here, and the script has to see it however it was
# invoked -- `su - <user> -c` runs a non-interactive shell, which returns out of
# .bashrc before the PATH line. Without this, nvim/gh/claude look missing and
# the tools phase reinstalls what is already there.
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) PATH="$HOME/.local/bin:$PATH" ;;
esac

# Debian keeps usermod, setupcon, ifdown and dhcpcd in /usr/sbin, which is on
# root's PATH only in a *login* shell. Neither `su -c` nor `su` then ./setup.sh
# gives one, so those commands are simply not found -- and `usermod` failing is
# silent enough to look like it worked.
case ":$PATH:" in
    *":/usr/sbin:"*) ;;
    *) PATH="$PATH:/usr/sbin:/sbin" ;;
esac

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
    tmux vim git openssh-client build-essential python3 luarocks curl wget
    ca-certificates gnupg ripgrep fd-find fzf zoxide lsd tree less jq
    man-db manpages manpages-dev unzip zip xz-utils rsync file psmisc
    procps lsof strace htop ncdu bat brightnessctl brightness-udev acpi

    # The only way to install a Python package on this machine. Debian marks
    # the system interpreter EXTERNALLY-MANAGED (PEP 668), so `pip install
    # --user` is refused outright and `python3 -m venv` fails without
    # python3-venv. Without both, no Python dependency can ever be installed
    # here again -- including gdtoolkit, which is the GDScript linter.
    python3-venv pipx

    # Mason's luaformatter is a luarocks package whose rockspec declares
    # `build = { type = "cmake" }`, so `:MasonInstall luaformatter` compiles
    # LuaFormatter from source and fails with no cmake. build-essential does
    # not provide it. The shared formatter config points :Format at lua-format
    # for Lua buffers, so without this there is no Lua formatting on this
    # machine -- and cmake is apt, so it has to be here rather than fixed
    # later.
    cmake

    # Godot dlopens libfontconfig at startup on linuxbsd. Everything this
    # machine actually uses -- --version, --check-only, and the headless
    # editor's LSP -- still works without it, but the binary reports the
    # failure on every single run and get_system_font_path() errors in the
    # editor log. It is the one apt dependency the Godot check turned up, and
    # apt is what disappears at the gate.
    libfontconfig1
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
    "$HOME/.local/bin/tmux-battery|$REPO_ROOT/bin/tmux-battery"

    "$HOME/.vimrc|$SHARED_ROOT/config/.vimrc"
    "$HOME/.config/nvim|$SHARED_ROOT/config/nvim"
    "$HOME/.config/git/ignore|$SHARED_ROOT/config/git/ignore"
    "$HOME/.config/yazi/theme.toml|$REPO_ROOT/config/yazi/theme.toml"

    "$HOME/.claude/CLAUDE.md|$SHARED_ROOT/config/claude/CLAUDE.md"
    "$HOME/.claude/settings.json|$SHARED_ROOT/config/claude/settings.json"
)

ENSURE_DIRS=(
    "$HOME/.config"
    "$HOME/.config/git"
    "$HOME/.config/yazi"
    "$HOME/.local/share"
    "$HOME/.local/bin"
    "$HOME/.claude"
    "$HOME/source/repos"
)

# User-local binaries, as "command|installer function". Everything here lives
# under $HOME so it can be updated with no root for the life of the machine.
TOOLS=(nvim gh yazi claude godot tree-sitter)

# Debian's names, not the upstream ones: fd-find installs fdfind and bat
# installs batcat. The shell config aliases them back; a script cannot see an
# alias, so check for what is actually on disk.
EXPECTED_COMMANDS=(git tmux nvim lsd rg fzf zoxide batcat fdfind brightnessctl claude gh yazi nmcli luarocks
    # tree-sitter is checked here on purpose: without it every :TSInstall
    # fails silently and the editor still looks fine, so nothing else notices.
    godot tree-sitter)

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
    # Do not inherit whatever umask the invoking shell had. These are systemd
    # units and system config; group-writable is wrong even when the group is
    # root, and after the gate nothing can chmod them.
    chmod 644 "$path"
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

    # Report what apt does not have, then install everything else anyway. An
    # earlier version aborted the whole phase here, which meant one bad name
    # left the machine with none of the other thirty-nine packages.
    if [ ${#unavailable[@]} -gt 0 ]; then
        problem "not in the archive: ${unavailable[*]}"
        warned "install a user-local build instead, or fix sources.list -- do not skip and move on"
        fail_phase packages
        local keep=() m
        for m in "${missing[@]}"; do
            local skip=0 u
            for u in "${unavailable[@]}"; do
                [ "$m" = "$u" ] && { skip=1; break; }
            done
            [ "$skip" -eq 0 ] && keep+=("$m")
        done
        missing=("${keep[@]}")
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

# Hand the wifi card from ifupdown to NetworkManager, once. Guarded on the
# device actually being unmanaged, so re-running this script can never tear down
# a working connection -- after the first pass this is a no-op forever.
nm_takeover() {
    local wifi state ssid psk waited

    if ! command -v nmcli >/dev/null 2>&1; then
        problem "nmcli is missing -- network-manager did not install"
        fail_phase system
        return
    fi

    wifi="$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}')"
    if [ -z "$wifi" ]; then
        warned "no wifi device present -- nothing to hand over"
        return
    fi

    # The guard is the ifupdown stanza, not the device state. Disabling
    # networking.service is NOT enough: ifupdown ships a udev rule that runs
    # `ifup` when the interface appears, so an `allow-hotplug` stanza starts
    # its own wpa_supplicant and dhcpcd at every boot, and NM is left holding
    # a device it is nominally managing but cannot use. Commenting the stanza
    # out is what actually ends the handover -- and makes this a no-op after.
    if ! grep -qE "^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+$wifi([[:space:]]|\$)" \
        /etc/network/interfaces 2>/dev/null; then
        state="$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v d="$wifi" '$1==d{print $2}')"
        skipped "$wifi already handed over ($state)"
        return
    fi

    # The installer's credentials live in a root-only file. Copy them into an NM
    # profile BEFORE releasing the card, so the machine is offline for seconds
    # rather than for however long it takes to retype a password.
    ssid="$(sed -n 's/^[[:space:]]*wpa-ssid[[:space:]]\+//p' /etc/network/interfaces 2>/dev/null \
        | head -1 | sed 's/^"//; s/"$//')"
    psk="$(sed -n 's/^[[:space:]]*wpa-psk[[:space:]]\+//p' /etc/network/interfaces 2>/dev/null \
        | head -1 | sed 's/^"//; s/"$//')"
    if [ -z "$ssid" ] || [ -z "$psk" ]; then
        problem "$wifi is unmanaged and /etc/network/interfaces has no wifi to migrate"
        warned "join one by hand instead: nmcli device wifi connect \"<SSID>\" --ask"
        fail_phase system
        return
    fi

    warned "handing $wifi to NetworkManager -- the connection drops for a few seconds"

    # Only add the profile if there is not one already. The guard above is the
    # ifupdown stanza, so this runs again on a machine that was half-migrated,
    # and nmcli will happily create a second profile with the same name.
    if nmcli -t -f NAME connection show 2>/dev/null | grep -qxF "$ssid"; then
        skipped "NM profile '$ssid' already exists"
    else
        run nmcli connection add type wifi con-name "$ssid" ifname "$wifi" ssid "$ssid" \
            wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk" connection.autoconnect yes \
            || { problem "could not create the NM profile -- nothing was torn down"; fail_phase system; return; }
    fi

    # Comment the stanza out rather than delete it: the credentials stay
    # readable as the way back, but ifupdown's udev rule no longer has anything
    # to act on. Disabling the service alone leaves that rule live.
    if [ "$DRY_RUN" -eq 1 ]; then
        printf '   %s? comment out the %s stanza in /etc/network/interfaces%s\n' \
            "$C_SKIP" "$wifi" "$C_OFF"
    else
        cp /etc/network/interfaces /etc/network/interfaces.pre-nm
        awk -v ifn="$wifi" '
            BEGIN { inblk = 0 }
            {
                if ($0 ~ "^[[:space:]]*(auto|allow-hotplug)[[:space:]]+" ifn "([[:space:]]|$)" ||
                    $0 ~ "^[[:space:]]*iface[[:space:]]+" ifn "[[:space:]]") {
                    inblk = 1; print "#" $0; next
                }
                if (inblk) {
                    if ($0 ~ /^[[:space:]]*$/) { inblk = 0; print; next }
                    if ($0 ~ /^[[:space:]]/)   { print "#" $0; next }
                    inblk = 0
                }
                print
            }
        ' /etc/network/interfaces.pre-nm > /etc/network/interfaces \
            && added "commented out the $wifi stanza (backup: /etc/network/interfaces.pre-nm)"
    fi

    run systemctl disable --now networking
    # Whatever ifupdown already started is still holding the card.
    run ifdown "$wifi" 2>/dev/null
    run pkill -f "wpa_supplicant.*-i[[:space:]]*$wifi" 2>/dev/null
    run dhcpcd -k "$wifi" 2>/dev/null
    run systemctl restart NetworkManager

    [ "$DRY_RUN" -eq 1 ] && return

    # The tools phase downloads from the network right after this, so do not
    # return until the link is actually back.
    waited=0
    while [ "$waited" -lt 45 ]; do
        state="$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v d="$wifi" '$1==d{print $2}')"
        [ "$state" = "connected" ] && break
        sleep 2
        waited=$((waited + 2))
    done

    if [ "$state" = "connected" ]; then
        added "$wifi connected to $ssid, NetworkManager driving"
    else
        problem "$wifi did not come back (state: ${state:-unknown})"
        warned "to restore: systemctl stop NetworkManager; systemctl enable --now networking; ifup $wifi"
        fail_phase system
    fi
}

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
    # /sys/class/backlight. netdev: NetworkManager convention. adm: reads the
    # system journal -- without it `journalctl` shows only this user's own
    # messages, so after the gate there would be no way to see why an
    # unattended upgrade, a boot, or the wifi failed. All three need root to
    # grant and are therefore pre-gate only.
    local g
    for g in video netdev adm; do
        if id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
            skipped "$user already in $g"
        else
            run usermod -aG "$g" "$user" && added "$user added to $g"
        fi
    done

    # -- wifi without an administrator --------------------------------------
    # THE pair of settings that decides whether this machine works in a library.
    #
    # plugins: Debian ships plugins=ifupdown,keyfile with [ifupdown]
    # managed=false, so NM stands aside from any interface configured in
    # /etc/network/interfaces -- and a console-only netinst puts the wifi
    # exactly there. Dropping the ifupdown plugin is what lets NM manage the
    # card at all; without it nmcli reports the device as "unmanaged".
    #
    # auth-polkit: NM asks polkit whether an unprivileged caller may change
    # anything. There is no polkit here and there is not going to be -- it ships
    # pkexec, a setuid-root escalation path this machine is built to not have,
    # and --no-install-recommends is the only reason network-manager did not
    # drag it in. With nothing to ask, NM must be told to allow local callers
    # directly. One user, no display server, no sshd: nobody else to ask about.
    if write_file /etc/NetworkManager/conf.d/10-console.conf \
'# Written by debian/setup.sh -- read the NetworkManager section of
# notes/build-plan.md before changing either of these.
[main]
plugins=keyfile
auth-polkit=false' && command -v nmcli >/dev/null 2>&1; then
        run nmcli general reload
    fi

    nm_takeover

    # Superseded by the two settings above. An earlier version of this script
    # wrote a polkit rule here, on a machine with no polkit to read it, and
    # verify() reported the file's existence as a passing check.
    if [ -f /etc/polkit-1/rules.d/50-nm-console.rules ]; then
        run rm -f /etc/polkit-1/rules.d/50-nm-console.rules \
            && added "removed the inert polkit rule -- nothing reads it"
    fi

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

    # -- reboot, poweroff and suspend after the gate ------------------------
    # `systemctl reboot` asks logind, logind asks polkit, and there is no
    # polkit -- so it is denied for the user. After the gate there is no root
    # to su to either. Without a mechanism, unattended-upgrades downloads
    # kernel patches that can never take effect and the whole update story is
    # decorative.
    #
    # The power button was meant to be the answer and could not be made to
    # work on this hardware: a short tap raises no input event at all, and a
    # long hold is the firmware's force-off, which cuts power below the OS.
    #
    # So: a directory the user owns, a path unit watching it, and a service
    # doing the privileged part. This is the only unprivileged trigger for a
    # root action on this machine. It does exactly three things and all three
    # of them are "stop running" -- which the user can already do by holding
    # the button in, just less cleanly.
    #
    # `suspend` is here for the same reason as the other two and not for
    # convenience: logind refuses Suspend() from an unprivileged caller
    # identically, because it is the same polkit check. It is the mildest of
    # the three -- nothing is written, nothing is killed, the session is still
    # there on resume -- so it costs nothing beyond the trigger that already
    # exists. The kernel here offers s2idle only (/sys/power/mem_sleep reads
    # [s2idle]); there is no S3, and `disk` would need a swap area sized for
    # RAM, which this machine does not have.
    write_file /etc/tmpfiles.d/user-power.conf \
"# Written by debian/setup.sh. The trigger directory for
# user-{reboot,poweroff,suspend}.
d /run/user-power 0700 $user $user -"
    run systemd-tmpfiles --create /etc/tmpfiles.d/user-power.conf

    local act
    for act in reboot poweroff suspend; do
        write_file "/etc/systemd/system/user-$act.path" \
"# Written by debian/setup.sh.
[Unit]
Description=Watch for an unprivileged request to $act

[Path]
PathExists=/run/user-power/$act

[Install]
WantedBy=paths.target"

        write_file "/etc/systemd/system/user-$act.service" \
"# Written by debian/setup.sh. Started by user-$act.path, never enabled itself.
[Unit]
Description=$act, requested by the console user

[Service]
Type=oneshot
# Remove the trigger first, so a failed $act cannot leave a file that
# re-fires this unit on every path event forever. This ordering is what makes
# suspend safe as well: the machine comes back from suspend, and a trigger
# still sitting there on resume would put it straight back to sleep.
ExecStart=/bin/rm -f /run/user-power/$act
ExecStart=/usr/bin/systemctl $act"
    done

    run systemctl daemon-reload
    for act in reboot poweroff suspend; do
        if systemctl is-enabled "user-$act.path" >/dev/null 2>&1; then
            skipped "user-$act.path already enabled"
        else
            run systemctl enable --now "user-$act.path" \
                && added "user-$act.path enabled" \
                || fail_phase system
        fi
    done

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

# The native installer, not npm: it drops a self-contained binary that updates
# itself in place, so no Node major-version bump can ever strand the CLI on a
# machine that cannot install one.
install_claude() {
    curl -fsSL https://claude.ai/install.sh | bash
}

# The standard build, not the mono one: this machine edits GDScript and has no
# dotnet SDK. The asset names differ by one underscore -- standard is
# Godot_v4.7.1-stable_linux.x86_64.zip and mono is
# Godot_v4.7.1-stable_mono_linux_x86_64.zip -- so the pattern below has to keep
# "stable_linux" adjacent or it will silently fetch the wrong engine.
#
# Verified headless on this machine at 4.7.1: ldd links only libc, libm,
# libpthread, libdl and librt, so nothing graphical is required to run it.
# Export templates are deliberately not installed -- this box does not export.
# nvim-treesitter's current branch builds parsers with the tree-sitter CLI, not
# with a bare C compiler. build-essential alone is therefore not enough, which
# is easy to miss because the failure is quiet: :TSInstall reports
# "ENOENT (cmd): 'tree-sitter'" and auto_install swallows it. Found on this
# machine with *no* parsers installed at all -- only the seven Neovim ships
# with -- so every language in ensure_installed had been falling back to regex
# syntax since the box was built.
#
# Upstream ships a single gzipped static binary, so this stays user-local and
# updatable after the gate. It must be installed before the lazy.nvim sync
# below, which is what triggers the first parser build; the $TOOLS loop runs
# first, so that ordering already holds.
install_tree-sitter() {
    local url tmp
    url="$(gh_latest_asset tree-sitter/tree-sitter 'tree-sitter-linux-x64.gz')"
    [ -n "$url" ] || return 1
    tmp="$(mktemp -d)" || return 1
    curl -fsSL "$url" -o "$tmp/ts.gz" || { rm -rf "$tmp"; return 1; }
    gunzip -f "$tmp/ts.gz" || { rm -rf "$tmp"; return 1; }
    cp "$tmp/ts" "$HOME/.local/bin/tree-sitter" || { rm -rf "$tmp"; return 1; }
    chmod +x "$HOME/.local/bin/tree-sitter"
    rm -rf "$tmp"
}

install_godot() {
    local url tmp bin
    url="$(gh_latest_asset godotengine/godot 'stable_linux.x86_64.zip')"
    [ -n "$url" ] || return 1
    tmp="$(mktemp -d)" || return 1
    curl -fsSL "$url" -o "$tmp/godot.zip" || { rm -rf "$tmp"; return 1; }
    unzip -q "$tmp/godot.zip" -d "$tmp" || { rm -rf "$tmp"; return 1; }
    # The zip holds a bare versioned executable, not a directory like yazi's.
    bin="$(find "$tmp" -maxdepth 1 -type f -name 'Godot_v*_linux.x86_64' | head -1)"
    [ -n "$bin" ] || { rm -rf "$tmp"; return 1; }
    cp "$bin" "$HOME/.local/bin/godot" || { rm -rf "$tmp"; return 1; }
    chmod +x "$HOME/.local/bin/godot"
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

    # nvm is a shell function, not a binary, so the loop above cannot see it.
    # PROFILE=/dev/null stops its installer appending to ~/.bashrc -- that file
    # is a symlink into this repo and already sources nvm itself.
    #
    # Node never comes from apt on this machine: apt's node puts globals in
    # /usr/lib/node_modules, which npm cannot write to once there is no root.
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        skipped "nvm present ($HOME/.nvm)"
    elif [ "$DRY_RUN" -eq 1 ]; then
        printf '   %s? install nvm into ~/.nvm%s\n' "$C_SKIP" "$C_OFF"
    else
        added "installing nvm"
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh \
            | PROFILE=/dev/null bash >/dev/null 2>&1
        # Judge the outcome, not the exit code: the installer returns non-zero
        # having installed correctly, because its last act is to tell an
        # interactive shell to re-source a profile that PROFILE=/dev/null
        # deliberately made empty.
        if [ -s "$HOME/.nvm/nvm.sh" ]; then
            added "nvm -> $HOME/.nvm"
        else
            problem "nvm install failed"
            fail_phase tools
        fi
    fi

    # nvm by itself provides no node or npm binary. Mason uses npm for bashls,
    # pyright and ts_ls, so leaving this as a manual "then install Node" step
    # makes a fresh Neovim install fail while setup still reports success.
    if [ -s "$HOME/.nvm/nvm.sh" ]; then
        # shellcheck disable=SC1091
        export NVM_DIR="$HOME/.nvm"
        . "$NVM_DIR/nvm.sh"
        if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
            skipped "Node present ($(node --version))"
        elif [ "$DRY_RUN" -eq 1 ]; then
            printf '   %s? install Node LTS through nvm%s\n' "$C_SKIP" "$C_OFF"
        else
            added "installing Node LTS through nvm"
            nvm install --lts \
                || { problem "Node install failed"; fail_phase tools; }
        fi
    fi

    # gdformat and gdlint. Godot's own LSP handles completion and go-to-def,
    # but it provides neither formatting nor linting -- documentFormatting is
    # false in its advertised capabilities -- so this is the only thing that
    # formats GDScript on this machine. Pin the major version to the engine's:
    # gdtoolkit 4.x parses Godot 4 syntax and 3.x does not.
    if command -v gdformat >/dev/null 2>&1; then
        skipped "gdtoolkit present ($(command -v gdformat))"
    elif ! command -v pipx >/dev/null 2>&1; then
        problem "pipx missing -- gdtoolkit cannot be installed"
        warned "pipx is an apt package, so this is only fixable before the gate"
        fail_phase tools
    elif [ "$DRY_RUN" -eq 1 ]; then
        printf '   %s? install gdtoolkit (gdformat, gdlint) with pipx%s\n' "$C_SKIP" "$C_OFF"
    else
        added "installing gdtoolkit"
        if pipx install 'gdtoolkit==4.*' >/dev/null 2>&1; then
            added "gdformat, gdlint -> $HOME/.local/bin"
        else
            problem "gdtoolkit install failed"
            fail_phase tools
        fi
    fi

    # The shared config requires lazy.nvim on its first line. Installing the
    # nvim binary alone therefore leaves a clean Debian build unable to start.
    # Keep this path in sync with common/config/nvim/init.lua.
    local lazy="$HOME/.local/share/nvim/lazy/lazy.nvim"
    if [ -d "$lazy/.git" ]; then
        skipped "lazy.nvim present ($lazy)"
    elif [ "$DRY_RUN" -eq 1 ]; then
        printf '   %s? install lazy.nvim and sync Neovim plugins%s\n' "$C_SKIP" "$C_OFF"
    else
        added "installing lazy.nvim"
        if git clone --filter=blob:none --branch=stable \
            https://github.com/folke/lazy.nvim.git "$lazy"; then
            added "lazy.nvim -> $lazy"
            added "syncing Neovim plugins"
            nvim --headless '+Lazy! sync' +qa \
                || { problem "Neovim plugin sync failed"; fail_phase tools; }
        else
            problem "lazy.nvim install failed"
            fail_phase tools
        fi
    fi
}

#---------------------------------------------------------------------------
# Health check -- always runs
#---------------------------------------------------------------------------

verify() {
    step "Verify"

    # $LINKS was expanded from $HOME, which is /root here. Checking it as root
    # would report all ten as missing and say nothing about the real ones.
    if is_root; then
        skipped "links not checked as root -- they belong to the user's \$HOME"
    else
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
    fi

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

    local nvim_check
    if ! command -v nvim >/dev/null 2>&1; then
        : # Already reported by EXPECTED_COMMANDS.
    else
        nvim_check="$(nvim --headless +qa 2>&1)"
        if [ $? -eq 0 ] && ! printf '%s\n' "$nvim_check" | grep -qE '(^|[^[:alnum:]])E[0-9]+:|Error (detected|in )'; then
            skipped "Neovim configuration loads"
        else
            problem "Neovim configuration does not load -- run nvim to see the error"
        fi
    fi

    # A display server on this machine is a build failure, not a preference.
    if command -v Xorg >/dev/null 2>&1 || [ -d /usr/lib/xorg ] || command -v weston >/dev/null 2>&1; then
        problem "a display server is installed -- this machine is supposed to be incapable of running one"
    else
        skipped "no display server present"
    fi

    # Without adm, journalctl shows only this user's own messages -- and after
    # the gate there is no way to join the group, so every system log is gone
    # for good. Root sees everything regardless, so only check as the user.
    if is_root; then
        skipped "journal access not checked as root"
    elif journalctl -b -n1 --no-pager >/dev/null 2>&1 && \
         ! journalctl -b -n1 --no-pager 2>&1 | grep -q 'not seeing messages'; then
        skipped "system journal readable"
    else
        problem "cannot read the system journal -- $USER is not in adm"
    fi

    if [ -e /sys/class/backlight ] && [ -n "$(ls -A /sys/class/backlight 2>/dev/null)" ]; then
        local backlight brightness_file
        backlight="$(find /sys/class/backlight -mindepth 1 -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | head -1)"
        brightness_file="/sys/class/backlight/$backlight/brightness"
        if is_root; then
            skipped "backlight present: $backlight (write access not checked as root)"
        elif [ -w "$brightness_file" ]; then
            skipped "backlight writable: $backlight"
        else
            problem "backlight exists but $USER cannot change it -- brightness-udev permissions missing"
        fi
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

    # Not "is the config file there" -- that question answered yes for weeks
    # while the real answer was no. Ask the two things that actually decide
    # whether this machine can join a network in a library: does NM own the
    # card, and may this account tell it to do anything.
    if ! command -v nmcli >/dev/null 2>&1; then
        problem "nmcli not installed -- no way to join a wifi network without root"
    else
        local wifi_state
        wifi_state="$(nmcli -t -f DEVICE,TYPE,STATE device status 2>/dev/null \
            | awk -F: '$2=="wifi"{print $3; exit}')"
        case "$wifi_state" in
            "")          problem "nmcli sees no wifi device" ;;
            unmanaged)   problem "wifi is unmanaged by NetworkManager -- cannot join a new network" ;;
            connected)   skipped "wifi connected, NetworkManager driving" ;;
            unavailable) problem "wifi is NM-managed but unavailable -- something else holds the card (ifupdown?)" ;;
            *)           warned "wifi state is '$wifi_state', not connected" ;;
        esac

        if is_root; then
            skipped "nmcli permissions not checked as root -- root is allowed either way"
        elif [ "$(nmcli -t general permissions 2>/dev/null \
            | awk -F: '$1=="org.freedesktop.NetworkManager.settings.modify.system"{print $2}')" = "yes" ]; then
            skipped "nmcli usable without root"
        else
            problem "nmcli cannot modify connections as this user -- the machine is stuck on known networks"
        fi
    fi

    [ "$PROBLEM_COUNT" -gt 0 ] && fail_phase verify
    return 0
}

#---------------------------------------------------------------------------
# Main
#---------------------------------------------------------------------------

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; }

summary() {
    step "Summary"
    if [ -n "$FAILED_PHASES" ]; then
        printf '   %sproblems in:%s%s\n' "$C_ERR" "$FAILED_PHASES" "$C_OFF"
        printf '   %s%d issue(s) named above%s\n' "$C_ERR" "$PROBLEM_COUNT" "$C_OFF"
        exit 1
    fi
    printf '   %sok%s\n' "$C_ADD" "$C_OFF"
    exit 0
}

# Root cannot do links and tools -- $HOME is /root -- so re-run this script as
# the account that owns them. That run does the health check, because it is the
# only one that can see the real $HOME, and its exit status becomes ours.
handoff() {
    local user status flags
    user="$(target_user)"
    if [ -z "$user" ]; then
        problem "no non-root account found -- run ./setup.sh yourself for links and tools"
        fail_phase handoff
        summary
    fi

    step "Links and tools, as $user"
    if [ -n "$FAILED_PHASES" ]; then
        warned "root phases had problems:$FAILED_PHASES"
    fi

    flags="--phase links,tools"
    [ "$DRY_RUN" -eq 1 ] && flags="--dry-run $flags"
    su - "$user" -c "\"$REPO_ROOT/setup.sh\" $flags"
    status=$?

    [ -n "$FAILED_PHASES" ] && exit 1
    exit "$status"
}

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
    is_root && printf '%s(running as root -- then handing links and tools back to your account)%s\n' "$C_WARN" "$C_OFF"

    # Phases are isolated: one failing does not stop the others. With no
    # --phase, do everything this account can reach -- which for root means
    # finishing through handoff(), so one command provisions the machine.
    if [ -n "$PHASES" ]; then
        wants_phase packages && phase_packages
        wants_phase system   && phase_system
        wants_phase links    && phase_links
        wants_phase tools    && phase_tools
    elif is_root; then
        phase_packages
        phase_system
        handoff
    else
        phase_links
        phase_tools
    fi

    verify
    summary
}

main "$@"
