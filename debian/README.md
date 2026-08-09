# Debian

A ThinkPad L14 running Debian trixie with **no display server**. One of four
sibling OS directories in this repo, alongside `archlinux/`, `mac/` and
`windows/`.

**`debian/` is self-contained.** Nothing here reads a file from a sibling
directory. In particular it is *not* a copy of `archlinux/` — that zone is
Hyprland, waybar, plasma and pipewire, none of which applies to a machine that
cannot run graphical software at all.

```
setup.sh    provisions the machine (written once the box exists)
config/     dotfiles, linked into place by setup.sh
notes/      build-plan.md — read this first
```

## What makes this zone different

Two of the repo-wide rules do not hold here, deliberately.

**Capability is removed, not gated.** X and Wayland never touch the disk, so
graphical software cannot execute regardless of how it later arrives. There is
no browser, no mail, no media. Claude Code CLI is the documentation surface.

**Provisioning is one-way.** After a verification gate, `sudo` is purged and
root is locked. Nothing needing root can be added afterwards — a missing
package means reinstalling from the recovery USB. So `setup.sh` splits into a
`packages` phase that can only run pre-gate, and `links`/`tools` phases that
stay re-runnable forever.

Everything about that gate — the ordered checklist, what the purge actually
buys, and the two escalation paths that survive a naive purge — is in
[notes/build-plan.md](notes/build-plan.md). Read it before changing anything
in this directory.

## Purpose

Portable machine for reading and writing code, git work, and Claude Code
sessions, used away from the desk. It edits GDScript, commits and pushes; it
does not run the Godot editor. Rendering and playtesting happen on the Windows
desktop.

## Zone rule

`setup.sh` writes only inside `debian/` and `$HOME`, and reads only from
`debian/`. `config/nvim`, `config/.vimrc` and `config/.tmux.conf` are this
zone's own copies. A change here does not reach `archlinux/`, and that is the
point — the tmux config in particular *must* differ, since there is no
clipboard to integrate with.
