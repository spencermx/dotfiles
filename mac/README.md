# macOS

macOS configuration and setup. One of three sibling OS directories in this
repo, alongside `archlinux/` and `windows/`.

**`mac/` is self-contained.** Everything it needs is under `mac/`, and nothing
here reads a file from a sibling directory. You can clone this repo and run
`mac/setup.sh` without `archlinux/` or `windows/` existing at all.

```
setup.sh    provisions the machine. package lists and config live at the top of it.
config/     dotfiles, linked into place by setup.sh
defaults/   exported macOS settings (the Terminal.app profile)
notes/      per-tool reference
```

## Setup

One script does the whole machine. Clone the repo, then:

```sh
./setup.sh --dry-run    # show what would change, touch nothing
./setup.sh              # do it
```

It refuses to run anywhere `uname` isn't `Darwin`.

**Every run upgrades everything.** Installing what's missing is only half the
job — a machine pinned to whatever was current on provisioning day isn't set
up. The `packages` phase installs anything absent and then brings the rest up
to date.

`$NO_AUTO_UPGRADE` is the exception. Chrome and 1Password are in it: both ship
their own updaters, and letting brew upgrade them too means two mechanisms
fighting over one app bundle. They're still *reported* as behind by the health
check, just not acted on, and don't fail the run.

| phase | |
|-------|--|
| `packages` | installs Homebrew if absent, then every formula and cask in `$FORMULAE` / `$CASKS`, then upgrades what's behind |
| `paths` | creates `$ENSURE_DIRS`; reports the broken `/etc/paths.d` entries `config/.zprofile` supersedes |
| `links` | symlinks all of `config/` into the places macOS expects, and removes links from a previous layout |
| `defaults` | Chrome's app-menu shortcuts; imports the Terminal.app profile |
| `tools` | nvm → node → lazy.nvim → `Lazy! sync` → Mason packages → tmux plugins |

A **health check** runs at the end regardless of which phases you picked. It
verifies the machine rather than trusting that the steps worked: every link is
a real symlink with a live target, every declared package is installed and
current, PATH has no literal `~`, Homebrew is ahead of `/usr/bin`, and every
command in `$EXPECTED_COMMANDS` resolves. Anything wrong is named and the
script exits `1`.

It resolves PATH and commands against a fresh `zsh -l`, not this process, so a
shell started before `.zprofile` landed doesn't produce false failures.

Phases are isolated — one failing doesn't stop the others, and the summary
lists what went wrong. Run one on its own with `--phase`:

```sh
./setup.sh --phase links
./setup.sh --phase packages,tools
```

Links point *into* the repo, so editing a config here takes effect directly
with nothing to re-copy. Anything real that gets replaced is backed up
alongside it as `.bak` first.

### What to edit

Everything configurable is in lists at the top of `setup.sh`: `$FORMULAE`,
`$CASKS`, `$LINKS`, `$ENSURE_DIRS`, `$MASON_PACKAGES`, `$CHROME_SHORTCUTS`.
Adding an app and adding a symlink are the same kind of edit, in the same file.

`$FORMULAE` is curated — what you'd deliberately install on a fresh machine,
not a dump of `brew leaves`. Things installed once and not worth provisioning
(`mingw-w64`, `whisky`, `wine-stable`, and plain `ffmpeg` which `ffmpeg-full`
supersedes) are listed in a comment right below it, so it's clear they were
considered rather than forgotten.

### bash 3.2

`setup.sh` is written for **bash 3.2.57**, which is what macOS ships and has
shipped for years. No `declare -A`, no `mapfile`, no `set -u` around empty
arrays. Pairs are encoded as `"left|right"` strings and split by hand.

Homebrew's bash 5 isn't a way out: a fresh machine runs this script *before*
brew exists.

## PATH

`config/.zprofile` owns PATH. It runs `brew shellenv`, which **prepends** the
brew prefix — and that ordering is the whole point.

This machine used to reach Homebrew through `/etc/paths.d/homebrew`, which
`path_helper` appends *after* `/usr/bin`. macOS ships its own `jq`, `python3`,
`pip3` and `openssl` there, so every brew formula sharing a name with a system
binary was installed and then permanently shadowed — brew's `jq` 1.8.1 lost to
`/usr/bin/jq` 1.7.1-apple on every invocation.

`/etc/paths.d/dotnet-cli-tools` has a second, unrelated bug: it contains the
literal text `~/.dotnet/tools`, and `path_helper` doesn't expand `~`. That
entry has never resolved to anything.

Both files are now redundant. `setup.sh` reports them, and removes them with:

```sh
./setup.sh --fix-paths    # needs sudo
```

They're left alone by default because they're in `/etc`, outside this repo's
zone, and removing them needs a new login shell to take effect.

## Karabiner and AeroSpace

