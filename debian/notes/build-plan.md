# ThinkPad L14 — Debian trixie, console only

Single-purpose portable machine for reading and writing code, git, and Claude
Code CLI. No display server, ever. Provisioned once, then `sudo` is purged and
root is locked. Anything needing root after that means a reinstall.

**The bar.** Undoing a restriction on this machine must cost a physical trip
and separate hardware — the way the Android tablet does, where escalation means
retrieving a cable from the car, connecting to another machine, and running
tooling. Not a password that is known, not a setting that is toggled. Reimaging
from the recovery USB is an expected recovery path, not a failure.

Every decision below is measured against that bar. A control that can be
defeated from the chair, in seconds, without hardware, does not count as a
control no matter how much configuration it involves.

This file is the pre-gate plan. It exists because the gate is one-way and the
whole risk of the build is discovering a missing package after it closes.

## Why Debian and not Arch

There is already an Arch zone and an Arch machine, so this is a fair question
and the answer is not preference. It is unattended security updates.

Arch is rolling. There is no security-only channel — the only update is
`pacman -Syu`, a full system upgrade — and Arch periodically *requires manual
intervention*, announced on the front page and assuming a human is present.
On a machine with no sudo and no root, one bad rolling upgrade, one keyring
transition, or one missed announcement is a reinstall. `archlinux-keyring`
going stale while the machine sits unused is its own version of the same trap.

Debian stable is built for exactly the missing property: fixes that change
behaviour as little as possible, delivered by a mechanism designed to run with
nobody watching. trixie carries security support into roughly 2028, longer with
LTS — the realistic life of this ThinkPad.

The usual argument for Arch, fresher packages, does not apply here, because
everything fast-moving on this box is user-local and updates without root
anyway: Claude CLI, node via nvm, `gh`, Mason's LSP servers, and neovim. apt
supplies only the slow, boring, security-patched base.

If the update requirement were dropped — an appliance frozen until reinstall —
Arch would be fine and `pacstrap base` is a cleaner minimal start than netinst
plus tasksel. That is a coherent design. It is not this one.

## The gap that breaks the model

**`sudo` purged with no bootloader password is not a restriction.** At the GRUB
menu: `e`, append `init=/bin/bash` to the kernel line, ctrl-x. Root shell, no
password, about fifteen seconds, no cable and no second machine. Full-disk
encryption does not close it either — the passphrase is one you know and type
at every boot anyway.

Measured against the stated bar (retrieve a cable from a car glovebox, use
platform-tools on another machine, issue ADB commands), an unprotected GRUB
menu is not in the same category. It is not even in the YubiKey category that
was already rejected.

So the purge is only real with a GRUB superuser password:

```sh
grub-mkpasswd-pbkdf2                 # produces grub.pbkdf2.sha512....
# /etc/grub.d/40_custom:
#   set superusers="rescue"
#   password_pbkdf2 rescue grub.pbkdf2.sha512....
update-grub
```

**Settled: the GRUB password is set.** It is not a hardening extra, it is the
mechanism. The goal is a machine whose restriction costs a physical trip and
separate hardware — retrieve a cable from the car, connect to another machine,
run tooling — the way the Android tablet already works. Without a bootloader
password the equivalent cost is one keystroke at a menu, sitting in the chair.
Every other measure here is downstream of it.

Generate a random passphrase, write it on paper, put the paper in the car with
the ADB cable. That reproduces the tablet's friction exactly and keeps one
non-destructive way back in. Discarding the paper instead is a coherent
stricter choice: it leaves reimaging from the recovery USB as the only path.

`set superusers` locks *editing* menu entries and the GRUB shell while leaving
normal boot unattended — add `--unrestricted` to the default menuentry if a
boot prompt appears.

## The second escalation path: pkexec

NetworkManager pulls in polkit, and polkit ships `pkexec`, which is setuid
root. `pkexec` authorises against `org.freedesktop.policykit.exec`, which on
Debian requires an *administrator* identity — by default, members of the `sudo`
group. Purging the `sudo` **package** does not empty the `sudo` **group**.

If the account stays in that group, `pkexec` grants root for the user's own
password after `sudo` is gone. Whole gate bypassed.

```sh
deluser <user> sudo         # before the gate, and verify with `id`
```

With root locked and the account in no admin group, polkit has no identity to
authenticate as and `pkexec` fails closed. That is durable — unlike
`chmod u-s /usr/bin/pkexec`, which a polkit package update from
unattended-upgrades silently restores.

