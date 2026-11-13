-- Focus and the pointer after a key moves the focus (session/hypr/hyprland/general.lua): the file's hl.config read with
-- a pretend hl, its input and cursor values then run through Hyprland 0.56.2's follow_mouse = 1 choice as
-- InputManager.cpp mouseMoveUnified makes it (lines 701-716: m_lastMouseFocus, mouse_refocus, the motion threshold),
-- with the two ways a key focuses a window: Actions::focus (hl.dsp.focus, used by Alt+Tab, the overview, the dock and
-- notifications), which moves nothing, and switchToWindow (Super+arrows), whose simulated move with no_warps on and
-- follow_mouse under 2 is forced onto the new window (ConfigActions.cpp 61-90).
local tree = os.getenv("TACIT_TREE") or ((arg[0]:match("^(.*)/[^/]*$") or ".") .. "/..")
local file = tree .. "/session/hypr/hyprland/general.lua"

local failed = 0
local function check(name, ok, why)
    if ok then print("  ok    " .. name)
    else failed = failed + 1; print("  FAIL  " .. name .. (why and (": " .. why) or "")) end
end

-- the config as Hyprland would hold it: each hl.config table merged in, section by section
local config = {}
local any = setmetatable({}, { __call = function(t) return t end, __index = function(t) return t end })
hl = setmetatable({
    get_monitors = function() return {} end,
    config = function(t)
        for section, values in pairs(t) do
            config[section] = config[section] or {}
            if type(values) == "table" then for k, v in pairs(values) do config[section][k] = v end end
        end
    end,
}, { __index = function() return any end })
HOME = "/home/someone"
is_file_exists = function() return false end
io.popen = function() return { read = function() return "" end, close = function() return true end } end
dofile(file)

print("Focus and the pointer after a key moves the focus (session/hypr/hyprland/general.lua)")
local input, cursor = config.input or {}, config.cursor or {}
local refocusOn = input.mouse_refocus ~= false   -- Hyprland's default is true
check("focus follows the pointer (follow_mouse 1), the pointer is not warped (no_warps)",
    input.follow_mouse == 1 and cursor.no_warps == true)

-- one desktop: windows A and B, the pointer resting on A
local function desk()
    local d = { focus = "A", lastMouse = "A", under = "A" }
    -- mouseMoveUnified for follow_mouse 1, the window under the pointer found, no button held
    function d.move(delta, forced)
        local found = forced or d.under
        local last = d.lastMouse
        if input.follow_mouse == 1 and (refocusOn or last ~= found) then
            if last ~= found or d.focus ~= found then
                d.lastMouse = found
                if delta > 0 then d.focus = found end   -- follow_mouse_threshold 0
            end
        end
    end
    -- Actions::focus: fullWindowFocus, warpCursor (nothing with no_warps)
    function d.focusWindow(w) d.focus = w end
    -- switchToWindow: fullWindowFocus, then the move forced onto the new window when no_warps is off or follow_mouse < 2
    function d.switchTo(w)
        d.focus = w
        if not cursor.no_warps or input.follow_mouse < 2 then d.move(0, w) end
    end
    return d
end

do
    local d = desk()
    d.focusWindow("B")            -- Alt+Tab, or a window picked in the overview
    d.move(0)                     -- the switcher's layer going away: Hyprland's own simulated move (LayerSurface.cpp)
    d.move(2)                     -- the touchpad brushed, the pointer still on A
    check("after Alt+Tab or the overview, a brush of the pointer over the old window keeps the typing where the key put it",
        d.focus == "B", "focus went back to " .. d.focus)
    d.under = "B"; d.move(30)
    d.under = "A"; d.move(30)
    check("moving into another window and back still gives focus to the window moved into", d.focus == "A", d.focus)
end
do
    local d = desk()
    d.under = "B"; d.move(30)
    check("and moving from one window into another gives it focus, as before", d.focus == "B", d.focus)
end
do
    -- what this leaves as it was: Super+arrows go through switchToWindow, whose forced move marks the new window as the
    -- pointer's, so the next motion over the old one still gives it focus back (only the warp would stop that)
    local d = desk()
    d.switchTo("B")
    d.move(2)
    check("Super+arrows still hand focus back on the next motion over the old window (as before)", d.focus == "A", d.focus)
end

if failed > 0 then os.exit(1) end
