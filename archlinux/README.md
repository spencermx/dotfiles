# Linux

Arch configuration and setup. One of three sibling OS directories in this repo,
alongside `mac/` and `windows/`.

**`archlinux/` is self-contained.** Everything it needs is under `archlinux/`, and
nothing here reads a file from a sibling directory.

```
setup.sh    provisions the machine. package list and config live at the top of it.
config/     dotfiles and app configs, linked into place by setup.sh
setup/      package list and the GRUB theme
notes/      reference — the manual steps that come before setup.sh
```

## Setup

```sh
./setup.sh --dry-run              # show what would change, touch nothing
./setup.sh                        # do it
./setup.sh --phase links          # one phase
```

It refuses to run anywhere `uname` isn't `Linux`.

| phase | |
|-------|--|
| `packages` | `pacman -S --needed` every package in `$PACKAGES`, plus the right microcode |
| `links` | symlinks `config/` into place |
| `services` | enables the PipeWire user services and Bluetooth, and points `vim` at nvim |

A health check runs at the end regardless of which phases you picked: every
link is a real symlink with a live target, every declared package is installed,
every command in `$EXPECTED_COMMANDS` resolves.

## What replaced the install scripts

There were seven: `install1.sh` through `install5.sh`, plus `_4k`, `_amd` and
`_intel` variants. They are now one `setup.sh`, because:

- **`install3_amd.sh` and `install3_intel.sh` were 110 lines each and differed
  by one word** — `amd-ucode` vs `intel-ucode`. That is now detected from
  `/proc/cpuinfo`, so there is one package list instead of two drifting copies.
- **`install2.sh` and `install2_4k.sh`** were the same link script forked per
  machine. That fork became the `$MACHINE` variable, retired in turn with the
  ASUS laptop it selected — there is one machine and one link table now.
- **`install1.sh` contained no executable code** — 36 lines, all comments. It
  is now `notes/arch-install.md`, which is what it always was.
- **`install5.sh` was three lines**, folded into the `services` phase.

### The bug that forced this

`install2.sh` pointed at:

```sh
BASE_SOURCE="$HOME/source/repos-spencermx/archlinux/config"
```

A `config/` directory that did not exist, in a repo path that did not exist.
The script had been broken for a long time and nothing reported it, because
nothing verified anything. `setup.sh` resolves every path from its own location
and checks the result, so it cannot drift that way again.

`install2.sh` also linked `workspace/`, `ultimate/` and `gitrip.sh` into `$HOME`
and `/usr/sbin`. Those are personal documents and now live in the private
`personal` repo, so they are deliberately gone from the link table.

## config/

| | |
|-|-|
| `.bashrc` `.gitconfig` `.tmux.conf` | shell and tooling |
| `.bashrc` → `~/.bashrc.repo` | sources `common/config/shell/repo.bash`, the `repo` command, shared with `debian/`. `$REPO_OPEN` is set here and is the only per-zone part |
| `.vimrc` `nvim/` | editor — from `common/config/`, shared with every zone |
| `nvim/` | 33 files — the same editor config the mac uses, as its own copy |
| `hypr/` | hyprland. Also has `hyprpaper.conf` |
| `alacritty/` | terminal |
| `waybar/` | the status bar both hyprland configs actually launch |
| `mechabar/` | **vendored third-party** waybar theme, 57 files, ships its own `install.sh`. Don't hand-edit it; update from upstream |
| `i3/` | X11 fallback WM |
| `kdeglobals` `etc/` | Plasma theming, and the nouveau blacklist that lets the nvidia driver load |

There is no `tmux/` directory. It existed and held exactly one thing:
`tmux/resurrect/`, 25 tmux-resurrect session snapshots — machine-generated
state recording which panes were open in which directories, rewritten on every
save. Removing that left the directory empty, and since git does not track
empty directories it would not have survived a clone. The
`~/.local/share/tmux` link that pointed at it is gone too.

tmux plugins are installed by tpm, not from this repo — see `config/.tmux.conf`
and run `prefix + I` after a fresh checkout.

## setup/

`packages` is a full `pacman -Q` snapshot of the machine, kept for reference —
nothing reads it. The list `setup.sh` actually installs is `$PACKAGES` at the
top of the script.

`Xenlism-Arch/` is a vendored GRUB theme. It stays in the repo deliberately:
the moment you need a boot theme is while restoring a broken machine, which is
exactly when you may not have a desktop or a network to fetch it with.
