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

## The second escalation path: pkexec — closed, because polkit is not installed

polkit ships `pkexec`, which is setuid root. It authorises against
`org.freedesktop.policykit.exec`, which on Debian requires an *administrator*
identity — by default, members of the `sudo` group. Purging the `sudo`
**package** does not empty the `sudo` **group**, so an account left in that
group gets root from `pkexec` for its own password after `sudo` is gone.

**On this machine the path does not exist at all: there is no polkit.**
`network-manager` only *recommends* `polkitd`, and `setup.sh` installs with
`--no-install-recommends`, so it never arrived. `/usr/bin/pkexec` is absent and
`systemctl is-active polkit` reports `inactive`.

That is not an accident to be tidied up — it is now load-bearing, and
`auth-polkit=false` in the NetworkManager config is what lets it stay that way.
See the wifi section below: the obvious way to let an unprivileged user drive
NetworkManager is a polkit rule, and taking that route would install `pkexec`
on this machine to solve a problem that has a solution not requiring it.

Two things to keep true, both verifiable rather than assumed:

- `command -v pkexec` finds nothing, and no package pulls `polkitd` back in.
  If one ever does, the account being in no admin group is the fallback that
  makes it fail closed — that is durable, unlike `chmod u-s /usr/bin/pkexec`,
  which a package update silently restores.
- `id` shows the account in no admin group. It is not in `sudo` today. If it
  ever appears there, `deluser <user> sudo` removes it.

## Purge mechanism — sudo was installed, then removed but not purged

An earlier version of this section claimed `sudo` was never installed. That was
wrong, and apt's own log says so:

```
2026-08-09 14:59:33  apt install sudo
2026-08-09 15:02:17  apt remove sudo
```

`dpkg-query -W -f='${Status}' sudo` therefore reports `deinstall ok
config-files`: the binary is gone, `/etc/sudoers` and friends are not. The
build did take the root-password path at install time, so Debian never put the
user in the `sudo` group — `getent group sudo` is empty and `id` confirms it —
but the package itself did get installed and manually removed.

**Before the gate, run `apt purge sudo`.** `remove` is not `purge`; it leaves
the conffiles behind and leaves the package in a state that is one
`apt install` from working again. Purge clears it.

The rule this replaces is still the one that matters if the machine is ever
rebuilt: `apt purge sudo` is the right removal and `rm /usr/bin/sudo` is not.
`rm` leaves dpkg believing the package is installed, and the next security
update of `sudo` unpacks the binary again and quietly reopens the door.

With that done the gate reduces to locking root, because the user is in no
admin group and — see above — there is no polkit either.

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

Full gate sequence, as this machine is actually built:

```sh
passwd -l root
usermod --expiredate 1 root
```

`sudo` is not installed and the user is in no admin group, so there is nothing
to purge and nothing to remove from a group. Confirm both rather than assume:
`command -v sudo` finds nothing, and `id` shows no `sudo` group.

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
  library is worse than a delayed kernel patch. Reboot manually — **with the
  power button, not `systemctl reboot`**, which is denied for the user here.
  See item 10 below; the power button is the mechanism that makes every
  downloaded patch actually take effect.

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
grub-efi-amd64 efibootmgr
```

**No `cryptsetup`, no `lvm2`, no LUKS.** Full-disk encryption was considered
and declined: the disk holds configuration and git working copies, all of it
pushed elsewhere, and nothing that would matter if the drive were read. The
consequence is recorded rather than hidden — an unencrypted root means anyone
who removes the NVMe and mounts it on another machine can edit `/etc/shadow`
and walk past the locked root account, the GRUB password and the absent `sudo`
in one step. That is a screwdriver and any Linux box, which is a lower bar than
the rest of this document sets. It is the accepted cost of not encrypting; the
partition layout is plain `ext4` root plus plain swap.

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
tmux vim git openssh-client build-essential python3 luarocks curl wget
ca-certificates gnupg ripgrep fd-find fzf zoxide lsd tree less jq
man-db manpages manpages-dev unzip zip xz-utils rsync file psmisc
procps lsof strace htop ncdu bat brightnessctl brightness-udev acpi
```
- **neovim is not in this list on purpose.** It comes from the upstream
  tarball into `~/.local/bin`, for the same reason as `claude` and `gh`: over
  three years, plugins will outrun trixie's frozen nvim, and a frozen editor
  on a machine whose whole job is editing code is the one piece of staleness
  that actually hurts. apt's `vim` stays as the unbreakable fallback — if a
  user-local nvim ever fails to start, there is still an editor.
