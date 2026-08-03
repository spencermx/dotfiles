# Yazi

Installed by `setup.sh` along with everything its preview pane shells out to.
There is no yazi config in this repo — it runs on defaults.

## Why the package list is so long

Each of these backs a specific file type in the preview pane. Yazi works
without them, it just shows nothing useful for those files:

| package | previews |
|---------|----------|
| `ffmpeg-full` | video thumbnails, audio metadata |
| `poppler` | PDF |
| `resvg` | SVG |
| `imagemagick-full` | image formats beyond the built-ins |
| `sevenzip` | archive contents |
| `fd`, `ripgrep`, `fzf`, `zoxide` | the file/content search and jump bindings |
| `jq` | JSON |

`fzf` and `zoxide` are also wired into the shell directly — see `config/.zshrc`.

## Fonts

Yazi draws file-type glyphs from a Nerd Font. Two casks are declared:

- `font-symbols-only-nerd-font` — the glyphs themselves
- `font-jetbrains-mono-nerd-font` — the terminal font

**The terminal has to be set to the Nerd Font or you get tofu.** That is part
of the "Clear Dark" Terminal.app profile in `defaults/`, which `setup.sh`
imports. Check it renders:

```sh
echo -e "  "
```

Three icons means it works. Three boxes means the profile didn't apply, or
Terminal is on a different profile.

## The `e` shortcut

`config/.zshrc` defines `e`, which runs yazi and then cds the shell to wherever
you quit. A child process can't change its parent's directory, so yazi writes
its exit directory to a temp file and the function does the `cd` itself.

The Windows repo has an `e` too, doing the same handoff around `drift`.