## Purge mechanism

`apt purge sudo`, not `rm /usr/bin/sudo`.

`rm` leaves dpkg believing the package is installed and correct. The next
security update of `sudo` — delivered by the unattended-upgrades that is
deliberately being left armed — unpacks the binary again and quietly reopens
the door. `apt purge` removes the binary, `/etc/sudoers`, and `/etc/sudoers.d`,
and leaves no package for a future upgrade to restore.

### `passwd -l root` vs `usermod --expiredate 1`

They do different things and the answer is both:

| | what it actually does | what it does not do |
|-|-|-|
| `passwd -l root` | prefixes the password hash with `!`, so no password can ever match. Blocks `su`, console login, password SSH | leaves the account valid. Anything reaching root without a password still works |
| `usermod --expiredate 1 root` | expires the account. `pam_unix`'s **account** stage denies it, which is a separate gate from authentication | same — does not touch anything that bypasses PAM |

`--expiredate` is the stronger of the two because it denies at the account
stage, which also covers auth paths that present no password (an SSH key, had
`openssh-server` been installed). Neither stops `systemd` from starting
root-owned units, and that is exactly the property the build depends on.

Full gate sequence:

```sh
deluser <user> sudo
apt purge sudo
passwd -l root
usermod --expiredate 1 root
```

## unattended-upgrades after the purge — confirmed, with conditions

The mechanism holds. `apt-daily.timer` and `apt-daily-upgrade.timer` are
system units started by PID 1 as root. They do not consult `sudo`, and a locked
or expired root account is irrelevant to them — systemd does not authenticate,
it forks. Purging `sudo` removes interactive escalation only.

Four things must be set **before** the gate or it degrades to nothing:

```
# /etc/apt/apt.conf.d/50unattended-upgrades
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Automatic-Reboot "false";
Dpkg::Options { "--force-confdef"; "--force-confold"; };
Unattended-Upgrade::Origins-Pattern {
  "origin=Debian,codename=${distro_codename},label=Debian-Security";
  "origin=Debian,codename=${distro_codename}-security,label=Debian-Security";
  "origin=Debian,codename=${distro_codename}-updates";
};
```

- **Kernel autoremove.** Without it `/boot` fills, apt starts failing on every
  run, and there is no way to clean it. This is the single most likely way the
  machine dies quietly six months in.
- **conffile policy.** A dpkg conffile prompt with no one to answer it stalls
  the upgrade forever. `confold` keeps the local file and moves on.
- **`-updates` as well as security.** Point releases carry `ca-certificates`
  and `tzdata`, and stale versions of either eventually break TLS.
- **No automatic reboot.** A machine that reboots itself mid-sentence in a
  library is worse than a delayed kernel patch. Reboot manually — `systemctl
  reboot` still works without `sudo`, because logind's polkit action allows an
  active local session. Verify this at the gate rather than assuming it.

Enable and prove it:

```sh
dpkg-reconfigure -plow unattended-upgrades      # writes 20auto-upgrades
unattended-upgrade --dry-run --debug            # must list origins, not error
systemctl list-timers apt-daily\*
```

## Which image

`debian-13.x.0-amd64-netinst.iso`, current point release, from debian.org.
Verify SHA256SUMS and its GPG signature before writing.

- **trixie is Debian 13, current stable.** Not testing, not sid — stable is
  what carries the security-only update stream that unattended-upgrades needs.
- **Not a live image.** Live ISOs boot a desktop and install it with Calamares.
  netinst runs the classic installer, which is where tasksel can be left with
  nothing but "standard system utilities" selected.
- **Ignore "unofficial non-free-firmware" images.** That was Debian 11 and
  earlier, and still dominates search results. Since 12 the firmware is in the
  official image.

netinst pulls packages over the network during the install, so the network
must work *in the installer*. The L14's RJ45 is the fallback if wifi firmware
does not bring the card up — have a cable ready. That is also the moment to
run `lspci -nn | grep -i net` from the installer shell and record the chipset.

## Package list

Nothing here pulls X or Wayland. Check with
`apt-get -s install <list> | grep -iE 'xorg|wayland|libx11|libgtk'` before
committing — the point is not tidiness, it is that graphical software cannot
execute regardless of how it later arrives.

### Base, firmware, boot
Confirmed on the actual machine (`lspci`, `/proc/cpuinfo`): AMD Ryzen 5 PRO
7530U, MediaTek MT7922 wifi, Realtek gigabit ethernet.