- `build-essential` is mandatory, not optional: nvim-treesitter compiles
  parsers on first run and links them with a C compiler. Without it the editor
  config half-fails on a machine that can no longer install a compiler.
  **It is necessary and not sufficient**, which is the part this plan
  originally got wrong. nvim-treesitter's current branch drives the build
  through the separate `tree-sitter` CLI, which is not in the archive and is
  not what `build-essential` provides. Measured on the built machine: every
  `:TSInstall` failed with `ENOENT (cmd): 'tree-sitter'`, `auto_install`
  swallowed the error, and the box had **no parsers at all** beyond the seven
  Neovim ships with — so every language in `ensure_installed` had been
  falling back to regex syntax since the build. Fixed user-local, from
  upstream's gzipped static binary, by `install_tree-sitter` in `setup.sh`.
  That it is user-local matters: this one is repairable after the gate.
- `luarocks` is required by Mason's `luaformatter` package. Without it Mason
  cannot install `lua-format`, and the shared Neovim formatter config fails at
  runtime. It comes from apt because Mason invokes the system command while
  building the formatter.
- `man-db manpages manpages-dev` — Claude CLI is the documentation surface
  only while the network is up. In a library with captive-portal wifi, man
  pages are the entire offline manual.
- Debian splits the command and permissions into two packages: `brightnessctl`
  is only the binary, while `brightness-udev` supplies the rule granting the
  `video` group write access to `/sys/class/backlight`. The latter is merely a
  Recommends and is therefore omitted by `--no-install-recommends` unless it is
  named explicitly. Without both, screen brightness needs root — on a
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
`~/.nvm`, then setup installs the current long-term-support Node release through
nvm. New versions install without root forever. Installing nvm without a Node
version is not sufficient: Mason needs `npm` for bashls, pyright, and ts_ls.

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

### 3. Joining a new wifi network after the gate — solved, in two settings

This is the one that decides whether the machine works in a library at all,
and it is easy to miss because the network you provisioned on keeps working.
It was in fact missed: `network-manager` was installed and the machine still
could not join a network as the user, for two independent reasons that both
had to be found before either mattered.

**Installing `nmcli` is not enough.** A console-only netinst has no desktop
task, so the installer writes the wifi SSID and PSK into
`/etc/network/interfaces` (`root:root`, mode 0600) and the machine boots on
`ifupdown` → `wpa_supplicant` → `dhcpcd`. Debian's NetworkManager ships
`plugins=ifupdown,keyfile` with `[ifupdown] managed=false`, which means it
deliberately stands aside from any interface configured in that file. `nmcli
device status` reports the card as `unmanaged` and NM will not touch it. A
desktop install does not hit this, because there the installer leaves
`/etc/network/interfaces` holding nothing but `lo`.

**And being allowed to command it is a separate problem.** NM asks polkit
whether an unprivileged caller may change anything. There is no polkit here
(see the pkexec section) so there is nothing to ask, and
`nmcli general permissions` answers `unknown` to everything.

Both are fixed by one file, written by `setup.sh`:

```ini
# /etc/NetworkManager/conf.d/10-console.conf
[main]
plugins=keyfile
auth-polkit=false
```

`plugins=keyfile` drops the ifupdown plugin, so NM stops treating
`/etc/network/interfaces` as authoritative and will manage the card.
`auth-polkit=false` tells NM to allow local callers directly instead of
consulting a daemon that does not exist. The alternative — install `polkitd`
and write a `.rules` file granting the user
`org.freedesktop.NetworkManager.*` — works too, and was rejected because it
puts setuid-root `pkexec` on the machine to solve a problem that has a
solution not requiring it. One user, no display server, no `sshd`: there is
nobody else on this box for polkit to distinguish between.

Handing the card over is a one-time migration, since the credentials only
exist in the root-only file. `setup.sh`'s `nm_takeover()` copies them into an
NM profile *first*, then `systemctl disable --now networking` and restarts NM,
so the machine is offline for seconds. It is guarded on the device actually
being `unmanaged`, so re-running the script can never tear down a working
connection. **`/etc/network/interfaces` is never modified** — that file is the
way back if NM fails to reconnect.

Verified on 2026-08-10, as the unprivileged user, with no password:

```
nmcli device wifi list                     # four APs listed
nmcli -t general permissions               # settings.modify.system:yes
nmcli connection add type wifi ...         # created, then deleted
```

Creating and deleting a system connection is the exact operation a new network
needs, so the authorisation half is proven. The remaining test is a real
association with a network the machine has never seen — a phone hotspot, at
the gate.

