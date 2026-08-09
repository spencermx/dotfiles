# Windows

Windows configuration and setup. One of three sibling OS directories in this
repo, alongside `archlinux/` and `mac/`.

**`windows/` is self-contained.** Everything it needs is under `windows/`, and
nothing here reads a file from a sibling directory.

```
setup.ps1   provisions the machine. app list and config live at the top of it.
config/     dotfiles, linked into place by setup.ps1
notes/      reference
setup/      per-tool install notes and the raw winget snapshot
```

## Setup

One script does the whole machine. Clone the repo, then:

```powershell
.\setup.ps1 -DryRun    # show what would change, touch nothing
.\setup.ps1            # do it
```

**Every run upgrades everything.** Installing what's missing is only half the
job — a machine pinned to whatever was current on provisioning day isn't set
up. The Packages phase installs anything absent and then brings the rest up to
date.

`$NoAutoUpgrade` is the exception. Visual Studio is in it — a VS update is
measured in gigabytes and shouldn't happen as a side effect of fixing a
symlink. It's still *reported* as behind by the health check, just not acted
on, and doesn't fail the run. Upgrade it when you mean to:

```powershell
winget upgrade --id Microsoft.VisualStudio.Community --exact
```

`-DryRun` lists exactly what would be upgraded first, and
`-Phase Links,Path,Env` skips packages entirely when you only want the config
side.

### Which Visual Studio

`Microsoft.VisualStudio.Community` is **Community 2026** (18.x) — the
unversioned id tracks the current major. Year-pinned ids exist separately
(`Microsoft.VisualStudio.2022.Community` is 17.x,
`Microsoft.VisualStudio.2019.Community` is 16.x) and are not declared here.

That unversioned id is the second reason VS is excluded from auto-upgrade: if
Microsoft repoints it at a future major, an unattended upgrade would jump major
versions. Nothing hardcodes a version path any more — `setup.ps1` and `vsdev`
both locate VS with `vswhere` — but a silent major upgrade is still worth not
doing unattended.

`Microsoft.VisualStudioCode` is a different product entirely — the lightweight
editor, not the IDE.

Every phase is idempotent — it only changes what's actually out of date, so
re-run it whenever the repo moves on. Run it from an **elevated** PowerShell:
the link phase needs admin (or Developer Mode) to create symlinks, and falls
back to copying without it.

| phase | |
|-------|--|
| `Packages` | `winget install` every app in the `$Packages` list that isn't already present |
| `Env` | user environment variables — `_NT_SYMBOL_PATH`, `sqlpath` |
| `Path` | adds drift's `build\`, Git's `usr\bin`, the VS Installer, NETFX tools — and prunes entries pointing at nothing |
| `Links` | symlinks the whole of `config/` into the places Windows expects |

A **health check** runs at the end regardless of which phases you picked. It
verifies the machine rather than trusting that the steps worked: every link is
a real symlink with a live target, every variable is set, PATH has no dead
entries, and every command in `$ExpectedCommands` resolves. Anything wrong is
named and the script exits `1`.

It resolves commands against the *registry* PATH, not the current process's, so
a shell started before PATH changed doesn't produce false failures.

Phases are isolated — one failing doesn't stop the others, and the summary
lists what went wrong.

Run one phase on its own with `-Phase`:

```powershell
.\setup.ps1 -Phase Links,Path
```

Links point *into* the repo, so editing a config here takes effect directly
with nothing to re-copy. Anything real that gets replaced is backed up
alongside it as `.bak` first.

Existing PATH entries pointing at nothing get pruned — a dead entry slows every
command lookup and hides typos.

There is no tolerate-list. If a directory belongs on PATH, `$EnsureDirs`
creates it, and directory creation runs *before* the prune so the entry is real
by the time PATH is checked. `~\.dotnet\tools` is the case that drove this: it
doesn't exist until your first `dotnet tool install -g`, so it gets made rather
than excused. `$DotnetTools` declares global tools to install, the same way
`$Packages` declares winget apps.

### What to edit

Everything configurable is in four lists at the top of `setup.ps1`:
`$Packages`, `$EnvVars`, `$PathEntries`, `$Links`. Adding an app and adding a
PATH entry are the same kind of edit, in the same file.

`$Packages` is curated — what you'd deliberately install on a fresh machine.
Runtimes and redistributables (VCRedist, VCLibs, WindowsAppRuntime, UI.Xaml)
are intentionally absent; they arrive as dependencies.

`setup\winget-export.json` is the raw `winget export` snapshot of the machine,
kept for reference only — nothing reads it. Refresh it with:

```powershell
winget export -o setup\winget-export.json --include-versions
```

## Shell

PowerShell only. The cmd (`profile.bat`, `cdx.bat`, `e.bat`, `vs2026.cmd`) and
Git Bash (`.bashrc`) profiles were deleted when this machine moved to
PowerShell 7 — there is one profile now, not three implementations of the same
three functions.

`config/Microsoft.PowerShell_profile.ps1` is linked into **both** profile
folders, because 5.1 and 7 read from different places:

| | |
|-|-|
| PowerShell 5.1 | `<Documents>\WindowsPowerShell\` |
| PowerShell 7 | `<Documents>\PowerShell\` |

Windows ships 5.1 and never updates it; 7 installs alongside as `pwsh` and is
in `$Packages`. Linking one file into both means either shell behaves the same.
`<Documents>` is resolved via `GetFolderPath`, so OneDrive folder redirection
works.

### What the profile defines

| | |
|-|-|
| `e` | run [drift](https://github.com/spencermx/drift2), then follow it to wherever you quit |
| `ll` | `Get-ChildItem -Force` |
| `fe` | open Explorer here |
| `vsdev` | load the VS build environment into this session — only needed for `cl`, `link`, `nmake` |

`e` works by handoff: a child process can't change its parent's directory, so
drift writes its exit directory to `%TEMP%\browser_lastdir.txt` and the function
does the `Set-Location` itself.

`vsdev` calls the `Launch-VsDevShell.ps1` that ships with Visual Studio, found
via `vswhere` — nothing hardcodes a version path. You rarely need it:
`devenv` and `msbuild` are on PATH permanently, so `devenv foo.sln` and
`msbuild foo.sln` work in any shell with no setup.

## drift

[drift](https://github.com/spencermx/drift2) is on PATH at the directory it
builds into — `../../drift2/build`, resolved relative to this repo so moving
the tree keeps working. Nothing is copied and there is no install step: one
binary, where it was produced, so there is never a question of which one you
are running.

This replaced a `commands/` directory here plus a `WINDOWS_BIN` variable that
drift2's `build.bat` copied into. That left two identical `drift.exe` files and
made PATH order decide which one ran.

Clone drift2 as a sibling of this repo and build it. If it isn't there the PATH
entry fails the on-disk check and is skipped, like any other absent tool —
though `drift` is in `$ExpectedCommands`, so the health check will say so.

## Line endings

`.gitattributes` pins `.ps1` to CRLF. `config/.gitconfig` sets
`autocrlf = false` to match. The `.bat`/`.cmd` rules went with the scripts they
protected.
