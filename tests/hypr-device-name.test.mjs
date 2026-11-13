// A pointer setting for one device (Settings > Mouse, > Touchpad: "device:<name>:<option>") written to
// shellOverrides/main.lua by scripts/hyprland/hyprconfigurator.py when the device's name has a quote or a backslash in
// it: the tree's script run by python on a file of its own, what it wrote read by luac and run by lua with a pretend
// hl.device and hl.config. Also the line an older version wrote for such a name, unescaped, which broke the whole file.
import { spawnSync } from "child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { check, done, tree } from "./lib/check.mjs";

console.log("== a device whose name has a quote or a backslash (hyprconfigurator.py)");
const dir = mkdtempSync(join(tmpdir(), "tacit-hypr-device-"));
try {
  const main = join(dir, "main.lua");
  // main.lua after these --set pairs on this text; and what Hyprland's config reads from it
  function written(text, ...sets) {
    writeFileSync(main, text);
    spawnSync("python3", ["-I", join(tree, "scripts/hyprland/hyprconfigurator.py"), "--file", main, ...sets.flatMap(s => ["--set", ...s])], { stdio: "ignore" });
    const parsed = spawnSync("luac", ["-p", main], { encoding: "utf8" });
    const run = spawnSync("lua", ["-e", `local seen = {}
hl = { config = function(t) if t.decoration then seen.rounding = t.decoration.rounding end end,
       device = function(t) for k, v in pairs(t) do if k ~= "name" then seen[t.name .. "|" .. k] = v end end end }
dofile(${JSON.stringify(main)})
local keys = {}
for k, v in pairs(seen) do keys[#keys + 1] = k .. "=" .. tostring(v) end
table.sort(keys)
io.write(table.concat(keys, "\\n"))`], { encoding: "utf8" });
    return { loads: parsed.status === 0, seen: (run.stdout ?? "").split("\n").filter(Boolean), file: readFileSync(main, "utf8").trim() };
  }
  const base = "hl.config({ decoration = { rounding = 12 } })\n";
  for (const name of ['my-"g"-mouse', "pad\\2", "logitech-usb-receiver"]) {
    const r = written(base, [`device:${name}:sensitivity`, "0.5"]);
    check(`${name}: main.lua still loads, with this device's speed under its own name and the rest kept`,
      r.loads && r.seen.join() === [`${name}|sensitivity=0.5`, "rounding=12"].join(), `${r.loads ? "loads" : "does not load"}: ${r.file.split("\n").pop()}; read ${JSON.stringify(r.seen)}`);
  }
  {
    // set twice: the second replaces the first
    written(base, ['device:my-"g"-mouse:sensitivity', "0.5"]);
    const r = written(readFileSync(main, "utf8"), ['device:my-"g"-mouse:sensitivity', "-0.3"]);
    check("set again, the line is replaced, not added", r.loads && r.file.split("\n").length === 2 && r.seen.includes('my-"g"-mouse|sensitivity=-0.3'), r.file);
  }
  {
    // the line an older version wrote, which no Lua reads: replaced by the next change to that setting
    const r = written(base + 'hl.device({ name = "my-"g"-mouse", sensitivity = 0.2 })\n', ['device:my-"g"-mouse:sensitivity', "0.4"]);
    check("a broken line written before for that name is replaced and the file loads again",
      r.loads && r.file.split("\n").length === 2 && r.seen.join() === ['my-"g"-mouse|sensitivity=0.4', "rounding=12"].join(), r.file);
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}
done();
