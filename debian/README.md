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
sessions, used away from the desk. It edits GDScript, commits and pushes.

It *does* run Godot, headlessly: `--headless --check-only --script` for syntax
and `--headless --editor` for the language server, which gives Neovim
completion and go-to-definition with no display server involved. Neovim starts
that editor itself, one per project, on the first `.gd` buffer opened — see
`common/config/nvim/lua/plugins/mason-lspconfig.lua`. What it does not do is render, playtest or export — no window ever
opens, export templates are not installed, and that work happens on the Windows
desktop.

## Zone rule

`setup.sh` writes only inside `$HOME`, and reads from `debian/` and `common/`.
`config/.tmux.conf` is this zone's own copy and *must* differ — there is no
clipboard to integrate with. `nvim` and `.vimrc` come from `common/config/`,
the same files the arch and mac zones use. A change to a `debian/` file reaches
nothing else; a change under `common/` reaches every zone.

`config/.bashrc` is this zone's own copy, but it sources one shared file:
`common/config/shell/repo.bash`, linked to `~/.bashrc.repo`, which is the
`repo` command. See `repo --help`. It is shared with `archlinux/` because
nothing in it is OS-specific; the one thing that is — what to open a reviewed
PR with, `code` there and `nvim` here — is `$REPO_OPEN`, set in `.bashrc`
before the source line. Everything else the two bashrcs have in common is still
deliberately duplicated.