### Associating is not connecting: the captive portal

Joining the network and reaching the internet are different problems, and the
second one is the one a library actually presents. `nmcli` finishes its job at
association; a portal then intercepts everything until a form is submitted.
With no browser, that form has to be found and filled from the console.

**NM's own portal detection was silently off, and this is pre-gate.** NM only
probes if `[connectivity] uri` is set, and Debian's `network-manager` ships no
connectivity conf at all. Unset, NM reports `full` whenever a default route
exists — which is precisely the state behind a portal. Measured before the fix:
`nmcli networking connectivity` answered `full` instantly with nothing logged.
`setup.sh` now writes the `[connectivity]` block into `10-console.conf`, so the
state becomes `portal` and there is something to trust.

**How detection works, and the one detail that breaks it.** Request a URL whose
correct answer is known — `http://connectivitycheck.gstatic.com/generate_204`
returns an empty 204 — and anything else means interception. A 302's `Location`
header *is* the portal URL; a 200 with the wrong body means a transparent proxy
answered in the real server's place.

The probe must be **HTTP, never HTTPS**. A portal cannot intercept TLS without
producing a certificate error, so an HTTPS probe fails or hangs instead of
revealing the redirect. Every probe URL in `debian/bin/portal` is http:// for
this reason and must stay that way.

**Submitting is not a blind POST.** Real portals set a session cookie on the
redirect and carry hidden fields — a CSRF token, the client MAC, the AP MAC, a
session id — and reject anything missing them. So the flow is: fetch the page,
extract the `<form>` and *every* input including hidden ones, then post them
back with the cookie jar intact, changing only the checkbox.

`debian/bin/portal` does exactly that in three steps — `portal`,
`portal inspect <url>`, `portal submit <url> name=value ...` — persisting
cookies to `~/.cache/portal/` so the session survives between commands. It is
standard library only, which is not a style choice: `pip` is refused by
`EXTERNALLY-MANAGED` and there is no root to install a system package with, so
`requests` and BeautifulSoup are permanently unavailable here. `urllib`,
`http.cookiejar` and `html.parser` are the whole toolbox.

Tested on 2026-08-11 against a local server that imitates a real portal —
302-intercepted probe, session cookie, hidden CSRF token, checkbox. Detection
found the URL, inspection listed all six fields, submission was rejected with
403 without the checkbox and accepted with 200 with it, cookie loaded from disk
across separate process invocations.

**The honest limit: a JavaScript-driven portal cannot be done this way.** If the
page builds its request in JS, neither this script nor a text browser can
complete it, and no amount of scripting fixes that. `portal inspect` says so
explicitly when it finds scripts and no form. The fallbacks are a phone
hotspot, or authorising on another device and cloning its MAC with
`nmcli connection modify <con> 802-11-wireless.cloned-mac-address <mac>` —
note `/usr/lib/NetworkManager/conf.d/no-mac-addr-change.conf` is present, so
the MAC is stable by default and a portal that authorises by MAC will remember
this machine between visits.

**A text browser is still the primary tool and is apt-only.** Most library
portals are plain HTML forms, and `w3m` walks them interactively — tab to the
checkbox, Enter — which is far more robust than scripting each one. The script
is for detection, for seeing what a portal actually wants, and for repeatable
re-login. Neither replaces the other, and only one of them can be installed
after the gate.

## Godot — checked on 2026-08-11, and it works better than expected

The premise that it must be settled before the gate was wrong, and the check
has now been run. Godot's official Linux build is a single self-contained
executable: no installer, no package, no root, and it unzips into
`~/.local/bin` on any day, including after the gate.

**Verified at 4.7.1-stable, standard build, on this machine:**

```
ldd Godot_v4.7.1-stable_linux.x86_64
    librt libpthread libdl libm libc + ld-linux        (nothing graphical)
godot --headless --version        -> 4.7.1.stable.official   exit 0
godot --headless --check-only --script good.gd            -> exit 0
godot --headless --check-only --script bad.gd             -> exit 1
    SCRIPT ERROR: Parse Error: Unexpected "Indent" in class body.
              at: GDScript::reload (res://bad.gd:3)
```

Nothing graphical is linked, so the dlopen reasoning held. Syntax checking
reports the file and line, which makes it usable as a real check on a box that
edits GDScript blind.

**One apt dependency turned up, which is exactly why the check exists.** The
binary dlopens `libfontconfig.so.1` and prints
`cannot open shared object file` on every run; the editor additionally errors
in `get_system_font_path` at `platform/linuxbsd/os_linuxbsd.cpp:843`. Nothing
this machine does actually breaks without it, but `libfontconfig1` is in the
archive and the archive is what disappears at the gate, so it is now in
`$PACKAGES`.

