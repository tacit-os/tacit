-- hypridle's environment at login (session/hypr/hyprland/execs.lua): the file's hyprland.start commands read with a
-- pretend hl, and the one that starts hypridle's unit run as Hyprland runs an exec, under sh, with a pretend systemctl
-- that notes its calls. Every exec runs at once (the import of the session's variables further down races this one),
-- and a user unit keeps the environment it started with, so what this command imports before `start hypridle` is all
-- hypridle can count on: the variables hypridle.conf's commands use, hyprctl's, the unit's ConditionEnvironment
-- (WAYLAND_DISPLAY) and XDG_CONFIG_DIRS, where it finds Tacit's hypridle.conf (session/xdg, hyprland/env.lua).
local tree = os.getenv("TACIT_TREE") or ((arg[0]:match("^(.*)/[^/]*$") or ".") .. "/..")

local failed = 0
local function check(name, ok, why)
    if ok then print("  ok    " .. name)
    else failed = failed + 1; print("  FAIL  " .. name .. (why and (": " .. why) or "")) end
end
local function readAll(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("a")
    f:close()
    return s
end

local cmds, start = {}, nil
local any = setmetatable({}, { __call = function(t) return t end, __index = function(t) return t end })
hl = setmetatable({
    on = function(ev, fn) if ev == "hyprland.start" then start = fn end end,
    exec_cmd = function(c) cmds[#cmds + 1] = c end,
}, { __index = function() return any end })
dofile(tree .. "/session/hypr/hyprland/execs.lua")
if start then start() end

print("hypridle's environment at login (session/hypr/hyprland/execs.lua)")

local cmd
for _, c in ipairs(cmds) do if c:find("start hypridle", 1, true) then cmd = c end end
check("one of the login commands starts hypridle's unit", cmd ~= nil)

-- what hypridle needs: the variables its file names ($NAME, not its own $name = ...), and the fixed ones above
local conf = readAll(tree .. "/session/xdg/hypr/hypridle.conf"):gsub("#[^\n]*", "")
local own, need = {}, { WAYLAND_DISPLAY = true, XDG_CONFIG_DIRS = true }
for name in conf:gmatch("%$([%w_]+)%s*=") do own[name] = true end
for name in conf:gmatch("%$([%w_]+)") do if not own[name] then need[name] = true end end
if conf:find("hyprctl", 1, true) then need.HYPRLAND_INSTANCE_SIGNATURE = true end

if cmd then
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p " .. dir .. "/bin")
    local function tool(name, body)
        local f = assert(io.open(dir .. "/bin/" .. name, "w"))
        f:write("#!/bin/bash\n" .. body .. "\n")
        f:close()
        os.execute("chmod +x " .. dir .. "/bin/" .. name)
    end
    tool("systemctl", 'echo "$*" >> ' .. dir .. "/calls")
    tool("python3", "exit 0")
    -- never the live USB's branch, whatever computer the test runs on
    local run = cmd:gsub("/run/archiso", dir .. "/no-archiso")
    local f = assert(io.open(dir .. "/cmd", "w"))
    f:write(run)
    f:close()
    os.execute("env PATH=" .. dir .. "/bin:/usr/bin:/bin TACIT_SHELL=/usr/share/tacit/shell sh " .. dir .. "/cmd >/dev/null 2>&1")
    local calls = io.open(dir .. "/calls", "r")
    local log = calls and calls:read("a") or ""
    if calls then calls:close() end
    os.execute("rm -rf " .. dir)

    local imported, started = {}, false
    for line in log:gmatch("[^\n]+") do
        if line:find("start hypridle", 1, true) then started = true; break end
        local vars = line:match("^%-%-user import%-environment (.*)$")
        if vars then for v in vars:gmatch("%S+") do imported[v] = true end end
    end
    local missing = {}
    for name in pairs(need) do if not imported[name] then missing[#missing + 1] = name end end
    table.sort(missing)
    check("the unit is started", started, "systemctl was asked: " .. log:gsub("\n", "; "))
    check("everything hypridle.conf's commands and the unit need is imported in the same command, before the start",
        started and #missing == 0, "not imported before the start: " .. table.concat(missing, " "))
end

os.exit(failed == 0 and 0 or 1)
