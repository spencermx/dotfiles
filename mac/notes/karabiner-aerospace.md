# Karabiner + AeroSpace are one keymap

Read this before touching either file. They are two programs implementing a
single keyboard layout, and neither one says so.

## What is actually going on

Every binding in `config/.aerospace.toml` uses `ctrl-cmd-alt` as its modifier:

```toml
ctrl-cmd-alt-h = 'focus left'
ctrl-cmd-alt-1 = 'workspace 1'
ctrl-cmd-alt-shift-q = 'close'
```

Nobody types a three-modifier chord. `config/karabiner.json` is what makes it
usable: its single rule, "Right CMD: Aerospace bindings + copy/paste
passthrough", holds 27 manipulators, and 20 of them rewrite

```
right_command + <key>   ->   left_control + left_command + left_option + <key>
```

So the key you actually press is **Right CMD + h**. AeroSpace never sees Right
CMD; it sees the three-modifier chord Karabiner synthesises.

## Consequences

- **Install one without the other and half your machine is dead.** AeroSpace
  alone: every window-management binding needs a chord you will not type.
  Karabiner alone: Right CMD does nothing at all.
- **Do not "simplify" the AeroSpace modifiers.** Changing `ctrl-cmd-alt-h` to
  something shorter breaks the Karabiner mapping that feeds it, and the failure
  looks like AeroSpace ignoring the key rather than a mismatch between files.
- **Both files are in `$CASKS` and `$LINKS` together.** `setup.sh` installs
  `aerospace` and `karabiner-elements` adjacently and links both configs.

## All 27 manipulators

| count | keys | does |
|-------|------|------|
| 22 | Right CMD + `hjkl` `q` `/` `,` `-` `=` `tab` `enter` `;` `0`–`9` (± Shift) | → ctrl+cmd+alt+same — feeds AeroSpace |
| 3 | Right CMD + `c` / `v` / `x` | passthrough to **Left** CMD |
| 2 | Right CMD + Shift + `[` / `]` | → ctrl+shift+PageUp/PageDown — move tab left/right |

The passthrough entries exist purely because Right CMD stopped being a CMD key.
Without them, Right CMD + C would emit the AeroSpace chord instead of copying.

Note the two bracket manipulators have **no app condition** — nothing in this
file does. They fire in every application, and only mean "move tab" in apps
that implement ctrl+shift+PageUp/PageDown.

## The file documents itself

Every manipulator carries a `description`, which is a real field in Karabiner's
schema, and all 27 are filled in. To see the whole keymap without reading the
JSON:

```sh
jq -r '.profiles[].complex_modifications.rules[].manipulators[].description' \
    config/karabiner.json
```

Keep filling it in when adding a manipulator — that field is the only comment
mechanism strict JSON gives you, and Karabiner preserves it across UI edits.

Karabiner also writes timestamped copies to
`~/.config/karabiner/automatic_backups/` whenever the UI saves — useful if a UI
edit clobbers something the repo had.

## Chrome tab shortcuts are a third, separate place

⌘`[` and ⌘`]` for previous/next tab are **not** in this file and **not** in
Chrome. Chrome has no shortcut editor. They are macOS *App Shortcuts*, which
override any app's menu item by its exact title:

```
System Settings -> Keyboard -> Keyboard Shortcuts -> App Shortcuts
```

They land in Chrome's own preferences domain, which is where `setup.sh` writes
them from `$CHROME_SHORTCUTS`:

```sh
defaults read com.google.Chrome NSUserKeyEquivalents
```

```
"New Window"          = "~c";   option-C
"Select Next Tab"     = "@]";   cmd-]
"Select Previous Tab" = "@[";   cmd-[
```

`@` = cmd, `~` = option, `^` = ctrl, `$` = shift. **The title has to match the
menu item exactly** — "Select Next Tab" works, "Next Tab" does nothing, and
there is no error either way. That is the single most annoying thing about this
mechanism.

So tab handling is split across two systems on purpose:

| | mechanism |
|-|-----------|
| ⌘`[` / ⌘`]` — switch tabs | macOS App Shortcut, overriding a Chrome menu item |
| Right CMD + Shift + `[` / `]` — move tab | Karabiner, synthesising ctrl+shift+PageUp/Down |

`.aerospace.toml` also has `cmd-e` → open a new Chrome window, which overlaps
with the option-C App Shortcut above. Two routes to the same thing, from two
different config systems.

## What cannot be scripted

This is why standing it up felt contrived — the config files are the easy half.
macOS gates all of the following behind manual approval, by design, and no
`defaults write` reaches them:

1. **Karabiner's driver extension** — Privacy & Security → allow
   `org.pqrs.Karabiner-DriverKit-VirtualHIDDevice`. Usually wants a reboot.
2. **Karabiner Input Monitoring** — Privacy & Security → Input Monitoring, for
   `karabiner_grabber` and `Karabiner-Elements`.
3. **AeroSpace Accessibility** — Privacy & Security → Accessibility. Without it
   AeroSpace launches and silently moves no windows.
4. **The App Shortcuts above**, if you would rather add them by hand than let
   `setup.sh` write them.

`setup.sh` installs both casks and links both configs. Items 1–3 are still
yours to click through once per machine.
