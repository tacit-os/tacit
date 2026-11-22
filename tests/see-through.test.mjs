// Settings > Appearance's See-through, Clear, Frosted or Solid, wherever it shows: Tacit's apps (Tacit.windowSeeThrough),
// the notch's and panels' frost, the Files window, the terminals' alpha (applycolor.sh) and Hyprland's windows
// (hyprland.lua over the shipped hyprland/general.lua). Each look is picked with Settings' own setGlass; the shell's
// trigger (shell.qml) runs glass-look.sh, here in a folder of its own with applycolor.sh and hyprctl stood in for, and
// Hyprland starts on the file it leaves, as a reload or the next login would. Solid is solid everywhere, Frosted is as it
// was, and Clear lets 0.3 through at most, whatever an older version stored.
import { spawnSync } from "child_process";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { adapterDefaults, inScope, matchBrace, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

const app = read("modules/common/Appearance.qml");
const tacit = read("modules/common/Tacit.qml");
const files = read("modules/ii/files/FilesWindow.qml");
const settings = read("tacit-settings.qml");
const shell = read("shell.qml");
const applycolor = read("scripts/colors/applycolor.sh");
const ColorUtils = { transparentize: (c, amount) => amount };
const expr = (src, at) => (at < 0 ? null : readExpression(src, src.indexOf(":", at) + 1).expr);
const near = (a, b) => typeof a === "number" && Math.abs(a - b) < 1e-6;
const SCALE = 0.8; // a bright wallpaper's (scripts/colors/seethrough.py)

// the settings as Config.qml declares them (Frosted); the looks picked as Settings' tiles do
const options = adapterDefaults(read("modules/common/Config.qml"));
const transparency = options.appearance.transparency;
const Config = { options, ready: true };
const Tacit = { clearSeeThrough: Number(qmlProperty(tacit, "clearSeeThrough")), frostedSeeThrough: Number(qmlProperty(tacit, "frostedSeeThrough")) };
const setGlassFn = qmlFunction(settings, "setGlass");
// the blur as Hyprland has it (Windows' switch, Game mode) and what Settings asked of it
const Appearance = { blurBehind: true };
const blurAsked = [];
const HyprlandConfig = { set: (k, v) => blurAsked.push(`${k}=${v}`) };
const setGlass = kind => inScope({ Config, Tacit, Appearance, HyprlandConfig }, setGlassFn.params, setGlassFn.body)(kind);

// the grounds with the blur on, as every process draws them: Appearance.solid (none before 1.2.19), the apps' window,
// the frost, the Files window's body
const solidExpr = qmlProperty(app, "solid");
const windowAt = tacit.lastIndexOf("property real windowSeeThrough:");
const windowExpr = tacit.slice(tacit.indexOf(":", windowAt) + 1, tacit.indexOf("\n\n", windowAt));
function grounds() {
  const root = { blurBehind: true, seeThroughScale: SCALE };
  if (solidExpr) root.solid = inScope({ root, Config }, "", `return (${solidExpr});`)();
  const win = inScope({ Appearance: root, Config, root: Tacit }, "", `return (${windowExpr});`)();
  const frost = inScope({ ColorUtils, m3colors: { m3surfaceContainerHigh: "#2a2e33" }, root }, "",
    `return (${expr(app, app.indexOf("property color colPanelFrost:"))});`)();
  const body = inScope({ ColorUtils, Appearance: root, win: { termBase: "#101418" }, Tacit: { windowSeeThrough: win } }, "",
    `return (${expr(files, files.indexOf("color:", files.indexOf("id: body")))});`)();
  return { win, frost, body };
}

const dir = mkdtempSync(join(tmpdir(), "tacit-see-through-"));
try {
  const home = join(dir, "home"), config = join(dir, "config"), state = join(dir, "state"), bin = join(dir, "bin");
  const generated = join(state, "quickshell/user/generated"), log = join(dir, "calls.log");
  for (const d of [home, join(config, "illogical-impulse"), generated, bin, join(dir, "scripts/colors")]) mkdirSync(d, { recursive: true });
  writeFileSync(join(generated, "seethrough.json"), `{"scale": ${SCALE}}`);
  writeFileSync(join(generated, "material_colors.scss"), "$term0: #101418;\n");
  const writeConfig = () => writeFileSync(join(config, "illogical-impulse/config.json"), JSON.stringify(options));

  // the terminals' alpha as applycolor.sh works it out, on the settings as they are now
  const alphaLines = applycolor.slice(applycolor.indexOf("term_seethrough="), applycolor.indexOf("\n", applycolor.indexOf("term_alpha=")));
  function terminalAlpha() {
    writeConfig();
    const r = spawnSync("bash", ["-c", `STATE_DIR='${join(state, "quickshell")}'; XDG_CONFIG_HOME='${config}'\n${alphaLines}\necho "$term_alpha"`],
      { encoding: "utf8", env: { PATH: process.env.PATH } });
    return Number(r.stdout.trim());
  }

  // glass-look.sh, with applycolor.sh beside it and hyprctl stood in for: what it wrote and what it ran
  const script = join(dir, "scripts/colors/glass-look.sh");
  const theirs = join(tree, "scripts/colors/glass-look.sh");
  if (existsSync(theirs)) copyFileSync(theirs, script);
  writeFileSync(join(dir, "scripts/colors/applycolor.sh"), `#!/bin/sh\necho applycolor >> '${log}'\n`);
  writeFileSync(join(bin, "hyprctl"), `#!/bin/sh\necho "hyprctl $*" >> '${log}'\n`);
  chmodSync(join(dir, "scripts/colors/applycolor.sh"), 0o755); chmodSync(join(bin, "hyprctl"), 0o755);
  const env = { HOME: home, XDG_CONFIG_HOME: config, XDG_STATE_HOME: state, PATH: `${bin}:/usr/bin:/bin` };
  const lookFile = () => { try { return JSON.parse(readFileSync(join(generated, "glass.json"), "utf8")).look; } catch (e) { return null; } };
  function glassLook(...args) {
    writeConfig();
    writeFileSync(log, "");
    const r = existsSync(script) ? spawnSync("bash", [script, ...args], { encoding: "utf8", env, timeout: 20000 }) : { status: "no scripts/colors/glass-look.sh" };
    const calls = readFileSync(log, "utf8");
    return { status: r.status, look: lookFile(), applycolor: calls.includes("applycolor"), reload: /^hyprctl reload/m.test(calls),
      said: `exit ${r.status}, glass.json ${lookFile()}, ran: ${calls.trim().replace(/\n/g, "; ") || "nothing"}` };
  }

  // Hyprland starting: decoration's values and whether a rule draws every window solid, as hyprland.lua leaves them.
  // hyprland/general.lua runs as shipped; the other modules are not about this.
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
package.searchers = { function(name)
    if name ~= "hyprland.general" then return function() return true end end
    return function() return assert(loadfile(tree .. "/session/hypr/hyprland/general.lua"))() end
end }
dofile(tree .. "/session/hypr/hyprland.lua")
io.stderr:write("RGBX " .. tostring(store["rgbx_class"]) .. "\\n")
io.stderr:write(string.format("RESULT %s %s\\n", tostring(store["decoration:inactive_opacity"]), tostring((store["opaque_all"] == true and store["rgbx_all"] ~= true and store["rgbx_class"] ~= nil))))
`);
  function hyprland() {
    const r = spawnSync("lua", [start, tree, home], { encoding: "utf8", timeout: 20000,
      env: { PATH: process.env.PATH, HOME: home, XDG_STATE_HOME: state } });
    const m = /RESULT (\S+) (\S+)/.exec(r.stderr ?? "");
    return m ? { inactive: +m[1], solid: m[2] === "true", said: `inactive_opacity ${m[1]}, solid rule ${m[2]}` }
      : { said: `${r.stdout}${r.stderr}`.trim() || "hyprland.lua did not finish" };
  }
  const say = g => `apps ${g.win}, frost ${g.frost}, Files ${g.body}`;

  console.log("== the shell carries the look to Hyprland and the terminals (shell.qml)");
  const ran = [];
  const Quickshell = { execDetached: a => ran.push(a.join(" ")), shellPath: p => join(tree, p) };
  const ready = qmlFunction(shell, "onReadyChanged");
  inScope({ Config, WM: { compositor: "hyprland" }, autostartProc: {}, Quickshell }, ready.params, ready.body)();
  check("at its start it runs glass-look.sh --start", ran.some(a => a.endsWith("scripts/colors/glass-look.sh --start")), ran.join("; "));
  const watchAt = shell.indexOf("target: Config.options.appearance.transparency");
  const watchOpen = watchAt < 0 ? -1 : shell.lastIndexOf("{", watchAt);
  const watch = watchOpen < 0 ? "" : shell.slice(watchOpen, matchBrace(shell, watchOpen) + 1);
  check("it watches the look only once config.json is read", expr(watch, watch.indexOf("enabled:")) === "Config.ready", watch ? "" : "no watch");
  for (const name of ["onEnableChanged", "onAutomaticChanged", "onBackgroundTransparencyChanged"]) {
    const f = watch && qmlFunction(watch, name);
    const id = f && /(\w+)\.restart\(\)/.exec(f.body)?.[1];
    const at = id ? shell.indexOf(`id: ${id}`) : -1;
    ran.length = 0;
    if (at >= 0) inScope({ Quickshell }, "", expr(shell, shell.indexOf("onTriggered:", at)))();
    check(`${name.slice(2, -7)} changed: glass-look.sh runs, after Config has written the file (50 ms)`,
      ran.some(a => a.endsWith("scripts/colors/glass-look.sh")) && Number(expr(shell, shell.indexOf("interval:", at))) > 50, ran.join("; "));
  }

  console.log("== Frosted, as installed: as before");
  let g = glassLook("--start");
  check("the shell's first start writes the look down for Hyprland", g.status === 0 && g.look === "frosted", g.said);
  check("and gives it to the terminals; Hyprland, which drew Frosted already, is not reloaded", g.applycolor && !g.reload, g.said);
  g = glassLook("--start");
  check("the next start does nothing", g.status === 0 && !g.applycolor && !g.reload, g.said);
  let gr = grounds();
  check("apps and Files 0.1 and the frost 0.24 by the wallpaper's scale", near(gr.win, 0.08) && near(gr.frost, 0.192) && near(gr.body, 0.08), say(gr));
  check("the terminals' alpha 92 (0.1 by the scale)", terminalAlpha() === 92, String(terminalAlpha()));
  let h = hyprland();
  check("Hyprland: windows not in use at the shipped 0.82 with the scale, none forced solid", near(h.inactive, 0.856) && h.solid === false, h.said);

  console.log("== Solid picked");
  setGlass("solid");
  g = glassLook();
  check("Hyprland is told and reloaded, the terminals given it", g.look === "solid" && g.reload && g.applycolor, g.said);
  gr = grounds();
  check("Tacit's apps, the frost and Files are solid", gr.win === 0 && gr.frost === 0 && gr.body === 0, say(gr));
  check("the terminals' alpha 100", terminalAlpha() === 100, String(terminalAlpha()));
  h = hyprland();
  check("Hyprland draws every window solid (the browsers' and terminals' fade too) and fades none not in use, the blur on",
    h.solid === true && h.inactive === 1, h.said);

  console.log("== back to Frosted");
  setGlass("frosted");
  g = glassLook();
  check("Hyprland is told and reloaded", g.look === "frosted" && g.reload && g.applycolor, g.said);
  h = hyprland();
  check("the solid rule is gone and windows not in use fade as before", h.solid === false && near(h.inactive, 0.856), h.said);
  gr = grounds();
  check("the grounds as before", near(gr.win, 0.08) && near(gr.frost, 0.192) && near(gr.body, 0.08), say(gr));

  console.log("== Clear");
  setGlass("clear");
  check("picked over the 0.4 stored by default it is 0.2, twice Frosted", near(transparency.backgroundTransparency, 0.2),
    String(transparency.backgroundTransparency));
  g = glassLook();
  check("the terminals are given it; Hyprland, the same for Clear as for Frosted, is not reloaded", g.look === "clear" && g.applycolor && !g.reload, g.said);
  h = hyprland();
  check("no window forced solid, windows not in use fade as on Frosted", h.solid === false && near(h.inactive, 0.856), h.said);
  gr = grounds();
  check("apps and Files 0.2 by the scale, clearer than Frosted; the frost as on Frosted",
    near(gr.win, 0.16) && near(gr.frost, 0.192) && near(gr.body, 0.16), say(gr));
  check("the terminals' alpha 84 (0.2 by the scale)", terminalAlpha() === 84, String(terminalAlpha()));
  // How clear went up to 60 % before 1.2.19
  transparency.backgroundTransparency = 0.5;
  gr = grounds();
  check("a 0.5 stored by an older version is held to 0.2 in the apps", near(gr.win, 0.16), say(gr));
  check("and in the terminals", terminalAlpha() === 84, String(terminalAlpha()));
  const seeThroughSetting = inScope({ Config, Tacit, Appearance }, "", `return (${qmlProperty(settings, "seeThroughSetting")});`)();
  const look = { glass: "clear" };
  look.clearAmount = inScope({ Config, Tacit, look, root: { seeThroughSetting } }, "", `return (${qmlProperty(settings, "clearAmount")});`)();
  const tiles = inScope({ look }, "", `return (${expr(settings, settings.indexOf("model:", settings.indexOf("id: glassRow")))});`)();
  const clearTile = tiles.find(t => t.kind === "clear");
  check("Settings' preview and Clear tile show 0.2, the tile blurred as real windows are",
    near(seeThroughSetting, 0.2) && near(clearTile?.see, 0.2) && clearTile?.blur === true, JSON.stringify(clearTile));
  const stepAt = settings.indexOf('label: "How clear"');
  const stepScope = { Config, Tacit, root: { seeThroughSetting } };
  const stepTo = inScope(stepScope, "", `return (${expr(settings, settings.indexOf("to:", stepAt))});`)();
  const stepValue = inScope(stepScope, "", `return (${expr(settings, settings.indexOf("value:", stepAt))});`)();
  check("How clear shows it as 20 % and goes no higher", stepValue === 20 && stepTo === 20, `${stepValue} % of at most ${stepTo} %`);
  setGlass("clear");
  check("Clear picked again over the 0.5 stores 0.2", near(transparency.backgroundTransparency, 0.2), String(transparency.backgroundTransparency));

  console.log("== Solid and away again by Clear, and a look changed while the shell was not running");
  setGlass("solid");
  g = glassLook();
  check("Solid: reloaded", g.look === "solid" && g.reload, g.said);
  setGlass("clear");
  g = glassLook();
  h = hyprland();
  check("Clear: reloaded, the solid rule gone", g.look === "clear" && g.reload && h.solid === false && near(h.inactive, 0.856), `${g.said}; ${h.said}`);
  setGlass("solid");
  g = glassLook("--start");
  h = hyprland();
  check("Solid set in config.json meanwhile: the shell's start writes it down and reloads Hyprland",
    g.look === "solid" && g.reload && g.applycolor && h.solid === true && h.inactive === 1, `${g.said}; ${h.said}`);

  console.log("== one setting with Windows' blur switch (Discord, OYINOS, 2026-11-22, on 1.2.19)");
  const glassOf = () => inScope({ Config, Appearance }, "", `return (${qmlProperty(settings, "glass")});`)();
  const previewOf = () => inScope({ Config, Tacit, Appearance }, "", `return (${qmlProperty(settings, "seeThroughSetting")});`)();
  setGlass("frosted");
  Appearance.blurBehind = false;
  check("with the blur off (the switch or Game mode) Solid shows as chosen and the preview is solid",
    glassOf() === "solid" && previewOf() === 0, `${glassOf()}, preview ${previewOf()}`);
  blurAsked.length = 0;
  options.hyprland.decoration.blur.enabled = false;
  setGlass("clear");
  check("Clear picked then turns the blur on, as the switch does", blurAsked.join(" ") === "decoration:blur:enabled=1"
    && options.hyprland.decoration.blur.enabled === true && transparency.enable === true && transparency.automatic === false, blurAsked.join(" ") || "nothing asked");
  Appearance.blurBehind = true;
  check("and with it on, Clear shows as chosen", glassOf() === "clear", glassOf());
  blurAsked.length = 0;
  setGlass("frosted");
  check("Frosted picked with the blur on asks nothing of it", blurAsked.length === 0 && glassOf() === "frosted", blurAsked.join(" ") || glassOf());
  Appearance.blurBehind = false;
  blurAsked.length = 0;
  setGlass("solid");
  check("Solid picked leaves the blur as it is", blurAsked.length === 0 && transparency.enable === false, blurAsked.join(" ") || "");
  Appearance.blurBehind = true;

  console.log("== the first start with 1.2.20's amounts, over 1.2.19's glass.json");
  setGlass("frosted");
  writeFileSync(join(generated, "glass.json"), '{"look": "frosted"}\n');
  g = glassLook("--start");
  check("the terminals are given the new alpha; Hyprland, which draws Frosted already, is not reloaded",
    g.status === 0 && g.look === "frosted" && g.applycolor && !g.reload, g.said);
  g = glassLook("--start");
  check("the next start does nothing", g.status === 0 && !g.applycolor && !g.reload, g.said);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
