-- MONITOR CONFIG
-- scale "auto": Hyprland picks 1 to 2 from the panel's density, so a new computer with a 4K or 2880 x 1800 panel starts
-- readable. A person's choice (Settings writes monitors.lua) loads after this and wins.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "auto"
})

-- Three fingers do what the window band does, to the window under the pointer (Discord 2026-10-29: the band's line
-- takes fiddling on a touchpad): down hides it into the dock, left and right take that half, up puts it back to its
-- size. It acts once the fingers have travelled far enough; a short brush does nothing. (Three fingers moved the window
-- before; the band's line still does.) Up used to close it, and people swiping up to bring a window back lost it
-- (Discord, Mustiya and Noid, #70); closing stays with the band's line, its menu, a middle click and Super+Q.
-- "back" is the way out of the other three: a window filled to the screen is restored, a window taken to a half goes
-- back to where it was and how big; with neither, the plugin answers "nothing to undo" and nothing moves.
local function bandVerb(verb)
    if verb ~= "back" then return verb end
    local w = hl.get_active_window()
    return (w and tonumber(w.fullscreen) == 1) and "fill" or "unside"
end
-- One gesture for the four ways, decided when the fingers lift by where they went in all. Hyprland picks a gesture's
-- direction from the first 5 units of movement, so a swipe up that set off a little sideways was taken as left or
-- right, and its sideways wobble, added up as distance, then sent the window to a half (Discord, Mustiya, 2026-11-12).
local swipeX, swipeY = 0, 0
local function swipeAdd(e)
    local d = e.delta or {}
    swipeX, swipeY = swipeX + (d.x or 0), swipeY + (d.y or 0)
end
local function swipeVerb()
    if math.abs(swipeY) >= math.abs(swipeX) then
        if math.abs(swipeY) < 120 then return nil end
        return swipeY < 0 and "back" or "hide"
    end
    if math.abs(swipeX) < 120 then return nil end
    return swipeX < 0 and "left" or "right"
end
hl.gesture({
    fingers = 3,
    direction = "swipe",
    action = {
        -- the event that starts the gesture comes again as its first update
        start = function() swipeX, swipeY = 0, 0 end,
        update = swipeAdd,
        finish = function(e)
            local verb = swipeVerb()
            if not e.cancelled and verb then
                hl.dispatch(hl.dsp.exec_cmd("hyprctl tacitgrip " .. bandVerb(verb) .. " active"))
            end
        end
    }
})
hl.gesture({
    fingers = 3,
    direction = "pinch",
    action = "fullscreen"
})
hl.gesture({
    fingers = 4,
    direction = "horizontal",
    action = "workspace"
})
hl.gesture({
    fingers = 4,
    direction = "up",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
    end
})

hl.config({
    gestures = {
        workspace_swipe_distance = 700,
        workspace_swipe_cancel_ratio = 0.2,
        workspace_swipe_min_speed_to_force = 5,
        workspace_swipe_direction_lock = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new = true,
        -- relative (r-1, r+1) instead of through the existing desktops only: an empty desktop 1 can be reached
        workspace_swipe_use_r = true
    },
    general = {
        -- Gaps and border (the owner's, 2026-10-16: Settings writes the person's own over these)
        gaps_in = 2,
        gaps_out = 5,
        gaps_workspaces = 50,

        border_size = 1,

        col = {
            active_border = "rgba(0DB7D455)",
            inactive_border = "rgba(31313600)"
        },
        resize_on_border = true,

        no_focus_fallback = true,
        allow_tearing = true, -- This just allows the `immediate` window rule to work
        snap = {
            enabled = true,
            window_gap = 4,
            monitor_gap = 5,
            respect_gaps = true
        }
    },
    decoration = {
        -- 2 = circle, higher = squircle, 4 = very obvious squircle
        -- Fuck clearly visible squircles. 100% Apple brainrot.
        rounding_power = 2.5,
        rounding = 22,
        -- the windows behind the one in use a little see-through, as on the owner's desktop
        active_opacity = 1.0,
        inactive_opacity = 0.82,

        blur = {
            enabled = true,
            xray = true,
            special = false,
            new_optimizations = true,
            size = 10,
            passes = 3,
            brightness = 1,
            noise = 0.05,
            contrast = 0.89,
            vibrancy = 0.5,
            vibrancy_darkness = 0.5,
            popups = false,
            popups_ignorealpha = 0.6,
            input_methods = true,
            input_methods_ignorealpha = 0.8
        },
        shadow = {
            enabled = true,
            range = 20,
            offset = {0, 2},
            render_power = 4,   -- Hyprland 0.57 refuses more than 4 (0.56 took 10 unchecked)
            color = "rgba(00000020)"

        },
        -- Dim
        dim_inactive = true,
        dim_strength = 0.05,
        dim_special = 0.2
    },
    animations = {
        enabled = true
    },
    dwindle = {
        preserve_split = true,
        smart_split = false,
        smart_resizing = false
        -- precise_mouse_move = true,
    },
})
-- Hyprland's own boxes stay out: its release news after an update and its donation request ("Hyprland updated to
-- 0.56.2!" over a new account's first desktop, 2026-10-17)
hl.config({ ecosystem = { no_update_news = true, no_donation_nag = true } })
-- Curves
hl.curve("expressiveFastSpatial", {
    type = "bezier",
    points = {{0.42, 1.67}, {0.21, 0.90}}
})
hl.curve("expressiveSlowSpatial", {
    type = "bezier",
    points = {{0.39, 1.29}, {0.35, 0.98}}
})
hl.curve("expressiveDefaultSpatial", {
    type = "bezier",
    points = {{0.38, 1.21}, {0.22, 1.00}}
})
hl.curve("emphasizedDecel", {
    type = "bezier",
    points = {{0.05, 0.7}, {0.1, 1}}
})
hl.curve("emphasizedAccel", {
    type = "bezier",
    points = {{0.3, 0}, {0.8, 0.15}}
})
hl.curve("standardDecel", {
    type = "bezier",
    points = {{0, 0}, {0, 1}}
})
hl.curve("menu_decel", {
    type = "bezier",
    points = {{0.1, 1}, {0, 1}}
})
hl.curve("menu_accel", {
    type = "bezier",
    points = {{0.52, 0.03}, {0.72, 0.08}}
})
hl.curve("stall", {
    type = "bezier",
    points = {{1, -0.1}, {0.7, 0.85}}
})
-- Configs
-- windows
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 3,
    bezier = "emphasizedDecel",
    style = "popin 80%"
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 3,
    bezier = "emphasizedDecel"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 2,
    bezier = "emphasizedDecel",
    style = "popin 90%"
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 2,
    bezier = "emphasizedDecel"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 3,
    bezier = "emphasizedDecel",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 10,
    bezier = "emphasizedDecel"
})

-- layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 2.7,
    bezier = "emphasizedDecel",
    style = "popin 93%"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 2.4,
    bezier = "menu_accel",
    style = "popin 94%"
})
-- fade
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 0.5,
    bezier = "menu_decel"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 2.7,
    bezier = "stall"
})
-- workspaces
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 7,
    bezier = "menu_decel",
    style = "slide"
})
-- specialWorkspace
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 2.8,
    bezier = "emphasizedDecel",
    style = "slidevert"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 1.2,
    bezier = "emphasizedAccel",
    style = "slidevert"
})
-- zoom
-- No ease-in for a freshly connected output: it fades and zooms the built-in wallpaper in,
-- which reads as "Hyprland fading in" after the boot splash. The picture is already there.
hl.animation({ leaf = "monitorAdded", enabled = false })

hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 3,
    bezier = "standardDecel"
})

-- The keyboard chosen in Setup: tacit-install writes the layout to /etc/vconsole.conf as XKBLAYOUT, so a password made
-- in Setup is typed the same at the lock. The variant and options are read too, for a file written by hand or by another
-- tool, and a value may be quoted. US where no layout is written (the Book4 has only a console KEYMAP there).
local function system_kb(key)
    local f = io.open("/etc/vconsole.conf", "r")
    if not f then return nil end
    local s = "\n" .. f:read("a")
    f:close()
    local v = s:match("\n" .. key .. "=[\"']?([^\"'\n]*)")
    return v ~= "" and v or nil
