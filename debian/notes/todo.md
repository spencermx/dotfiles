# Debian console workstation — todo

This is the running backlog for the console-only Debian laptop configured by
this repository. It exists so ideas and unfinished work survive switching
between Codex, Claude, another assistant, or a later terminal session.

The machine deliberately has no X server or Wayland compositor. Its interface
is the Linux text console, with tmux acting as the workspace/window layer and
Bash, Neovim, Yazi, Claude CLI, and similar terminal programs running inside
it. Proposed solutions must preserve that design unless the user explicitly
changes it.

For any assistant continuing this work:

- Read `debian/notes/build-plan.md` and `debian/notes/terminal-stack.md` before
  making system-level or terminal-display changes.
- Treat unchecked entries as ideas to discuss and investigate, not permission
  to implement them automatically.
- Put reproducible configuration in this repository; do not leave unexplained
  machine-only edits behind.
- Test changes on the real Linux console inside tmux. A sandbox or graphical
  terminal does not reproduce its font, color, input-sequence, or system-bus
  behavior accurately.
- Mark an item complete only after the user confirms it works. Add a short note
  describing the implemented file or commit so later sessions can find it.
- Add new remembered tasks here instead of relying on conversation history.

## Todo

- [ ] Add a useful status line to Claude CLI.
  Determine what Claude CLI supports natively before changing shell or tmux
  configuration. Keep it legible on the limited Linux-console color palette.

- [ ] Add battery status to the persistent screen status area.
  Show useful battery information alongside the clock in tmux's bottom-right
  status bar. At minimum include charge percentage; discuss whether charging
  state and estimated remaining time are useful before deciding the final
  format. Avoid expensive commands running every second.

## Completed

Move items here only after they have been tested on the real machine. Record
where the implementation lives and, when available, its commit ID.
