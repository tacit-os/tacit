-- The touchpad gestures in session/hypr/hyprland/general.lua, replayed the way Hyprland 0.56.2 feeds them
-- (src/managers/input/trackpad/TrackpadGestures.cpp, LuaFunctionGesture.cpp): nothing until the fingers have moved 5
-- units on either axis; then the first gesture, in the order the file adds them, whose direction is that way, its axis,
-- or "swipe" gets begin and update with that same event, update for each event after, and end when the fingers lift.
-- A gesture an earlier one overshadows is refused when it is added, as Hyprland's addGesture does.
local tree = os.getenv("TACIT_TREE") or ((arg[0]:match("^(.*)/[^/]*$") or ".") .. "/..")
local file = tree .. "/session/hypr/hyprland/general.lua"

local failed = 0
local function check(name, ok, why)
    if ok then print("  ok    " .. name)
    else failed = failed + 1; print("  FAIL  " .. name .. (why and (": " .. why) or "")) end
end

-- TrackpadGestures.cpp: dirForString, and the axis each direction belongs to
local DIR = { swipe = "swipe", left = "left", l = "left", right = "right", r = "right", up = "up", u = "up", top = "up",
    t = "up", down = "down", d = "down", bottom = "down", b = "down", horizontal = "horizontal", horiz = "horizontal",
    vertical = "vertical", vert = "vertical", pinch = "pinch", pinchin = "pinchin", zoomin = "pinchin",
    pinchout = "pinchout", zoomout = "pinchout" }
local AXIS = { up = "vertical", down = "vertical", vertical = "vertical", left = "horizontal", right = "horizontal",
    horizontal = "horizontal", swipe = "swipe", pinch = "pinch", pinchin = "pinch", pinchout = "pinch" }

local gestures, refused, sent, window = {}, {}, {}, { fullscreen = 0 }
-- anything the file calls that this replay does not care about: callable, indexable, and itself again
local any = setmetatable({}, { __call = function(t) return t end, __index = function(t) return t end })
hl = setmetatable({
    gesture = function(spec)
        local dir = DIR[tostring(spec.direction):lower()]
        local axis = AXIS[dir]
        for _, g in ipairs(gestures) do
            if g.fingers == spec.fingers and (g.dir == axis or g.dir == dir
                or ((axis == "vertical" or axis == "horizontal") and g.dir == "swipe")) then
                table.insert(refused, string.format("%d-finger %s, shadowed by %s", spec.fingers, dir, g.dir))
                return
            end
        end
        table.insert(gestures, { fingers = spec.fingers, dir = dir, action = spec.action })
    end,
    dispatch = function(c) table.insert(sent, c) end,
    dsp = setmetatable({ exec_cmd = function(c) return c end, global = function(c) return "global " .. c end }, { __index = function() return any end }),
    get_active_window = function() return window end,
    get_monitors = function() return {} end,
}, { __index = function() return any end })
HOME = "/home/someone"
is_file_exists = function() return false end
dofile(file)

-- one swipe: the deltas as libinput hands them over, fingers on the pad, and whether it ended cancelled
local function swipe(deltas, fingers, cancelled)
    sent = {}
    local tx, ty, active, failedFind = 0, 0, nil, false
    for _, d in ipairs(deltas) do
        local ev = { delta = { x = d[1], y = d[2] }, fingers = fingers }
        if not failedFind then
            tx, ty = tx + d[1], ty + d[2]
            if active or math.abs(tx) >= 5 or math.abs(ty) >= 5 then
                if not active then
                    local axis = math.abs(tx) > math.abs(ty) and "horizontal" or "vertical"
                    local dir = axis == "horizontal" and (tx < 0 and "left" or "right") or (ty < 0 and "up" or "down")
                    for _, g in ipairs(gestures) do
                        if (g.dir == axis or g.dir == dir or g.dir == "swipe") and g.fingers == fingers then active = g; break end
                    end
                    if not active then failedFind = true
                    elseif type(active.action) == "table" and active.action.start then active.action.start(ev) end
                end
                if active and type(active.action) == "table" and active.action.update then active.action.update(ev) end
            end
        end
    end
    if active then
        if type(active.action) == "table" and active.action.finish then active.action.finish({ cancelled = cancelled or false })
        elseif type(active.action) == "function" then active.action()            -- the legacy form: called at the end
        elseif type(active.action) == "string" then table.insert(sent, "hyprland's own " .. active.action) end
    end
    return sent[1] or "nothing"
end

local function rep(n, x, y, t) t = t or {} for _ = 1, n do t[#t + 1] = { x, y } end return t end
local function sideways(t) table.insert(t, 1, { -3, -1 }) table.insert(t, 1, { -4, -1 }) return t end
local function wobbly(n, y, w) local t = sideways({}) for i = 1, n do t[#t + 1] = { (i % 2 == 0) and w or -w, y } end return t end

local back, hide = "hyprctl tacitgrip unside active", "hyprctl tacitgrip hide active"
local cases = {
    { "a straight swipe up, 300", rep(30, 0, -10), back },
    { "up, setting off sideways, wobbling 5 a step", wobbly(30, -10, 5), back },
    { "up, setting off sideways, drifting left 4 a step", sideways(rep(30, -4, -10)), back },
    { "a straight swipe down", rep(20, 0, 10), hide },
    { "a straight swipe left", rep(20, -10, 0), "hyprctl tacitgrip left active" },
    { "a straight swipe right", rep(20, 10, 0), "hyprctl tacitgrip right active" },
    { "a brush up, 60", rep(6, 0, -10), "nothing" },
    { "a swipe up taken back before lifting", rep(15, 0, 10, rep(15, 0, -10)), "nothing" },
}

print("Touchpad gestures (session/hypr/hyprland/general.lua, as Hyprland 0.56.2 feeds them)")
check("Hyprland accepts every gesture the file adds", #refused == 0, table.concat(refused, "; "))
for _, c in ipairs(cases) do
    local got = swipe(c[2], 3)
    check(string.format("three fingers, %s: %s", c[1], c[3]), got == c[3], "got " .. got)
end
local got = swipe(rep(30, 0, -10), 3, true)
check("three fingers, a swipe up that ends cancelled: nothing", got == "nothing", "got " .. got)
window = { fullscreen = 1 }
got = swipe(rep(30, 0, -10), 3)
check("three fingers up on a window filling the screen: " .. "hyprctl tacitgrip fill active", got == "hyprctl tacitgrip fill active", "got " .. got)
window = { fullscreen = 0 }
got = swipe(rep(30, 0, -10), 4)
check("four fingers up: the overview", got == "global quickshell:overviewWorkspacesToggle", "got " .. got)

os.exit(failed == 0 and 0 or 1)