end

hl.config({
    input = {
        kb_layout = system_kb("XKBLAYOUT") or "us",
        kb_variant = system_kb("XKBVARIANT") or "",
        kb_options = system_kb("XKBOPTIONS") or "",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35,

        follow_mouse = 1,
        off_window_axis_events = 2,

        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            clickfinger_behavior = true,
            scroll_factor = 0.7
        }
    },

    misc = {
        -- Not off: tacit-ground.so hands Hyprland the person's boot still for its first frames (and the flat
        -- background colour after them, never Hyprland's own wallpaper).
        disable_hyprland_logo = false,
        force_default_wallpaper = 0,
        -- The session is "Tacit:Hyprland" (tacit-portal's choices apply first); Hyprland's own check would put a
        -- warning on screen for any name but "Hyprland".
        disable_xdg_env_checks = true,
        disable_splash_rendering = true,
        vrr = 0,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        enable_swallow = false,
        swallow_regex = "(foot|kitty|allacritty|Alacritty)",
        on_focus_under_fullscreen = 2,
        allow_session_lock_restore = true,
        session_lock_xray = false,
        initial_workspace_tracking = false,
        focus_on_activate = true
    },

    binds = {
        scroll_event_delay = 0,
        hide_special_on_workspace_change = true
    },

    cursor = {
        zoom_factor = 1,
        zoom_rigid = false,
        zoom_disable_aa = true,
        hotspot_padding = 1,
        -- Focusing a window does not move the pointer: Hyprland warps it to the middle of the window it focuses
        -- (a picture or a video opened in the viewer, a window picked in the overview), and the jump takes the
        -- pointer away from the person. Tacit draws its surfaces over windows, so nothing here wanted the warp.
        no_warps = true
    },

    xwayland = {
        -- an X program on a scaled screen is scaled up with the rest (soft, but as large as everything else); at
        -- true the scale-2 screens "auto" gives would show it half size
        force_zero_scaling = false
    }
})

-- The boot still as Hyprland's own first frames (tacit-boot's tacit-ground.so): it hands Hyprland the person's
-- still at plugin load, before any output is connected, so the first frame is the picture the splash held.
if is_file_exists("/usr/lib/tacit/hyprland/tacit-ground.so") then
    hl.plugin.load("/usr/lib/tacit/hyprland/tacit-ground.so")
end

-- A window shared on its own (a call, a stream) keeps drawing while it is out of sight (tacit-portal's tacit-share.so):
-- Hyprland suspended it and copied no frames once it was on another workspace, so the share froze on its last frame
if is_file_exists("/usr/lib/tacit/hyprland/tacit-share.so") then
    hl.plugin.load("/usr/lib/tacit/hyprland/tacit-share.so")
end

-- The window band (tacit-boot's tacit-frame.so): the line above every window; up to the notch closes, down to the dock
-- hides, to a side takes that half, a right click opens the window's menu (the shell's WindowBand and WindowMenu)
-- Settings > Windows > Line on windows turns it off by making this file (the plugin is also let go at once)
if is_file_exists("/usr/lib/tacit/hyprland/tacit-frame.so")
    and not is_file_exists((os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/quickshell/user/window-line-off") then
    hl.plugin.load("/usr/lib/tacit/hyprland/tacit-frame.so")
end