```
linux-image-amd64 firmware-linux firmware-mediatek firmware-realtek
firmware-amd-graphics firmware-misc-nonfree amd64-microcode
grub-efi-amd64 efibootmgr cryptsetup lvm2
```

- **`firmware-mediatek`** drives the MT7922 through `mt7921e`, in-kernel since
  5.15 and trixie ships 6.12. It is in `non-free-firmware`, which the official
  trixie installer includes by default.
- **`firmware-amd-graphics` is not optional, despite there being no display
  server.** On AMD laptops the backlight is exposed as
  `/sys/class/backlight/amdgpu_bl0` by the `amdgpu` *kernel* driver, which
  will not initialise without its firmware. Missing it means no backlight
  device, nothing for `brightnessctl` to write to, and screen brightness
  frozen wherever the firmware left it — on a battery machine used in varying
  light, for the life of the machine.
- **`amd64-microcode`**, not `intel-microcode`. Ryzen 5 PRO 7530U is Zen 3.
- Realtek ethernet runs on in-kernel `r8169` and needs no blob. It is the
  fallback if wifi ever fails to come up, including during the install.

`ls /sys/class/net` showing only `lo` at the installer's first screen is
expected — network drivers are not loaded until the "detect network hardware"
step.

### System services
```
unattended-upgrades systemd-timesyncd network-manager tlp fwupd
```
`systemd-timesyncd` is not optional. If the RTC battery goes flat or the
machine sits unused, the clock drifts, TLS certificate validation fails, and
then git, apt and Claude CLI all stop at once with errors that do not mention
the clock. Fixing the clock post-gate needs root.

`fwupd` is worth one run before the gate; after it, EC and UEFI firmware are
frozen forever. CPU microcode still arrives, because that ships as an apt
package.

### Console, locale, input
```
console-setup kbd locales keyboard-configuration
```
Set a large console font in `/etc/default/console-setup` —
`FONTFACE="Terminus" FONTSIZE="16x32"`. At 1080p on a 14" panel the default
8x16 is punishing for a full day, and this file needs root to change.

The kernel dropped console scrollback in 5.9, so **tmux is the only way to
scroll**. It is not a convenience here.

### Toolchain
```
tmux vim git openssh-client build-essential python3 curl wget
ca-certificates gnupg ripgrep fd-find fzf zoxide lsd tree less jq
man-db manpages manpages-dev unzip zip xz-utils rsync file psmisc
procps lsof strace htop ncdu bat brightnessctl acpi
```
- **neovim is not in this list on purpose.** It comes from the upstream
  tarball into `~/.local/bin`, for the same reason as `claude` and `gh`: over
  three years, plugins will outrun trixie's frozen nvim, and a frozen editor
  on a machine whose whole job is editing code is the one piece of staleness
  that actually hurts. apt's `vim` stays as the unbreakable fallback — if a
  user-local nvim ever fails to start, there is still an editor.
- `build-essential` is mandatory, not optional: nvim-treesitter compiles
  parsers with a C compiler on first run. Without it the editor config
  half-fails on a machine that can no longer install a compiler.
- `man-db manpages manpages-dev` — Claude CLI is the documentation surface
  only while the network is up. In a library with captive-portal wifi, man
  pages are the entire offline manual.
- `brightnessctl` ships a udev rule granting the `video` group write access to
  `/sys/class/backlight`. Without it, screen brightness needs root — on a
  battery-powered machine used in varying light, that matters daily.
- Debian renames two binaries: `fd-find` installs `fdfind`, `bat` installs
  `batcat`. Handled in the dotfiles shell config, not by a root-owned symlink
  in `/usr/local/bin`, so it stays fixable after the gate.

Confirm `lsd` and `fzf` actually exist in trixie before relying on them — the
shell config aliases `ls`/`ll` straight to `lsd`, so if it is missing the
prompt is broken on a machine that can no longer install it. Either is
substitutable with a user-local binary if apt does not have it.

### Deliberately absent
No `xclip`/`wl-clipboard` (no display server to hold a selection), no audio
stack, no fonts beyond console, no `openssh-server` (no remote rescue, which
is consistent with the model), no `nodejs` from apt — see below.

## The three pre-gate problems

### 1. Claude CLI auth without a browser

The login flow prints a URL and waits for a code pasted back. Open the URL on
the Windows desktop, paste the code into the console. No local browser is
touched. Set `BROWSER=` in the environment so nothing tries to spawn one.

