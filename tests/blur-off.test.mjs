// With the compositor's blur off (Settings > Appearance's switch, Game mode, a line of the person's own), nothing of
// Tacit's is see-through over the nothing behind it. Appearance.blurBehind, read from Hyprland's answer as the tree's
// own code parses it, decides Tacit.windowSeeThrough, the Files window's body and the frost; and Hyprland's own start
// (session/hypr/hyprland.lua, with the shipped hyprland/general.lua under it) leaves windows not in use unfaded. For
// that part the switch and Game mode run as the tree has them, through HyprlandConfig.qml's set/setMany/reset and
// hyprconfigurator.py, into a shellOverrides/main.lua of the test's own that each start reads, as a restart would.
import { spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { adapterDefaults, inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

const app = read("modules/common/Appearance.qml");
const tacit = read("modules/common/Tacit.qml");
const files = read("modules/ii/files/FilesWindow.qml");
const ColorUtils = { transparentize: (c, amount) => amount };
const expr = (src, at) => (at < 0 ? null : readExpression(src, src.indexOf(":", at) + 1).expr);

console.log("== Hyprland's answer for decoration:blur:enabled (Appearance.qml)");
const blurBehindExpr = qmlProperty(app, "blurBehind");
const query = app.indexOf("id: blurQuery");
// blurBehind after the query's handler has read this answer of hyprctl getoption -j (none: before any answer)
function reads(text) {
  if (!blurBehindExpr || query < 0) return "Appearance.qml has no blurBehind read from Hyprland";
  const root = { blurAnswer: undefined };
  if (text !== undefined) {
    const open = app.indexOf("{", app.indexOf("onStreamFinished:", query));
    inScope({ root, text }, "", app.slice(open + 1, matchBrace(app, open)))();
  }
  return inScope({ root }, "", `return (${blurBehindExpr});`)();
}
check('{"bool": false} (Hyprland 0.56 and later) is the blur off', reads('{"option": "decoration:blur:enabled", "bool": false, "set": true}') === false);
check('{"int": 0} (older ones) is the blur off', reads('{"option": "decoration:blur:enabled", "int": 0, "set": true}') === false);
check("true and 1 are the blur on", reads('{"bool": true, "set": false}') === true && reads('{"int": 1}') === true);
check("before the first answer the blur counts as on, so nothing flashes solid at start", reads(undefined) === true);
check("so does an answer that is not one (no Hyprland, no hyprctl)", reads("HYPRLAND_INSTANCE_SIGNATURE not set!") === true);
const reloaded = qmlFunction(app, "onReloaded");
const q = { running: false };
if (reloaded) inScope({ blurQuery: q }, reloaded.params, reloaded.body)();
check("it is asked again at every config reload", q.running);

console.log("== the grounds with the blur off and on");
// Appearance.solid as the tree has it, See-through on (Frosted or Clear) unless said; before 1.2.19 each ground read
// blurBehind itself
const solidExpr = qmlProperty(app, "solid");
const solidOf = (blurBehind, enable = true) => solidExpr && inScope({ root: { blurBehind },
  Config: { options: { appearance: { transparency: { enable } } } } }, "", `return (${solidExpr});`)();
const clearSeeThrough = Number(qmlProperty(tacit, "clearSeeThrough"));
const seeThroughExpr = (() => {
  const at = tacit.lastIndexOf("property real windowSeeThrough:");
  return tacit.slice(tacit.indexOf(":", at) + 1, tacit.indexOf("\n\n", at));
})();
const seeThrough = (blurBehind, transparency) => inScope({ Appearance: { blurBehind, solid: solidOf(blurBehind, transparency.enable),
  seeThroughScale: 0.8 }, Config: { options: { appearance: { transparency } } }, root: { clearSeeThrough } }, "", `return (${seeThroughExpr});`)();
const frosted = { enable: true, automatic: true, backgroundTransparency: 0.4 };
const clear = { enable: true, automatic: false, backgroundTransparency: 0.25 };
const solid = { enable: false, automatic: true, backgroundTransparency: 0.4 };
check("Tacit.windowSeeThrough: none with the blur off, Frosted or Clear", seeThrough(false, frosted) === 0 && seeThrough(false, clear) === 0,
  `${seeThrough(false, frosted)}, ${seeThrough(false, clear)}`);
check("with the blur on as before: Frosted 0.15 and Clear its own amount, by the wallpaper's scale; Solid none",
  Math.abs(seeThrough(true, frosted) - 0.12) < 1e-9 && Math.abs(seeThrough(true, clear) - 0.2) < 1e-9 && seeThrough(true, solid) === 0,
  `${seeThrough(true, frosted)}, ${seeThrough(true, clear)}, ${seeThrough(true, solid)}`);
const bodyExpr = expr(files, files.indexOf("color:", files.indexOf("id: body")));
const body = blurBehind => inScope({ ColorUtils, Appearance: { blurBehind, solid: solidOf(blurBehind) }, win: { termBase: "#101418" } }, "",
  `return (${bodyExpr});`)();
check("the Files window's body is solid with the blur off, 0.15 see-through with it on", body(false) === 0 && body(true) === 0.15,
  `${body(false)}, ${body(true)}`);
const frostExpr = expr(app, app.indexOf("property color colPanelFrost:"));
const frost = blurBehind => inScope({ ColorUtils, m3colors: { m3surfaceContainerHigh: "#2a2e33" },
  root: { blurBehind, solid: solidOf(blurBehind), seeThroughScale: 0.8 } }, "", `return (${frostExpr});`)();
check("the frost is solid with the blur off, 0.24 by the wallpaper's scale with it on", frost(false) === 0 && Math.abs(frost(true) - 0.192) < 1e-9,
  `${frost(false)}, ${frost(true)}`);

console.log("== windows not in use after the switch and Game mode, at Hyprland's next start (hyprland.lua)");
const dir = mkdtempSync(join(tmpdir(), "tacit-blur-off-"));
try {
  const home = join(dir, "home"), state = join(dir, "state");
  const overrides = join(home, ".config/hypr/hyprland/shellOverrides/main.lua");
  const custom = join(home, ".config/hypr/custom/general.lua");
  mkdirSync(join(state, "quickshell/user/generated"), { recursive: true });
  mkdirSync(join(home, ".config/hypr/custom"), { recursive: true });
  // a bright wallpaper: the glass's see-through at 0.8 (scripts/colors/seethrough.py)
  writeFileSync(join(state, "quickshell/user/generated/seethrough.json"), '{"scale": 0.8}');

  // HyprlandConfig.qml's writers as the tree has them, each run done at once as its queue would
  const hcSrc = read("services/HyprlandConfig.qml");
  const writer = { push: args => spawnSync("python3", ["-I", ...args.slice(1)], { stdio: "ignore" }) };
  const hcRoot = { configuratorScriptPath: join(tree, "scripts/hyprland/hyprconfigurator.py"), shellOverridesPath: overrides };
  const HyprlandConfig = {};
  for (const name of ["set", "setMany", "reset"]) {
    const f = qmlFunction(hcSrc, name);
    HyprlandConfig[name] = inScope({ writer, root: hcRoot }, f.params.replace(/:\s*\w+/g, ""), f.body);
  }
  const options = adapterDefaults(read("modules/common/Config.qml"));
  const Config = { options };
  const scope = { Config, HyprlandConfig, Quickshell: { execDetached() {} } };
  // a control's handler in tacit-settings.qml, found by its label
  const settings = read("tacit-settings.qml");
  const handler = (label, on) => inScope(scope, "", `return (${expr(settings, settings.indexOf(on, settings.indexOf(`label: "${label}"`)))});`)();
  const blurSwitch = handler("Blur behind see-through windows", "onToggled:");
  const notInUse = handler("Windows not in use", "onMoved:");
  // the Game mode tile, on or off as Hyprland says animations are
  const gameSrc = read("modules/common/models/quickToggles/GameModeToggle.qml");
  const gameRoot = { toggled: false };
  const gameAction = inScope({ ...scope, root: gameRoot }, "", `return (${expr(gameSrc, gameSrc.indexOf("mainAction:"))});`)();
  const gameMode = on => { gameRoot.toggled = !on; gameAction(); };

  // Hyprland starting on these files: decoration's values as hyprland.lua leaves them. hyprland/general.lua runs as
  // shipped, the person's main.lua and custom/general.lua as written; Tacit's other modules are not about this.
  const start = join(dir, "start.lua");
  writeFileSync(start, `local tree, home = arg[1], arg[2]
local store = {}
local function put(prefix, t)
    for k, v in pairs(t) do
        if type(v) == "table" then put(prefix .. k .. ":", v) else store[prefix .. k] = v end
    end
end
local any = setmetatable({}, { __call = function(t) return t end, __index = function(t) return t end })
hl = setmetatable({
    config = function(t) put("", t) end,
    get_config = function(k) return store[k] end,
    get_devices = function() return {} end,
    get_monitors = function() return {} end,
    -- with the blur off or Solid: every window drawn without the rules' fade (opaque on all), and only the apps that paint
    -- their own see-through ground drawn without their alpha (force_rgbx on those; on all, menus' shadows went black)
    window_rule = function(t)
        if not t.match then return end
        if t.match.class == ".*" then
            if t.opaque then store["opaque_all"] = true end
            if t.force_rgbx then store["rgbx_all"] = true end
        elseif t.force_rgbx then store["rgbx_class"] = t.match.class end
    end,
}, { __index = function(_, k) if tostring(k):match("^__tacit") then return nil end return any end })
HOME = home
is_file_exists = function(p) local f = io.open(p, "r"); if f then f:close() end; return f ~= nil end
local files = { ["hyprland.general"] = tree .. "/session/hypr/hyprland/general.lua",
    ["hyprland.shellOverrides.main"] = home .. "/.config/hypr/hyprland/shellOverrides/main.lua",
    ["custom.general"] = home .. "/.config/hypr/custom/general.lua" }
package.searchers = { function(name)
    local path = files[name]
    if not path then return function() return true end end
    return function() return assert(loadfile(path))() end
end }
dofile(tree .. "/session/hypr/hyprland.lua")
io.stderr:write("RGBX " .. tostring(store["rgbx_class"]) .. "\\n")
io.stderr:write(string.format("RESULT %s %s %s\\n", tostring(store["decoration:inactive_opacity"]), tostring(store["decoration:blur:enabled"]), tostring((store["opaque_all"] == true and store["rgbx_all"] ~= true and store["rgbx_class"] ~= nil))))
`);
  function hyprland() {
    const r = spawnSync("lua", [start, tree, home], { encoding: "utf8", env: { PATH: process.env.PATH, HOME: home, XDG_STATE_HOME: state } });
    const m = /RESULT (\S+) (\S+) (\S+)/.exec(r.stderr ?? "");
    const failed = `${r.stdout}${r.stderr}`.split("\n").filter(l => /FAILED|error/i.test(l)).join("; ");
    const rgbx = /RGBX (\S+)/.exec(r.stderr ?? "")?.[1];
    return m ? { inactive: +m[1], blur: m[2], solid: m[3], rgbx, why: failed } : { why: failed || "hyprland.lua did not finish" };
  }
  function opacity(name, want, blur) {
    const h = hyprland();
    check(name, h.inactive !== undefined && Math.abs(h.inactive - want) < 1e-6 && (blur === undefined || h.blur === blur),
      `inactive_opacity ${h.inactive}, blur ${h.blur}${h.why ? `; ${h.why}` : ""}`);
    // and every window drawn solid while the blur is off (a terminal's own see-through ground too), none while it is on
    if (blur !== undefined)
      check(`${name}: every window ${blur === "false" ? "solid" : "as it draws itself"}`, h.solid === (blur === "false" ? "true" : "false"), `solid rule ${h.solid}`);
    // only the apps that paint their own see-through ground lose their alpha: a browser's menu or a GTK window keeps the
    // see-through edge its shadow is drawn in (Discord, OYINOS, 2026-11-22: Brave's bookmark folder opened in a black box)
    if (blur === "false") {
      const full = c => { try { return new RegExp(`^(?:${h.rgbx})$`).test(c); } catch { return false; } };
      check(`${name}: foot, kitty and Thyris drawn without their own alpha, Brave's menus and GTK's shadows with theirs`,
        ["foot", "footclient", "kitty", "browser-cef"].every(full) && !["brave-browser", "org.gnome.Nautilus", "chromium", "discord"].some(full),
        `force_rgbx on ${h.rgbx}`);
    }
  }

  // 0.82 as shipped, with this wallpaper's scale on its see-through: 1 - 0.18 * 0.8
  opacity("as installed: windows not in use at the shipped 0.82, scaled by the wallpaper", 0.856, "true");
  blurSwitch(false);
  opacity("the switch turned off: the blur is off and windows not in use are not faded", 1, "false");
  notInUse(70);
  opacity("Windows not in use moved meanwhile: still not faded", 1, "false");
  blurSwitch(true);
  opacity("the switch on again: the blur is back, with the 70% just chosen, scaled", 0.76, "true");
  gameMode(true);
  opacity("Game mode on: the blur is off and windows not in use are not faded", 1, "false");
  gameMode(false);
  opacity("Game mode off: exactly as before it, 70% scaled", 0.76, "true");
  blurSwitch(false);
  gameMode(true);
  gameMode(false);
  opacity("Game mode on and off with the switch off: the blur stays off and windows unfaded", 1, "false");
  rmSync(overrides);
  writeFileSync(custom, "hl.config({ decoration = { blur = { enabled = false } } })\n");
  opacity("the blur turned off by a line of the person's own (custom/general.lua): windows not in use not faded", 1, "false");
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