**These two are one keyboard layout split across two programs.** Every
AeroSpace binding uses `ctrl-cmd-alt`, and Karabiner is what turns Right CMD
into that chord. Install one without the other and half the machine is dead.

See [notes/karabiner-aerospace.md](notes/karabiner-aerospace.md) before
changing either file.

## Terminal.app

The "Clear Dark" profile — full ANSI palette plus the Nerd Font — is exported
to `defaults/terminal-clear-dark.plist` and imported by the `defaults` phase.
It previously existed only in `com.apple.Terminal` and nowhere in git.

Terminal rewrites its plist when it quits, so an import done while it's running
gets clobbered — quit and reopen after a first-time import.

Re-export after changing it in the UI:

```sh
/usr/libexec/PlistBuddy -x -c "Print :'Window Settings':'Clear Dark'" \
    ~/Library/Preferences/com.apple.Terminal.plist > defaults/terminal-clear-dark.plist
```

## Zone rule

`setup.sh` writes only inside `mac/` and `$HOME`, and reads only from `mac/`.
Every entry in `$LINKS` targets a file under `config/` — there is no path in
this directory that reaches into a sibling OS directory.

That includes the editor: `config/nvim/` and `config/.vimrc` are **mac's own
copies**, not links to somewhere else. If a change should apply on another OS
too, make it there as well; nothing propagates automatically, and that is the
point.

Configs that differ from their Linux counterparts, for reference:

| file | difference |
|------|-----------|
| `config/.tmux.conf` | `pbcopy` instead of `xclip`, plus Option+`hjkl` resize |
| `config/.gitconfig` | invokes `gh` bare through PATH; the Linux copy hardcodes `/usr/bin/gh`, which is wrong under Homebrew |

## Shell

zsh, in two files with a clean split:

| | |
|-|-|
| `config/.zprofile` | PATH and login-time environment. Read once per login shell. |
| `config/.zshrc` | aliases, functions, completions. Assumes `.zprofile` already ran. |

`.zshrc` sources `.zprofile` itself if `$HOMEBREW_PREFIX` is unset — Terminal
and tmux both start login shells, but some editors' embedded terminals don't,
and without it every alias points at a binary that isn't on PATH yet.

### What the shell defines

| | |
|-|-|
| `e` | run yazi, then follow it to wherever you quit |
| `fe` | open Finder here |
| `ll` / `ls` | `lsd -la` / `lsd -l` |
| `laude` | `clear && claude` |
| `repo` | every git repo below here — status, bulk branch update, or PR review |
| `z` | zoxide |
| ctrl-r / ctrl-t | fzf history and file search |

`zoxide` and `fzf` were both installed as deliberate brew leaves and neither
was ever initialised, so until now neither was reachable through the interface
it exists for.

### repo

One word for everything that touches repos. What you type after it identifies
itself — digits and URLs are pull requests, anything else is a branch name —
so there are no subcommands and nothing to disambiguate.

```
repo             where every repo below here stands. No network.
repo <branch>    checkout <branch> and pull, in every repo that has it
repo <number>    review that PR of the repo you are standing in
repo <url>       review that PR, any repo
repo -l          every review clone and its state
```

Repos are found at depth 1 and 2, so it works from the folder holding your
project folders as well as from inside one. A repo is skipped when it has
tracked changes, is on a detached HEAD, or has no such branch — untracked files
block nothing, because build output and `node_modules` are permanent residents
of half these trees. `repo <tab>` completes branch names across every repo
below here.

Reviews never touch the trees you work in. Each repo clones once to
`~/.prs/<owner>-<repo>` and stays; later reviews fetch and check out there with
`--force --detach`, so nothing ever needs stashing. **Leave nothing in a review
clone** — tracked changes there are discarded on every checkout. Untracked
files survive on purpose, so the second review of a repo skips the rebuild.

`-b <name>` forces the branch reading, for a branch actually named with digits.
It is the only flag here you will never type.

This is a port of the same function in
[`windows/config/Microsoft.PowerShell_profile.ps1`](../windows/config/Microsoft.PowerShell_profile.ps1)
and, like every other config living in two zones, it is a separate copy — a
change there does not arrive here. Two zsh-specific traps are worth knowing if
you edit it: `path` is tied to `PATH`, so a local named `path` breaks command
lookup for the length of the call; and `$var:` is read as a history modifier, so
git refspecs need `${var}` on both sides of the colon.

## Claude Code

`config/claude/` is linked to `~/.claude/`. Before this, the mac had no
`CLAUDE.md` at all and an unmanaged `settings.json` — so the no-AI-attribution
rule the Windows box enforces wasn't enforced here.

`attribution.commit`/`pr` are set to `""`, which is what actually stops the
`Co-Authored-By` trailer being generated. `CLAUDE.md` says so in words too, but
this is the half that doesn't depend on being read.