The re-auth path is the part that matters, and it is safe: credentials live
under `~/.claude/`, owned by the user. Token refresh and full re-login are both
user-level operations. Nothing in that flow needs root, so it survives the
purge.

**Rehearse it at the gate, do not merely verify it.** Log out (`/logout`), then
log back in through the paste-code flow, while root still exists to fix a
surprise. "It is currently authenticated" proves nothing about the day the
token expires.

Keep an API key in the password store as break-glass: `ANTHROPIC_API_KEY` is a
second, independent auth path that needs no interactive flow at all.

### 2. Node and the CLI, updatable without root

Install Claude Code with the native installer, not npm:

```sh
curl -fsSL https://claude.ai/install.sh | bash     # → ~/.local/bin/claude
```

This drops a self-contained binary in `$HOME` that self-updates in place, with
no Node dependency at all. Decoupling the CLI from the Node runtime removes an
entire class of post-gate failure — a Node major-version bump can never strand
the CLI.

Node is still wanted for TypeScript work, so install it with `nvm` under
`~/.nvm`. New versions install without root forever.

Never `apt install nodejs` on this machine. An apt-installed Node puts globals
in `/usr/lib/node_modules`, which npm cannot write to once `sudo` is gone.

Same rule for `gh`, which the dotfiles `repo` function depends on: take the
release tarball into `~/.local/bin` rather than the apt package, so it can be
updated after the gate. Authenticate with `gh auth login --with-token` from a
PAT generated on the desktop; the browser flow is not needed.

`yazi` goes the same way, and additionally because it may not be packaged in
trixie at all — it is recent enough that the freeze may have missed it, and
"apt says no" is not a thing that can be worked around after the gate. It is a
TUI, so the absence of a display server is irrelevant to it. Take the upstream
release binary into `~/.local/bin`; the shell's `e()` wrapper depends on it.

**General rule: anything that might need updating post-gate goes user-local.**
apt-installed software gets security patches and nothing else, forever.

To summarise what does *not* come from apt: `claude`, `node` (nvm), `gh`,
`nvim`, `yazi`, and Mason's LSP servers. All in `$HOME`, all updatable with no
root, forever.

### 3. Joining a new wifi network after the gate

This is the one that decides whether the machine works in a library at all,
and it is easy to miss because the network you provisioned on keeps working.

NetworkManager's `org.freedesktop.NetworkManager.settings.modify.system`
defaults to requiring administrator authentication. With `sudo` purged and root
locked there is no administrator, so `nmcli device wifi connect` on a new
network fails and **the machine is bricked for its stated purpose**.

Write an explicit rule before the gate rather than relying on Debian's
`netdev` defaults:

```javascript
// /etc/polkit-1/rules.d/50-nm-console.rules
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0 &&
        subject.user === "<user>") {
        return polkit.Result.YES;
    }
});
```

trixie's polkit no longer reads the old `.pkla` files, so it must be a `.rules`
file. Verify with `pkcheck --action-id
org.freedesktop.NetworkManager.settings.modify.system --process $$`, and then
verify for real: at the gate, connect to a phone hotspot the machine has never
seen, as the unprivileged user, with `sudo` already gone from the picture.

## Godot — the decision is not one-way

The premise that it must be settled before the gate is wrong, and worth
correcting because it removes a forced choice.

Godot's official Linux build is a single self-contained executable. There is no
installer, no package, and no root: it unzips into `~/.local/bin` on any day,
including after the gate. Godot 4 loads its display drivers dynamically, which
is exactly why `--headless` works in minimal CI containers with no X libraries
present — the same reason it will run here.

What *is* one-way is the dependency question. So: **unzip it and run
`godot --headless --version` before the gate.** If it runs, delete it or keep
it as you like — either way you have proven it can be added later. If it turns
out to want a library from apt, that is precisely the finding you need while
root still exists.

Export templates stay off the machine. `--headless --export-release` needs
them and this box does not export; the desktop does.

Useful without templates: `godot --headless --check-only --script foo.gd`
parses a script and reports syntax errors, which is real value on a box whose
whole job is editing GDScript blind.

## What else is being forgotten

1. **GRUB password.** See the top. Everything else is detail next to it.
2. **`pkexec` via the `sudo` group.** Second root path, survives the purge.
3. **Kernel autoremove**, or `/boot` fills and updates stop silently.
4. **Clock sync**, or TLS fails everywhere at once with a misleading error.
5. **Backlight via `video` group**, or brightness is frozen at boot value.
6. **Console font**, or the display is unusable for a full day at 1080p/14".
7. **A broken dpkg state is unrecoverable.** If an unattended upgrade is
   interrupted mid-transaction, `dpkg --configure -a` needs root. There is no
   mitigation short of the recovery USB. Accepted cost, but know it.
