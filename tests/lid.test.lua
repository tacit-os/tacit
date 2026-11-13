-- The laptop's own screen and its lid (session/hypr/hyprland/general.lua), replayed the way Hyprland 0.56.2 runs it:
-- hl.monitor merges into the rule of that output's name, keeping the fields not given, and the screens are set again
-- after it (LuaBindingsConfigRules.cpp hlMonitor, MonitorRuleManager.cpp add); a screen turned off or on is a
-- monitor.removed or monitor.added (Monitor.cpp onDisconnect, onConnect), and hl.get_monitors lists only those on. A
-- reload starts Lua afresh with no rules, runs the config again, then the person's monitors.lua. The lid's state and
-- the connectors are what /proc/acpi/button/lid and /sys/class/drm say, through io.popen.
local tree = os.getenv("TACIT_TREE") or ((arg[0]:match("^(.*)/[^/]*$") or ".") .. "/..")
local file = tree .. "/session/hypr/hyprland/general.lua"

local failed = 0
local function check(name, ok, why)
    if ok then print("  ok    " .. name)
    else failed = failed + 1; print("  FAIL  " .. name .. (why and (": " .. why) or "")) end
end

-- the computer: its connectors, which are plugged in, and the lid
local world = { lid = "open", acpi = true, plugged = { ["eDP-1"] = true } }
local connectors = { "eDP-1", "HDMI-A-1", "DP-1" }
local rules, binds, handlers, on, calls
local refreshing, loading, turned = false, false, {}
local function enabled(name)
    if not world.plugged[name] then return false end
    local r = rules[name] or rules[""]
    return not (r and r.disabled)
end
-- Hyprland sets the screens again once a rule changes, and once a screen is plugged or unplugged; each turned on or off
-- tells the config, which may change a rule again
local function refresh()
    if refreshing or loading then return end
    refreshing = true
    for _ = 1, 20 do
        local changed = false
        for _, name in ipairs(connectors) do
            local now = enabled(name)
            if now ~= (on[name] or false) then
                on[name] = now
                changed = true
                table.insert(turned, name .. (now and " on" or " off"))
                for _, h in ipairs(handlers[now and "monitor.added" or "monitor.removed"] or {}) do h({ name = name }) end
            end
        end
        if not changed then break end
    end
    refreshing = false
end

