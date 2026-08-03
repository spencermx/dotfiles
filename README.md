# dotfiles

Machine configuration for three operating systems. Each directory provisions
one of them from scratch with a single script.

```
linux/      Arch     ./setup.sh
mac/        macOS    ./setup.sh
windows/    Windows  .\setup.ps1
```

## Getting a machine up

Clone, then run the script for the OS you are on:

```sh
git clone https://github.com/spencermx/dotfiles.git ~/source/repos/dotfiles

cd ~/source/repos/dotfiles/mac    && ./setup.sh --dry-run && ./setup.sh
cd ~/source/repos/dotfiles/linux  && ./setup.sh --dry-run && ./setup.sh
```

```powershell
cd ~\source\repos\dotfiles\windows; .\setup.ps1 -DryRun; .\setup.ps1
```

Each script refuses to run on the wrong OS, so there is no way to fire the
wrong one by accident.

## The three scripts do the same job

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

| | linux | mac | windows |
|-|-------|-----|---------|
| packages | pacman | Homebrew | winget |
| shell | bash | zsh | PowerShell |
| phases | `packages` `links` `services` | `packages` `paths` `links` `defaults` `tools` | `Packages` `Env` `Path` `Links` |

## The zones are independent

**No file in one OS directory is read by another.** Configs that appear in more
than one place are separate copies, and a change to one does not propagate.

This is deliberate and was arrived at the hard way. The editor config in
`linux/config/nvim` and `mac/config/nvim` is the same 33 files, and it was
briefly shared by pointing one at the other. That coupling meant a mac change
edited the Linux config, and `mac/setup.sh` could not run unless `linux/`
existed. Two copies and an occasional manual sync is the cheaper problem.

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

- [linux/README.md](linux/README.md) — two machines share it (desktop and an
  ASUS laptop), selected by DMI detection
- [mac/README.md](mac/README.md) — Karabiner and AeroSpace are one keymap split
  across two programs, and the PATH ordering that Homebrew requires
- [windows/README.md](windows/README.md) — why Visual Studio is excluded from
  auto-upgrade, and the two profile locations PowerShell 5.1 and 7 read from
