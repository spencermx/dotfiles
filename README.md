# dotfiles

Machine configuration for four operating systems. Each directory provisions
one of them from scratch with a single script.

```
archlinux/  Arch     ./setup.sh
debian/     Debian   ./setup.sh    text-only ThinkPad; see debian/README.md
mac/        macOS    ./setup.sh
windows/    Windows  .\setup.ps1
```

## Getting a machine up

Clone, then run the script for the OS you are on:

```sh
git clone https://github.com/spencermx/dotfiles.git ~/source/repos/dotfiles

cd ~/source/repos/dotfiles/mac    && ./setup.sh --dry-run && ./setup.sh
cd ~/source/repos/dotfiles/archlinux  && ./setup.sh --dry-run && ./setup.sh
cd ~/source/repos/dotfiles/debian     && ./setup.sh --dry-run && ./setup.sh
```

```powershell
cd ~\source\repos\dotfiles\windows; .\setup.ps1 -DryRun; .\setup.ps1
```

Each script refuses to run on the wrong OS, so there is no way to fire the
wrong one by accident.

## The scripts do the same job

They were written at different times against different package managers, but
they share a shape, and reading one teaches you the others:

| | |
|-|-|
| **Declarative lists at the top** | packages, links, directories. Adding an app and adding a symlink are the same kind of edit, in the same file. |
| **Idempotent phases** | re-running changes only what is actually out of date. |
| **Isolated phases** | one failing does not stop the others; the summary names what broke. |
| **`--dry-run` / `-DryRun`** | show every change without making one. |
| **A health check that always runs** | verifies the machine rather than trusting the steps: links are real and live, declared packages are installed and current, expected commands resolve. Exits non-zero and names anything wrong. |
| **Upgrades on every run** | installing what is missing is only half the job. A machine pinned to whatever was current on provisioning day is not set up. |

| | archlinux | debian | mac | windows |
|-|-------|--------|-----|---------|
| packages | pacman | apt | Homebrew | winget |
| shell | bash | bash | zsh | PowerShell |
| phases | `packages` `links` `services` | see below | `packages` `paths` `links` `defaults` `tools` | `Packages` `Env` `Path` `Links` |

`debian/` is the odd one out and breaks two of the rules above deliberately: it
has no display server, and it is provisioned once behind a one-way gate after
which `sudo` is purged, so "re-runnable" applies only to the phases that need
no root. Read [debian/README.md](debian/README.md) before touching it.

## The zones are independent, except for `common/`

**No file in one OS directory is read by another.** Configs that appear in more
than one OS directory are separate copies, and a change to one does not
propagate. The one exception is `common/`, which any zone may read.

The distinction was arrived at the hard way. The editor config — 33 nvim files
plus `.vimrc` — was once shared by pointing one zone at another. That coupling
meant a mac change edited the Linux config, and `mac/setup.sh` could not run
unless `archlinux/` existed.

`common/` fixes the first half and not the second. A path under `common/`
announces that editing it changes every OS, where `mac/config/nvim` quietly
pointing at `archlinux/` did not. But a zone still needs `common/` beside it to
provision a machine.

A file earns a place in `common/` only by being byte-identical everywhere it
appears. When one OS needs it to differ, it moves back into that zone rather
than growing a conditional.

The same applies to `.gitattributes`: `windows/` pins `.ps1` to CRLF, `mac/`
pins `.sh` to LF, and both are scoped to their own directory so they cannot
fight.

## What is not here

Personal documents, identity information, and anything describing how accounts
are protected live in a separate private repo. That includes addresses,
employment history, device identifiers, MFA setup, and a firewall allowlist
that named financial institutions.

Nothing in this repo is sensitive: it is configuration, plus a GitHub noreply
address that appears in every commit anyway. That property is worth keeping —
check before adding a file that came off a machine rather than out of an
editor.

## Per-OS reference

Each directory has its own README covering the parts that do not generalise:

- [archlinux/README.md](archlinux/README.md) — two machines share it (desktop and an
  ASUS laptop), selected by DMI detection
- [debian/README.md](debian/README.md) — a console-only ThinkPad with no X or
  Wayland, and the ordered gate that ends in `sudo` being purged
- [mac/README.md](mac/README.md) — Karabiner and AeroSpace are one keymap split
  across two programs, and the PATH ordering that Homebrew requires
- [windows/README.md](windows/README.md) — why Visual Studio is excluded from
  auto-upgrade, and the two profile locations PowerShell 5.1 and 7 read from