local any = setmetatable({}, { __call = function(t) return t end, __index = function(t) return t end })
local function load(theirs)
    rules, binds, handlers, calls = {}, {}, {}, {}
    hl = setmetatable({
        monitor = function(t)
            local r = {}
            for k, v in pairs(rules[t.output] or {}) do r[k] = v end
            for k, v in pairs(t) do r[k] = v end
            rules[t.output] = r
            table.insert(calls, t.output .. (t.disabled == nil and "" or (t.disabled and " off" or " on")))
            refresh()
        end,
        get_monitors = function()
            local l = {}
            for _, name in ipairs(connectors) do if on[name] then l[#l + 1] = { name = name } end end
            return l
        end,
        bind = function(keys, fn, opts) binds[keys] = { fn = fn, opts = opts or {} } end,
        on = function(ev, fn) handlers[ev] = handlers[ev] or {}; table.insert(handlers[ev], fn) end,
    }, { __index = function() return any end })
    HOME = "/home/someone"
    is_file_exists = function() return false end
    loading = true
    dofile(file)
    -- the person's monitors.lua, loaded after; the screens are set once the whole config has run
    if theirs then hl.monitor(theirs) end
    loading = false
    refresh()
end
io.popen = function(cmd)
    local out = ""
    if cmd:find("/proc/acpi/button/lid", 1, true) and world.acpi then out = out .. "state:      " .. world.lid .. "\n" end
    if cmd:find("/sys/class/drm", 1, true) then
        out = out .. "card1\n"
        for _, name in ipairs(connectors) do out = out .. "card1-" .. name .. "\n" end
        out = out .. "renderD128\nversion\n"
    end
    return { read = function() return out end, close = function() return true end }
end
local function lidTo(state)
    world.lid = state
    local b = binds["switch:" .. (state == "closed" and "on" or "off") .. ":Lid Switch"]
    if b then b.fn() end
    refresh()
end
local function plug(name, yes)
    world.plugged[name] = yes or nil
    refresh()
end
local function shown() local l = {} for _, n in ipairs(connectors) do if on[n] then l[#l + 1] = n end end return table.concat(l, ", ") end

print("The laptop's own screen and its lid (session/hypr/hyprland/general.lua)")

-- a desk: the laptop, then a screen plugged in beside it
on = {}
local mine = { output = "eDP-1", mode = "2880x1800@120", position = "0x0", scale = 1.5 }
load(mine)
plug("HDMI-A-1", true)
check("lid open with a screen plugged in: both are on", on["eDP-1"] and on["HDMI-A-1"], shown())
calls = {}
lidTo("closed")
check("closing the lid with the other screen on turns the laptop's screen off", not on["eDP-1"] and on["HDMI-A-1"], shown())
check("with one rule change, which the screen going does not undo or repeat", #calls == 1 and calls[1] == "eDP-1 off", table.concat(calls, "; "))
check("at the lock screen too (the binds are locked ones)", binds["switch:on:Lid Switch"] and binds["switch:on:Lid Switch"].opts.locked == true
    and binds["switch:off:Lid Switch"].opts.locked == true)
calls = {}
lidTo("open")
check("opening it turns the laptop's screen on again", on["eDP-1"] and on["HDMI-A-1"] and #calls == 1, shown() .. " / " .. table.concat(calls, "; "))
check("with the mode, place and scale Settings gave it", rules["eDP-1"].scale == 1.5 and rules["eDP-1"].position == "0x0"
    and rules["eDP-1"].mode == "2880x1800@120" and not rules["eDP-1"].disabled)

-- closed, then the other screen unplugged: the laptop's own screen comes back rather than none at all
lidTo("closed")
plug("HDMI-A-1", false)
check("lid closed and the other screen unplugged: the laptop's screen is on again", on["eDP-1"] and not on["HDMI-A-1"], shown())
calls = {}
plug("DP-1", true)
check("lid closed and a screen plugged in: the laptop's screen goes off", not on["eDP-1"] and on["DP-1"] and #calls == 1, shown())

-- a reload with the lid closed (Settings' display changes reload): the laptop's screen never comes on
do
    turned = {}
    load(mine)
    check("a reload with the lid closed keeps it off, never on for a moment, with Settings' place for it", not on["eDP-1"] and on["DP-1"]
        and #turned == 0 and rules["eDP-1"].disabled == true and rules["eDP-1"].scale == 1.5, shown() .. " / turned " .. table.concat(turned, "; "))
    lidTo("open")
    check("and opening the lid after that reload brings it back", on["eDP-1"] and on["DP-1"] and rules["eDP-1"].scale == 1.5, shown())
end

-- no other screen: closing the lid is logind's (it suspends), and the screen stays as it is
plug("DP-1", false)
calls = {}
lidTo("closed")
check("lid closed with no other screen: the laptop's screen stays on, nothing changed", on["eDP-1"] and #calls == 0, shown())
lidTo("open")

-- no ACPI lid (a desktop, or a lid the kernel does not show there): nothing ever turns off
world.acpi = false
plug("HDMI-A-1", true)
lidTo("closed")
check("with no lid in /proc/acpi, the laptop's screen is never turned off", on["eDP-1"] and on["HDMI-A-1"], shown())
world.acpi = true
lidTo("open")

-- a person with no rule of their own for it: it comes back as the catch-all has it
on = {}
world.plugged = { ["eDP-1"] = true, ["HDMI-A-1"] = true }
load(nil)
lidTo("closed")
lidTo("open")
local r = rules["eDP-1"] or {}
check("with no rule of the person's, it comes back with nothing but the catch-all's mode, place and scale", on["eDP-1"]
    and r.mode == nil and r.position == nil and r.scale == nil and not r.disabled, shown())

os.exit(failed == 0 and 0 or 1)
