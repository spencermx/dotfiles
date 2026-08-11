# Terminal stack: Linux console, tmux, shells, and graphical terminals

The Debian machine and a typical graphical Arch machine use different display
stacks. Several layers are casually called a "terminal", so it helps to name
each one precisely.

## The two stacks

A typical graphical Arch setup:

```text
physical screen and keyboard
        |
Wayland compositor or X display server
        |
Alacritty or Kitty (graphical terminal emulator)
        |
tmux (terminal multiplexer)
        |
Bash or Zsh (shell)
        |
Neovim and other terminal programs
```

This console-only Debian setup:

```text
physical screen and keyboard
        |
Linux kernel text console
        |
tmux (terminal multiplexer)
        |
Bash (shell)
        |
Neovim and other terminal programs
```

The missing layer on Debian is intentional: it has no X server or Wayland
compositor and therefore no graphical applications.

## Linux text console

The Linux text console is the kernel's built-in local terminal interface. It
exists before a graphical environment starts and commonly appears on virtual
terminals such as `/dev/tty1`, `/dev/tty2`, and `/dev/tty3`. They can usually be
selected with Alt-F1, Alt-F2, and so on.

It displays text, a limited color palette, and a bitmap console font. Compared
with a graphical terminal emulator, it has no normal font fallback, scalable
TrueType rendering, GPU-rendered windows, or broad Nerd Font coverage. The
console font has room for a relatively small glyph collection.

## Alacritty, Kitty, and xterm

Alacritty, Kitty, and xterm are graphical **terminal emulators**. They draw a
terminal inside a graphical window and require Wayland or X underneath them.
They can provide true 24-bit color, scalable fonts, font fallback, Nerd Font
icons, graphical clipboard integration, and multiple graphical windows.

Installing Alacritty or Kitty alone would not work on this Debian machine. A
Wayland compositor or X server would also have to be introduced, which would
end the machine's console-only design.

They are called terminal emulators because they imitate the behavior of
historical hardware terminals for command-line programs.

## Bash and Zsh

Bash and Zsh are **shells**. A shell reads commands and launches programs:

```bash
cd ~/source/repos
git status
nvim
```

A shell does not create or draw a window. It runs inside a terminal. Bash and
Zsh work in either a Linux console or a graphical terminal emulator.

For example:

```text
Linux console -> tmux -> Bash
Wayland -> Alacritty -> tmux -> Zsh
```

## tmux

tmux is a **terminal multiplexer**. It sits between the outer terminal and the
programs running inside it:

```text
Linux console
      |
    tmux
   /  |  \
Bash nvim logs
```

It provides persistent sessions, windows, split panes, scrollback, and the
ability to detach and reattach. That is particularly valuable on the Linux
console, which has no graphical windows and limited native scrollback. tmux is
effectively the text-mode window manager for this machine.

tmux does not provide graphical font rendering or create additional display
colors. It divides an existing terminal into rectangular text regions and
provides a virtual terminal to each program running inside it.

## `TERM`, xterm, and `screen-256color`

`xterm` is the name of an actual graphical terminal emulator, but names such as
these are also terminal capability descriptions:

```text
linux
xterm
xterm-256color
screen
screen-256color
tmux-256color
```

Programs inspect the `$TERM` environment variable to decide which control
sequences they may safely send. Outside tmux, the Debian console will normally
report `TERM=linux`. Inside tmux, it reports `TERM=screen-256color` because
that is the terminal interface tmux presents to its child programs.

This does not mean GNU Screen or xterm is running. The flow is:

```text
Neovim sees screen-256color
        |
Neovim sends terminal control sequences to tmux
        |
tmux translates them for the outer terminal
        |
the Linux console draws the result
```

`screen-256color` says that tmux accepts a 256-color command vocabulary. It
does not give the physical Linux console accurate 256-color or 24-bit output.
The outermost display remains the limiting factor.

This distinction explained the original Neovim appearance: Neovim was forced
to generate 24-bit RGB colors, tmux accepted the instructions, and the Linux
console reduced them to its available palette. Several subtle Kanagawa shades
became nearly identical, hiding separators and distorting text colors.

The Debian shell now exports `DOTFILES_CONSOLE=1`. The shared Neovim config
uses that explicit marker to select a console-safe palette while other machines
retain Kanagawa and true color. `$TERM` alone cannot identify the outer display
because tmux uses the same value on a Linux console, in a graphical terminal,
and over SSH.

## Dolphin and Yazi

Dolphin is KDE's graphical file manager, comparable to Windows Explorer or
macOS Finder. It requires a graphical environment. Yazi fills the corresponding
role in a terminal and does not require a display server.

```text
Dolphin -> graphical file manager
Yazi    -> terminal file manager
```

## Quick classification

| Program or system | Role | Requires graphics? |
|---|---|---:|
| Linux console | Kernel text terminal | No |
| Alacritty | Terminal emulator | Yes |
| Kitty | Terminal emulator | Yes |
| xterm | Terminal emulator | Yes |
| tmux | Terminal multiplexer | No |
| Bash | Shell | No |
| Zsh | Shell | No |
| Neovim | Terminal editor | No |
| Yazi | Terminal file manager | No |
| Dolphin | Graphical file manager | Yes |
| i3 | X11 window manager | Yes |
| Sway | Wayland compositor | It provides the graphical layer |

The Debian machine is not accidentally missing a terminal emulator. The Linux
console itself supplies the terminal, tmux adds sessions and panes, Bash
interprets commands, and Neovim and Yazi provide full-screen terminal
interfaces.
