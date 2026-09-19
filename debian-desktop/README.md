# Debian desktop

A desktop overlay for Debian 13: Sway, automatic tiling, Waybar, Alacritty,
bemenu, Firefox ESR, Thunar, notifications and tray applets. The workflow is
adapted from the Arch machine: Alt modifier, Vim directions, ten workspaces,
no gaps, one-pixel borders and the Nord Legible terminal palette. Alacritty
uses a readable 16-point JetBrains Mono font.

This adds a Sway login session alongside the existing desktop. It does not
replace LightDM, remove Xfce, change the boot target, or log out the current
session. It assumes a working Debian desktop and preserves the user's existing
CLI tooling; it is not a base OS installer. The console-only `debian/` profile
remains a separate machine profile. Never run its hardening gate on a desktop.

## Install

```sh
cd ~/source/repos/dotfiles/debian-desktop
./setup.sh --dry-run
./setup.sh
```

Run as your normal desktop user. The script authenticates once for the
`packages,services` phases (using cached sudo credentials or asking for the
root password with `su`), then installs links as your user. The WirePlumber
audio coexistence preference is linked before package installation; other
links are installed after apt succeeds. An installation never removes
packages and updates only the listed packages and required dependencies.

Individual phases are also available:

```sh
./setup.sh --phase packages,services
./setup.sh --phase links
./setup.sh --phase check
```

The links phase is idempotent. Existing files or symlinks are moved, intact,
into a unique `~/.local/state/debian-desktop/backups/` directory before
replacement. It refuses to write through symlinked parent directories.
Configs are linked into this profile and updates take effect from the repo.

When ready, save your work and log out of Xfce. Select **Sway** in LightDM's
session chooser and log in normally. Alt+Enter opens the terminal. Selecting
**Xfce Session** at the next login returns to the previous desktop.

## Keys

| Keys | Action |
|------|--------|
| Alt+Enter | Alacritty with your existing shell aliases and desktop overrides |
| Alt+D | bemenu program launcher; type a command name |
| Alt+E | Firefox ESR |
| Alt+Shift+F | Thunar file manager |
| Alt+H/J/K/L | Focus left/down/up/right |
| Alt+Shift+H/J/K/L | Move the focused window |
| Alt+1…0 | Workspaces 1…10 |
| Alt+Shift+1…0 | Send window to workspace without following |
| Alt+F | Fullscreen |
| Alt+A | Toggle floating; Alt+drag moves floating windows |
| Alt+Space | Focus floating/tiling layer |
| Alt+G / Alt+V | Put the next window below / beside the current tile |
| Alt+X | Change current split orientation |
| Alt+S | Swap focused tile with its next sibling |
| Alt+T | Tabbed layout; Alt+X returns to a split |
| Alt+W / Alt+Shift+W | Show scratchpad / send window to scratchpad |
| Alt+R, then H/J/K/L | Resize; Enter or Escape finishes |
| Alt+Shift+Q | Close window |
| Alt+Shift+C | Reload Sway config |
| Alt+Ctrl+L | Lock |
| Alt+Shift+P | Power menu |
| Alt+Shift+E | Confirm logout; Cancel is selected initially |
| Print / Shift+Print | Focused output / select region; saved and copied |
| Brightness keys or F9/F10 | Decrease/increase screen brightness |
| Volume and playback keys | Audio and media controls |

Automatic tiling chooses split orientation from the focused tile's geometry.
It approximates Hyprland's dwindle layout; Sway's layout tree is not identical.
Alt+G/V override the next split until focus changes. The scratchpad cycles
individual windows, unlike Hyprland's named special workspace. Region captures
use a live selection rather than Hyprshot's frozen preview.

## Desktop integration

- The laptop display and external monitors are detected automatically. Put
  machine-specific `output`/`input` settings in `~/.config/sway/local.conf`.
- The plain Nord background replaces the Arch-only wallpaper path.
- PulseAudio remains the sound server. PipeWire and WirePlumber provide portal
  screen capture, without `pipewire-pulse` or `pipewire-audio`. The user-local
  WirePlumber fragment disables its audio/Bluetooth hardware management. Remove
  that fragment if deliberately migrating audio to PipeWire later.
- Screen sharing uses the wlr portal and an explicit monitor chooser; file
  dialogs use the GTK portal. Portal preferences are specific to Sway.
- Swayidle locks after fifteen idle minutes and turns off displays after thirty.
  `before-sleep` locks before logind suspend (including lid suspend); the
  delay is bounded by logind's `InhibitDelayMaxSec`. The desktop suspend
  command also locks first and aborts its request if locking fails. Unlock
  with your normal login password.
- The power menu asks for confirmation before logout, reboot or poweroff.
- Screenshots go to your Pictures/Screenshots folder and the clipboard.
- The session helper starts Mako, NetworkManager/Bluetooth applets, a polkit
  authentication agent, autotiling and swayidle, and stops its children on
  Sway shutdown. Log: `~/.local/state/debian-desktop/session.log`.
- `desktop-terminal` loads your existing `~/.bashrc` and then the desktop
  overrides. They remove `DOTFILES_CONSOLE`, set the browser, use Swaylock
  for `lock`/`suspend` and add `fe` to open Thunar here, as on Arch and the
  Mac. Physical TTYs and existing tmux sessions are unchanged.

Sway reserves the Alt bindings before terminal applications see them. Tmux's
existing prefix bindings still work; its console-specific clipboard config is
left intact. Use Alacritty's Ctrl+Shift+C/V for the system clipboard.

## Verify after logging in

Try Alt+Enter, Alt+D and workspace switching, then test sound, brightness,
Wi-Fi/Bluetooth and screenshots. Test Alt+Ctrl+L, command-driven suspend and
lid resume with saved work. Test screen sharing from Firefox; select the
display when the chooser appears. These hardware/login behaviors cannot be
fully verified by an offscreen compositor test.

The automated smoke test uses a private headless Sway and D-Bus session. It
checks three rendered Alacritty windows, window/workspace commands, Waybar,
Mako, screenshots and Swaylock startup. It does not authenticate an unlock,
suspend the laptop or change the live session's environment:

```sh
dbus-run-session -- python3 tests/smoke.py
```

Logs and a screenshot are saved to the temporary directory printed by the
test. The test requires the packages and links installed by setup first.

Reference: Debian's [Sway manual](https://manpages.debian.org/trixie/sway/sway.5.en.html),
[swayidle manual](https://manpages.debian.org/trixie/swayidle/swayidle.1.en.html)
and [portal manual](https://manpages.debian.org/trixie/xdg-desktop-portal-wlr/xdg-desktop-portal-wlr.5.en.html).
