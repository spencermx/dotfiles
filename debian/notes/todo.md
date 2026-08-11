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

- [ ] Resolve the tmux plugin-manager configuration.
  The shared tmux config declares TPM and tmux-resurrect, but TPM was not
  installed on this Debian machine and config reloads previously reported
  `~/.tmux/plugins/tpm/tpm returned 127`. Either install the user-local plugin
  manager and verify resurrection, or remove the inactive declarations from
  the Debian path so reloads are quiet and honest.

- [ ] Test laptop suspend and resume as the normal user.
  Test the lid path on battery power, then confirm the console, tmux session,
  clock, and NetworkManager connection all recover after reopening the lid.
  Do not combine this with another test that could force the machine off.

- [ ] Decide whether tmux should show update/reboot state.
  Automatic security updates are enabled, but kernel updates need the manual
  reboot mechanism. Consider a low-cost status marker when `/var/run/reboot-required`
  exists, rather than requiring the user to remember to check it.

- [ ] Review and finish the one-way gate checklist.
  Continue from `debian/notes/build-plan.md`; remaining decisions include the
  firmware update, GRUB protection, Godot check/decision, sudo removal, and
  eventual root lock. Do not perform the irreversible steps until every gate
  item has been checked again and a recovery/reimage plan is understood.

- [ ] Sort the leftover setup/session artifacts.
  Decide whether `claudesession` and `debian/setupoutputscript` should be
  archived into notes, ignored, or deleted. Do not commit large raw transcripts
  accidentally and do not delete them until their useful context is preserved.

## Completed

Move items here only after they have been tested on the real machine. Record
where the implementation lives and, when available, its commit ID.

- [x] Console-safe Neovim and Yazi presentation.
  Tested on the real console and committed in `d2c1ba9` and `12c5fc8`.