### The LSP does run headless — this was the wrong assumption

The natural reading is that Godot's language server is an *editor* feature and
so cannot exist on a machine with no display server. That is false, and it is
the single biggest quality-of-life finding in this build:

```
godot --headless --editor --path <project>
ss -ltn | grep 6005     ->  LISTEN 127.0.0.1:6005     (~3 seconds)
```

A real LSP `initialize` handshake over that socket returns
`completionProvider` (trigger characters `.`, `$`, `'`, `"`),
`definitionProvider`, `declarationProvider`, `hoverProvider`,
`documentSymbolProvider`, `referencesProvider` and `renameProvider`. So this
machine gets completion and go-to-definition for GDScript, not merely syntax
highlighting. `common/config/nvim/lua/plugins/mason-lspconfig.lua` points at
`127.0.0.1:6005`; Mason has nothing to install, because the server is the
engine.

Two costs worth knowing. The headless editor is a background process per
project, on a battery-powered laptop. And it imports the project on first open,
which writes `.godot/` and takes time on a large one.

`documentFormattingProvider` is **false** — the engine will not format. That is
what `gdtoolkit` is for: `gdformat` and `gdlint`, pinned to 4.x to match the
engine, installed with `pipx` because Debian marks the system interpreter
`EXTERNALLY-MANAGED` and refuses `pip install --user`. `pipx` and
`python3-venv` are apt packages, so **GDScript formatting and linting are
pre-gate-only decisions** even though the engine itself is not.

Export templates stay off the machine. `--headless --export-release` needs
them and this box does not export; the desktop does.

The mono build is deliberately not the one installed: this machine edits
GDScript and has no dotnet SDK. The asset names differ by a single underscore,
so `install_godot` keeps `stable_linux` adjacent in its match pattern.

## What else is being forgotten

1. **GRUB password.** See the top. Everything else is detail next to it.
2. **`pkexec` via the `sudo` group.** Second root path, survives the purge —
   closed here only because polkit is not installed. Anything that installs
   `polkitd` reopens it.
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
10. **Reboot without sudo — tested, and it fails. The power button is the
    answer.** The usual mechanism is logind's polkit action for an active local
    session. There is no polkit here, and systemd denies a caller it cannot
    authorise. Measured on 2026-08-10, as the user:

    ```
    $ systemctl reboot
    Failed to execute /usr/bin/pkttyagent: No such file or directory
    Call to Reboot failed: Access denied
    ```

    That is the whole update story failing quietly: `unattended-upgrades`
    downloads kernel patches that can never take effect. Found only because the
    plan said "verify this rather than assume it" and it got verified.

    **The power button was the intended answer and does not work here.**
    `HandlePowerKey=poweroff` is logind's active default, logind logs that it
    is `Watching system buttons on /dev/input/event5` and `event8`, and it
    demonstrably reacts to the lid switch on the same mechanism. But a short
    tap produces no input event at all — measured three times, decoding raw
    `struct input_event` reads — and a long hold is the firmware's force-off,
    which cuts power below the OS and risks the filesystem. Whatever window
    exists between the two, the embedded controller did not produce an ACPI
    event in it. Do not spend another evening on this.

    **What is actually installed:** a directory the user owns, watched by
    root-owned path units.

    ```
    /etc/tmpfiles.d/user-power.conf        d /run/user-power 0700 <user> <user>
    /etc/systemd/system/user-reboot.path   PathExists=/run/user-power/reboot
    /etc/systemd/system/user-reboot.service rm the trigger, then systemctl reboot
    ```

    …and the same pair for `poweroff` and for `suspend`.
    `debian/config/.bashrc` defines `reboot`, `poweroff` and `suspend` as
    functions that `touch` the trigger file. No polkit, no `pkexec`, no root.

    `suspend` rides the same mechanism because it hits the same wall: logind's
    `Suspend()` is a polkit action exactly as `Reboot()` is, so an
    unprivileged `systemctl suspend` is denied for the same reason and with
    the same message. It is the mildest of the three — nothing is written,
    nothing is killed, the session is still there on resume. The trigger is
    removed *before* the action, which is load-bearing for suspend
    specifically: the machine comes back, and a trigger left on disk would be
    seen by the path unit on resume and put it straight back to sleep. The
    kernel here offers s2idle only — `/sys/power/mem_sleep` reads `[s2idle]`,
    so there is no S3 — and `disk` (hibernate) would need a swap area sized
    for RAM, which this machine does not have.

    The cost is real and worth stating plainly: this is the one unprivileged
    trigger for a root action on the machine. It does exactly three things and
    all three are "stop running" — which the user can already do by holding
    the power button, just less cleanly. Against that, the alternative was a
    machine that downloads kernel patches it can never apply. Note that it is
    **root-owned and must exist before the gate**; afterwards it cannot be
    added, changed, or repaired.

