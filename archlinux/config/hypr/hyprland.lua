-- Lua port of hyprland.conf -- hyprlang configs are deprecated since
-- Hyprland 0.55 and support ends around 0.57.
-- While both this file and hyprland.conf exist, Hyprland loads only this one
-- (picked once at startup); delete or rename it to fall back to the .conf.
-- Refer to the wiki for more information.
-- https://wiki.hypr.land/Configuring/


------------------
---- MONITORS ----
------------------

-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })
-- hl.monitor({ output = "DP-2", mode = "2560x1440@60", position = "0x0", scale = 1 })
-- hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@144", position = "2560x360", scale = 1 })

-- ------------------------------- Monitor Setups -------------------------------
-- 3 MONITOR 2.5k + 4k + 4k - HIGH RESOLUTION
-- hl.monitor({ output = "DP-1", mode = "2560x1440@60", position = "0x0", scale = 1 })
-- hl.monitor({ output = "DP-2", mode = "3840x2160@60", position = "2560x0", scale = 2 })
-- hl.monitor({ output = "HDMI-A-1", mode = "3840x2160@60", position = "4480x0", scale = 2 })

-- 3 MONITOR 2.5k + 1080p + 1080p - LOW RESOLUTION
-- hl.monitor({ output = "HDMI-A-1", mode = "2560x1440@60", position = "0x0", scale = 1 })
-- hl.monitor({ output = "DP-1", mode = "1920x1080@60", position = "2560x0", scale = 1 })
-- hl.monitor({ output = "DP-2", mode = "1920x1080@60", position = "4480x0", scale = 1 })

-- hl.monitor({ output = "DP-2", mode = "2560x1440@60", position = "0x0", scale = 1 })
-- hl.monitor({ output = "DP-1", mode = "3840x2160@60", position = "2560x0", scale = 2 })
-- hl.monitor({ output = "HDMI-A-1", mode = "3840x2160@60", position = "4480x0", scale = 2 })

-- 2 MONITOR 4k + 4k  <-- ACTIVE
-- DP-2     = ASUS ROG XG27UCDMG    4k OLED, 240Hz     left
-- HDMI-A-1 = Samsung Odyssey G81SF 4k, 120Hz max here right
-- scale 2 on both -> each is 1920x1080 logical, so right sits at 1920x0
hl.monitor({ output = "DP-2",     mode = "3840x2160@240", position = "0x0",    scale = 2 })
hl.monitor({ output = "HDMI-A-1", mode = "3840x2160@120", position = "1920x0", scale = 2 })

-- 1 MONITOR 2k
-- hl.monitor({ output = "DP-1", mode = "2560x1440@60", position = "0x0", scale = 1.25 })
-- ----------------------------- End Monitor Setups -----------------------------


---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use
local terminal    = "alacritty"
local fileManager = "dolphin"
local browser     = "firefox"
local menu        = "bemenu-run"


-------------------
---- AUTOSTART ----
-------------------

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
hl.on("hyprland.start", function()
    hl.exec_cmd("waybar & hyprpaper")
end)


-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("JAVA_HOME", "/usr/lib/jvm/java-17-openjdk")


-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 0,
        gaps_out = 0,

        border_size = 1,

        col = {
            active_border   = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "dwindle",
    },
})

hl.config({
    decoration = {
        rounding       = 0,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        blur = {
            enabled  = true,
            size     = 3,
            passes   = 1,
            vibrancy = 0.1696,
        },
    },
})

