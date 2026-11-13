// Settings > Keyboard & touchpad > Dictation key (tacit-settings.qml, session/hypr/tacit/keybinds.lua): Settings' key
// properties and setFlowKey() run under node; the command it starts runs under bash with the tree's managed_block.py on a
// custom/variables.lua in a folder of its own (a pretend hyprctl); then that file and Tacit's keybinds.lua run under lua
// with a stand-in hl, which says where quickshell:flowHold is bound, in the main keys and in the flow submap. The row
// shows on every install with Flow, and a key chosen there takes the Copilot key's place, not one beside it.
import { spawnSync } from "child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the dictation key (tacit-settings.qml, session/hypr/tacit/keybinds.lua)");
const app = read("tacit-settings.qml");
const dir = mkdtempSync(join(tmpdir(), "tacit-flow-key-"));
const variables = join(dir, "config/hypr/custom/variables.lua");
mkdirSync(join(dir, "bin"), { recursive: true });
writeFileSync(join(dir, "bin/hyprctl"), "#!/bin/sh\nexit 0\n");
chmodSync(join(dir, "bin/hyprctl"), 0o755);

// Settings' root as far as the key goes, with its FileViews in memory
const root = { flowKeyChosen: "", flowKeyOld: "" };
const prop = name => { const e = qmlProperty(app, name); return e === null ? undefined : inScope({ root }, "", `return (${e});`)(); };
root.flowDefaultKey = prop("flowDefaultKey");
const key = () => inScope({ root }, "", `return (${qmlProperty(app, "flowKey")});`)();
const legacy = { saved: null, text() { return this.saved ?? ""; }, setText(t) { this.saved = t; } };
const varsAt = app.indexOf("id: customVariables");
const varsLoaded = varsAt < 0 ? null : readExpression(app, app.indexOf("onLoaded:", varsAt) + "onLoaded:".length).expr;
const customVariables = { text: () => existsSync(variables) ? readFileSync(variables, "utf8") : "" };
function pick(k) {
  const f = qmlFunction(app, "setFlowKey");
  let argv = null;
  inScope({ root, customKeybinds: legacy, Quickshell: { execDetached: a => { argv = a; } }, Directories: { scriptPath: join(tree, "scripts"), config: join(dir, "config") },
    FileUtils: { trimFileProtocol: p => p } }, f.params, f.body)(k);
  if (argv) {
    const r = spawnSync(argv[0], argv.slice(1), { encoding: "utf8", env: { PATH: `${join(dir, "bin")}:${process.env.PATH}`, HOME: dir } });
    if (r.status !== 0) throw new Error(r.stderr);
  }
  if (varsLoaded) inScope({ root, customVariables }, "", `${varsLoaded};`)();
}
// where Hyprland binds flowHold, from the person's variables.lua and Tacit's keybinds.lua
function bound() {
  const driver = join(dir, "driver.lua");
  writeFileSync(driver, `
local out, submap = {}, nil
local any = setmetatable({}, { __call = function(t) return t end, __index = function(t) return t end })
hl = setmetatable({
  bind = function(keys, d) if d == "quickshell:flowHold" then out[#out + 1] = (submap or "main") .. "=" .. keys end; return any end,
  dsp = setmetatable({ global = function(n) return n end }, { __index = function() return function() return any end end }),
  define_submap = function(name, fn) submap = name; fn(); submap = nil end,
}, { __index = function() return function() return any end end })
local f = io.open(arg[1]); if f then f:close(); dofile(arg[1]) end
dofile(arg[2])
print(table.concat(out, ";"))`);
  const r = spawnSync("lua", [driver, variables, join(tree, "session/hypr/tacit/keybinds.lua")], { encoding: "utf8" });
  return (r.stdout || r.stderr).trim();
}

try {
  check("on an install, the row has a key to show: the Copilot key", key() === "SUPER + SHIFT + F23", JSON.stringify(key()));
  const row = app.slice(app.lastIndexOf("ChoiceRow {", app.indexOf('label: "Dictation key"')), app.indexOf('label: "Dictation key"'));
  check("and the row is not hidden for want of one", !/visible:\s*root\.flowKey/.test(row), row.trim());
  check("Tacit binds the Copilot key, in the main keys and the flow submap", bound() === "main=SUPER + SHIFT + F23;flow=SUPER + SHIFT + F23", bound());
  pick("SUPER + ALT + D");
  check("Super + Alt + D is kept and read back", key() === "SUPER + ALT + D" && /^TACIT_FLOW_KEY = "SUPER \+ ALT \+ D"$/m.test(customVariables.text()), customVariables.text());
  check("and dictation moves there, in both, the Copilot key left free", bound() === "main=SUPER + ALT + D;flow=SUPER + ALT + D", bound());
  pick("SUPER + SHIFT + F23");
  check("back on the Copilot key, Settings' block goes", !/TACIT_FLOW_KEY/.test(customVariables.text()) && key() === "SUPER + SHIFT + F23", customVariables.text());
  check("and dictation is on the Copilot key again", bound() === "main=SUPER + SHIFT + F23;flow=SUPER + SHIFT + F23", bound());
  // a home with the binds appended to custom/keybinds.lua before they were packaged
  legacy.saved = 'hl.bind("SUPER + SHIFT + F23", hl.dsp.global("quickshell:flowHold"), { description = "Flow: hold to dictate" })\nhl.define_submap("flow", function()\n    hl.bind("SUPER + SHIFT + F23", hl.dsp.global("quickshell:flowHold"), { description = "Flow: hold to dictate" })\nend)\n';
  root.flowKeyOld = "SUPER + SHIFT + F23";
  pick("SUPER + SHIFT + D");
  check("where the binds were appended to custom/keybinds.lua, that copy goes to the same key",
    (legacy.saved.match(/hl\.bind\("SUPER \+ SHIFT \+ D", hl\.dsp\.global\("quickshell:flowHold"\)/g) ?? []).length === 2 && !/F23/.test(legacy.saved), legacy.saved);
} catch (e) {
  check("the key could be set", false, String(e.message ?? e));
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
