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

- [ ] Resolve the tmux plugin-manager configuration.
  The shared tmux config declares TPM and tmux-resurrect, but TPM was not
  installed on this Debian machine and config reloads previously reported
  `~/.tmux/plugins/tpm/tpm returned 127`. Either install the user-local plugin
  manager and verify resurrection, or remove the inactive declarations from
  the Debian path so reloads are quiet and honest.

- [ ] Test laptop suspend and resume as the normal user.
  Two paths now: the lid switch, which logind handles itself and which needs
  no authorisation, and the `suspend` shell function, which goes through
  /run/user-power like `reboot` and `poweroff`. Test both on battery power,
  then confirm the console, tmux session, clock, and NetworkManager connection
  all recover. Do not combine this with another test that could force the
  machine off. Note the lid path is untested on this hardware and the power
  button was already found to raise no input event — if the lid raises none
  either, the shell function is the only route and must be verified pre-gate,
  since `user-suspend.path` is root-owned and cannot be added afterwards.

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

- [x] Confirm the GDScript stack on the real console. Confirmed 2026-08-11.
  `godot` 4.7.1 and the `tree-sitter` CLI are installed in `~/.local/bin`;
  `setup.sh` grew `install_godot` and `install_tree-sitter`;
  `common/config/nvim/` gained the gdscript/godot_resource parsers, a
  `gdscript` LSP and a `gdformat` formatter rule. `:checkhealth vim.lsp` on a
  `.gd` buffer lists the client attached with the project as its root.
  The editor no longer has to be started by hand, and the LSP is no longer
  pinned to `127.0.0.1:6005` — see the next entry.

- [x] Start the headless editor per project instead of pinning port 6005.
  Done 2026-08-11 in `common/config/nvim/lua/plugins/mason-lspconfig.lua`. A
  fixed port only ever serves one project, and the second project opened would
  have silently attached to the first project's server. The `gdscript` client's
  `cmd` is now a function: it reuses the editor already serving this root if
  `pgrep` finds one, otherwise picks a free port in 6005-6055 and spawns
  `godot --headless --editor --path <root> --lsp-port N --dap-port N+100`.
  Measured on this machine: 1.9s to attach cold, 218ms warm.

  Two traps, both silent, worth not rediscovering. libuv's `bind()` reports an
  occupied port as free — `EADDRINUSE` only surfaces at `listen()` — so it
  cannot be used to find a free port. And an async connect probe never gets its
  callback while the LSP `cmd` hook blocks, so it always times out. The working
  check is a synchronous `ss -ltnH` call. Editors are detached and outlive
  Neovim; `:GodotLspStop` kills them.

- [x] Note that nvim-lspconfig's `Lsp*` commands are gone on Neovim 0.12.
  Confirmed 2026-08-11 on this machine. Neovim 0.12 ships a builtin `:lsp`, and
  `plugin/lspconfig.lua` returns early when `exists(':lsp') == 2`, so `:LspInfo`,
  `:LspLog`, `:LspStart`, `:LspStop` and `:LspRestart` are all undefined. Use
  `:checkhealth vim.lsp` for what `:LspInfo` showed, and `:lsp restart|stop|
  enable|disable` for the rest. `:lsp` has no `info` subcommand.

- [ ] Re-run the root phase of `setup.sh` — the package list grew.
  `libfontconfig1` (Godot dlopens it), `cmake`, plus `python3-venv` and `pipx`.
  This is apt, so it can only ever happen before the gate. Without the Python
  two, nothing can ever install a Python package on this machine again —
  including `gdtoolkit`, which is the only GDScript formatter and linter that
  exists here. Without `cmake`, `:MasonInstall luaformatter` cannot build, so
  there is no Lua formatting either. From `debian/`:
  `su -c './setup.sh --phase packages'` — the phase is a `--phase` value, not a
  positional argument, and `su -c ./setup.sh` would run `system` and the
  handoff too.

- [ ] Install gdtoolkit once pipx exists.
  `setup.sh`'s tools phase does it (`pipx install 'gdtoolkit==4.*'`), pinned to
  4.x to match the engine. Blocked on the item above. Godot's own LSP reports
  `documentFormattingProvider: false`, so without this there is no way to
  format GDScript on this machine.

- [ ] Decide on a text browser, before the gate.
  There is no `w3m`, `lynx` or `links2`, which means captive-portal wifi cannot
  be logged into at all — the machine associates and then every request hits
  the portal. `build-plan.md` names a library as the working environment. Also
  the only way to read HTML docs offline here. apt-only, so one-way.

- [ ] Decide the rest of the pre-gate apt list.
  `shellcheck` (this repo is a 39 KB bash script), `entr`/`inotify-tools` (no
  file-watch loop otherwise), `vlock` (the console is currently unlocked when
  you walk away), `sqlite3`, `tig`, `netcat-openbsd`, and `pass` if the
  break-glass `ANTHROPIC_API_KEY` in `build-plan.md` is meant to be real.
  Deliberately excluded: `lazygit`, `shfmt`, `delta` — all ship static
  binaries and stay installable forever.

- [ ] Fix unattended-upgrades to match its own spec.
  Checked 2026-08-11 and three of the four settings `build-plan.md` calls
  mandatory are absent. `trixie-updates` is genuinely uncovered — its release
  is `n=trixie-updates`, and the current pattern only matches `codename=trixie`
  — so the `ca-certificates`/`tzdata` channel is not being applied. Also
  missing: `Remove-Unused-Kernel-Packages`, the `--force-confold` dpkg options,
  and `APT::Periodic::AutocleanInterval` (110 MB of `.debs` cached already, and
  `apt clean` needs root). Note the plan's `/boot` fear does not apply to this
  disk — there is no separate `/boot`, it is on a 225 G root at 3%.

- [ ] Decide on a BIOS supervisor password.
  The gate's whole value rests on the GRUB password, but Secure Boot is
  disabled and nothing stops F12 → boot a USB → mount the unencrypted root →
  edit `/etc/shadow`. That is cheaper than the screwdriver-and-NVMe path the
  plan already accepts as its floor. On a ThinkPad the supervisor password
  locks setup and the boot menu and cannot be cleared by pulling the coin
  cell — it needs mainboard service, which is the stated bar. Not one-way:
  settable any day, before or after the gate.

- [ ] `sudo` is installed again — `build-plan.md` says otherwise in two places.
  `dpkg-query` reports `install ok installed` and apt history shows
  `apt install sudo` on 2026-08-10 at 21:31. Not an active hole, since `id`
  confirms no admin group, but the purge section and the gate sequence both
  describe a state that is no longer true.

## Completed

Move items here only after they have been tested on the real machine. Record
where the implementation lives and, when available, its commit ID.

- [x] Console-safe Neovim and Yazi presentation.
  Tested on the real console and committed in `d2c1ba9` and `12c5fc8`.

- [x] Battery status in tmux's bottom-right status area.
  Reads capacity and charging state directly from sysfs every 15 seconds via
  `debian/bin/tmux-battery`; tested on the real console and committed in
  `c5b82d1`.