8. **Nothing outside git survives.** No backup path exists on this machine.
   Anything not committed and pushed is one reinstall from gone.
9. **USB storage — settled: omitted.** Mounting removable media as a
   non-root user would need `udisks2` plus a polkit rule, pre-gate. It is not
   installed, on purpose: mountable removable storage is a route for software
   and media to arrive on a machine designed so they cannot. Consequence,
   accepted: after the gate this machine reads nothing from USB, and
   everything arrives over the network through git.
10. **Reboot/poweroff without sudo** works through logind's polkit action for
    an active local session — but verify it at the gate, because everything
    else about the purge depends on being able to reboot for kernel patches.

## Ordered checklist

Root exists for steps 1–13. It does not exist after step 15.

```
 1  Install trixie, netinst, no desktop at tasksel
      confirm wifi chipset in the installer shell first
 2  Disk: LUKS full-disk encryption, passphrase decided now
 3  apt install every package above; verify no X/Wayland was pulled in
 4  Locale, keyboard, console font (Terminus 16x32)
 5  systemd-timesyncd enabled; `timedatectl` shows synchronised
 6  NetworkManager + the polkit .rules file; user added to netdev, video
 7  unattended-upgrades configured per above; --dry-run clean
 8  tlp enabled; fwupd run once
 9  GRUB superuser password set; update-grub; passphrase written on paper
10  ssh-keygen; pubkey pasted into GitHub from the desktop
11  User-local binaries into ~/.local/bin: claude (native installer),
      nvm + node, gh, nvim, yazi
12  Authenticate Claude CLI (paste-code flow); gh auth login --with-token
13  Clone repos; run debian/setup.sh --dry-run then for real
14  Godot binary: unzip, `--headless --version`, record the result
15  REBOOT — then the verification gate below
```

### The gate

Every line must pass, as the unprivileged user, after a real reboot. Any
failure means fix it now, while root still exists.

```
[ ] wifi reconnects unattended at boot
[ ] connect to a NEVER-SEEN network (phone hotspot) as the user
[ ] git push to a real repo over SSH
[ ] claude: /logout, then log back in via paste-code. Re-auth REHEARSED
[ ] nvim opens, treesitter parsers compile, no missing-compiler error
[ ] e() launches yazi and follows it on quit; ls/ll resolve (lsd present)
[ ] tmux scrollback works (there is no console scrollback)
[ ] brightnessctl changes brightness without a password
[ ] systemctl reboot works without a password
[ ] unattended-upgrade --dry-run exits clean
[ ] timedatectl reports synchronised
[ ] man git renders
[ ] godot --headless --version, if keeping it
[ ] dotfiles links all live; debian/setup.sh health check exits 0
```

Only then:

```
deluser <user> sudo
apt purge sudo
passwd -l root
usermod --expiredate 1 root
reboot        # and confirm the checklist still passes
```

## Dotfiles integration

`debian/` is a fresh zone, not a copy of `archlinux/`. That zone is Hyprland,
waybar, plasma, firefox and pipewire — nothing in it applies to a machine with
no display server. `.vimrc` and `config/nvim` come from `common/config/` —
link them through `$SHARED_ROOT`, do not copy. `.tmux.conf` and `.gitconfig`
are **new copies** inside this zone, per the repo's zone rule.

Three known conflicts to resolve while writing them:

| | |
|-|-|
| `.tmux.conf` | the archlinux copy pipes to `xclip`. There is no selection to pipe to and no host terminal to accept OSC 52 — a physical TTY swallows it. tmux's own buffers are the whole clipboard here |
| `repo` | exists in zsh (`mac/`) and PowerShell (`windows/`) only; `archlinux/config/.bashrc` has aliases and no `repo`. It needs a bash port, and it depends on `gh` |
| `fdfind` / `batcat` | Debian's renamed binaries. Alias in the shell config, not via a root-owned symlink in `/usr/local/bin` — that would be unfixable after the gate |

`setup.sh` for this zone gets written once the machine is up and the package
list has survived contact. It splits differently from its siblings: a
root-requiring `packages` phase that can only ever run pre-gate, and
`links`/`tools` phases that stay re-runnable forever.
