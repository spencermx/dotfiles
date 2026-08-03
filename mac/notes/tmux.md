# tmux on macOS

`config/.tmux.conf` is mac's own copy. Two deliberate differences from the
Linux config it started as:

| | mac | linux |
|-|-----|-------|
| copy-mode yank | `pbcopy` | `xclip -in -selection clipboard` |
| Option + `hjkl` | resizes panes | not bound |

The Option bindings exist because macOS Terminal sends `M-` sequences reliably,
and they run through the same `is_vim` check as the ctrl bindings, so Neovim
still receives the keys when it's focused.

Before this repo had a mac zone, `~/.tmux.conf` was a **real file, not a
symlink** — the two changes above lived only on this disk and were in no
repository at all.

## Plugins

`tpm` and `tmux-resurrect`, cloned into `~/.tmux/plugins/` by the `tools`
phase. They were installed by hand and appeared in no install notes.

`tpm` has to exist before it can install anything, so `setup.sh` clones it like
any other plugin rather than relying on it to bootstrap itself.

After a fresh clone, inside tmux:

```
Prefix + I     install plugins   (Prefix is ctrl-a)
Prefix + R     reload config
```

## Prefix

`ctrl-a`, not the default `ctrl-b`. `send-prefix` is bound to `ctrl-a` twice
over, so `ctrl-a ctrl-a` passes a literal `ctrl-a` through to whatever is
running in the pane.