## Ordered checklist

Root exists for steps 1–13. It does not exist after step 15.

```
 1  Install trixie, netinst, no desktop at tasksel
      confirm wifi chipset in the installer shell first
 2  Disk: plain ext4 plus swap. Encryption declined, see the package list
 3  Clone dotfiles; `su -c debian/setup.sh` does 4-8 and 11 in one pass
 4    - every package above; verify no X/Wayland was pulled in
 5    - console font (Terminus 16x32); systemd-timesyncd
 6    - NetworkManager takes the wifi card; user added to netdev, video
 7    - unattended-upgrades; tlp
 8    - then it hands links and tools back to your own account
 9  fwupd run once, by hand — after the gate, firmware is frozen forever
10  ssh-keygen; pubkey pasted into GitHub from the desktop
11  User-local, done by setup.sh: claude, nvm, gh, nvim, lazy.nvim and its
      plugins, yazi, godot, tree-sitter, gdtoolkit via pipx
12  Authenticate Claude CLI (paste-code flow); gh auth login --with-token
13  `apt purge sudo` — remove left it in config-files state
14  GRUB superuser password set; update-grub; passphrase written on paper
15  Godot: DONE 2026-08-11, see the Godot section. 4.7.1 runs headless, the
      LSP serves on :6005, and it needs libfontconfig1 from apt
16  REBOOT — then the verification gate below
```

### The gate

Every line must pass, as the unprivileged user, after a real reboot. Any
failure means fix it now, while root still exists.

```
[ ] wifi reconnects unattended at boot — NetworkManager is now solely
      responsible for this; networking.service is disabled
[ ] connect to a NEVER-SEEN network (phone hotspot) as the user:
      nmcli device wifi connect "<SSID>" --ask
[ ] pkexec is still absent; polkit still not installed
[ ] git push to a real repo over SSH
[ ] claude: /logout, then log back in via paste-code. Re-auth REHEARSED
[ ] nvim opens, and `:TSInstall` actually COMPILES a parser. Check
      ~/.local/share/nvim/site/parser/ is non-empty rather than trusting
      the editor to look fine -- auto_install fails silently without the
      tree-sitter CLI, and this machine shipped with zero parsers
[ ] `:MasonInstall luaformatter` succeeds and `:Format` formats a Lua buffer;
      Mason needs the apt-installed `luarocks` command to build it
[ ] godot --headless --version, and the headless editor binds :6005
      (godot --headless --editor --path <proj>; ss -ltn | grep 6005)
[ ] gdformat and gdlint run -- they come from pipx, which is apt-only
[ ] e() launches yazi and follows it on quit; ls/ll resolve (lsd present)
[ ] tmux scrollback works (there is no console scrollback)
[ ] brightnessctl changes brightness without a password
[ ] `reboot` as the user actually reboots — via /run/user-power, not
      systemctl, which is denied here. This is the ONLY way a kernel
      update ever takes effect. Untested before the gate = a machine that
      downloads patches it can never apply
[ ] `poweroff` as the user actually powers off
[ ] unattended-upgrade --dry-run exits clean
[ ] journalctl -b shows SYSTEM messages, not just this user's. Needs the
      adm group, which needs root, so it is pre-gate only -- and without
      it there is no way to ever see why anything failed
[ ] timedatectl reports synchronised
[ ] man git renders
[ ] dotfiles links all live; debian/setup.sh health check exits 0
```

Only then:

```
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

`setup.sh` exists and has survived contact with the machine. It splits
differently from its siblings: `packages` and `system` need root and can only
ever run pre-gate, while `links` and `tools` stay re-runnable forever. Because
no single account can do both, a root run finishes by re-invoking the script as
the user — so `su -c ./setup.sh` provisions the whole machine, and plain
`./setup.sh`, the only form that survives the gate, does the two phases that
need no root.

Two Debian-specific details it has to carry, both of which bit during the
build: `fd-find` and `bat` install as `fdfind` and `batcat`, aliased in the
shell config rather than symlinked into `/usr/local/bin` where they could never
be fixed afterwards; and the health check has to look for the Debian names,
because a script cannot see a shell alias.