hl.config({
    animations = {
        enabled = false,
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Dwindle-Layout/ for more
hl.config({
    dwindle = {
        -- pseudotile = true, -- Master switch for pseudotiling. Enabling is bound to mainMod + P in the keybinds section below
        preserve_split = true, -- You probably want this
    },
})

-- See https://wiki.hypr.land/Configuring/Layouts/Master-Layout/ for more
hl.config({
    master = {
        new_status = "master",
    },
})

hl.config({
    misc = {
        force_default_wallpaper = 0,     -- Set to 0 or 1 to disable the anime mascot wallpapers
        disable_hyprland_logo   = false, -- If true disables the random hyprland logo / anime girl background. :(
    },
})


---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout  = "us",
        kb_variant = "",
        kb_model   = "",
        kb_options = "",
        kb_rules   = "",

        follow_mouse = 1,

        sensitivity = 0, -- -1.0 - 1.0, 0 means no modification.

        touchpad = {
            natural_scroll = false,
        },
    },
})

-- Example per-device config
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Devices/ for more
hl.device({
    name        = "epic-mouse-v1",
    sensitivity = -0.5,
})

-- hl.config({
--     cursor = {
--         no_warps = true,
--     },
-- })


--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/ for more
-- See https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/ for workspace rules

-- Example windowrule
-- hl.window_rule({ name = "float-kitty", match = { class = "^(kitty)$", title = "^(kitty)$" }, float = true })

-- Ignore maximize requests from apps. You'll probably like this.
-- hl.window_rule({ name = "suppress-maximize-events", match = { class = ".*" }, suppress_event = "maximize" })

-- Fix some dragging issues with XWayland
-- hl.window_rule({
--     name  = "fix-xwayland-drags",
--     match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
--     no_focus = true,
-- })


---------------------
---- KEYBINDINGS ----
---------------------

local mainMod = "ALT" -- SUPER Sets "Windows" key as main modifier

hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd(menu))

-- Move focus with mainMod + h/j/k/l
hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "l" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "r" }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "u" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "d" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

-- Move windows with mainMod + SHIFT + h/j/k/l
hl.bind(mainMod .. " + SHIFT + h", hl.dsp.window.move({ direction = "l" }))
hl.bind(mainMod .. " + SHIFT + j", hl.dsp.window.move({ direction = "d" }))
hl.bind(mainMod .. " + SHIFT + k", hl.dsp.window.move({ direction = "u" }))
hl.bind(mainMod .. " + SHIFT + l", hl.dsp.window.move({ direction = "r" }))

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

-- ----------- CUSTOM ---------
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
-- NOTE: mainMod + a is bound twice (here and togglefloating below); both fire on each press.
hl.bind(mainMod .. " + a", hl.dsp.exec_cmd("pgrep hyprpaper && pkill hyprpaper || hyprpaper &"))
hl.bind(mainMod .. " + SHIFT + e", hl.dsp.exec_cmd("loginctl terminate-user $(whoami)"))

-- Brightness control bindings
hl.bind("F10", hl.dsp.exec_cmd("brightnessctl set +5%"))
hl.bind("F9",  hl.dsp.exec_cmd("brightnessctl set 5%-"))

-- Preselect split direction for next window
hl.bind(mainMod .. " + g", hl.dsp.layout("preselect d")) -- split horizontally i.e. split across a horizontal line
hl.bind(mainMod .. " + v", hl.dsp.layout("preselect r")) -- split vertically i.e. split across a vertical line
hl.bind(mainMod .. " + x", hl.dsp.layout("togglesplit")) -- toggles the split (top/side) of the current window. preserve_split must be enabled for toggling to work.
hl.bind(mainMod .. " + s", hl.dsp.layout("swapsplit"))   -- swaps the two halves of the split of the current window.

-- Screenshots
hl.bind("Print",         hl.dsp.exec_cmd("hyprshot -m output -o ~/Pictures"))          -- Capture entire monitor
hl.bind("SHIFT + Print", hl.dsp.exec_cmd("hyprshot -m region --freeze -o ~/Pictures"))

-- Resize windows with mainMod + R followed by h/j/k/l
hl.bind(mainMod .. " + R", hl.dsp.submap("resize"))
hl.define_submap("resize", function()
    -- Resize bindings: h (shrink width), l (expand width), k (shrink height), j (expand height)
    hl.bind("h", hl.dsp.window.resize({ x = -10, y = 0,   relative = true }), { release = true })
    hl.bind("l", hl.dsp.window.resize({ x = 10,  y = 0,   relative = true }), { release = true })
    hl.bind("k", hl.dsp.window.resize({ x = 0,   y = -10, relative = true }), { release = true })
    hl.bind("j", hl.dsp.window.resize({ x = 0,   y = 10,  relative = true }), { release = true })

    -- Exit resize mode
    hl.bind("escape", hl.dsp.submap("reset"))
    hl.bind("return", hl.dsp.submap("reset"))
end)

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + w",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + w", hl.dsp.window.move({ workspace = "special:magic", follow = false }))

hl.bind(mainMod .. " + a", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
-- hl.bind(mainMod .. " + M", hl.dsp.exit())
-- hl.bind(mainMod .. " + P", hl.dsp.window.pseudo()) -- dwindle
