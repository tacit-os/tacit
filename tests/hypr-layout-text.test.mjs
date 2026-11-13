// A keyboard layout typed into Settings > Hyprland (modules/ii/settings/pages/HyprlandConfig.qml) and written to
// shellOverrides/main.lua by scripts/hyprland/hyprconfigurator.py: the tree's script run by python on a file of its own,
// what it wrote read by luac and run by lua with a pretend hl.config, and the field's own confirm handler run under node.
import { spawnSync } from "child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== a keyboard layout typed with a quote, a backslash or spaces (hyprconfigurator.py, HyprlandConfig.qml)");
const dir = mkdtempSync(join(tmpdir(), "tacit-hyprconf-"));
try {
  const main = join(dir, "main.lua");
  // the file after Settings set this layout, beside the page's other settings; and what Hyprland's config reads from it
  function written(layout) {
    writeFileSync(main, "hl.config({ decoration = { rounding = 12 } })\n");
    spawnSync("python3", ["-I", join(tree, "scripts/hyprland/hyprconfigurator.py"), "--file", main, "--set", "input:kb_layout", layout], { stdio: "ignore" });
    const parsed = spawnSync("luac", ["-p", main], { encoding: "utf8" });
    const run = spawnSync("lua", ["-e", `local seen = {}
hl = { config = function(t) for k, v in pairs(t) do seen[k] = v end end }
dofile(${JSON.stringify(main)})
io.write(seen.input and seen.input.kb_layout or "", "|", seen.decoration and seen.decoration.rounding or "")`], { encoding: "utf8" });
    const [kb, rounding] = (run.stdout ?? "").split("|");
    return { loads: parsed.status === 0, kb, rounding, file: readFileSync(main, "utf8").trim().split("\n").pop() };
  }
  for (const layout of ['us"', "us\\", "de"]) {
    const r = written(layout);
    check(`a layout typed as ${layout}: main.lua still loads, with the layout as typed and the rest kept`,
      r.loads && r.kb === layout && r.rounding === "12", `${r.loads ? "loads" : "does not load"}: ${r.file}`);
  }
} finally {
  rmSync(dir, { recursive: true, force: true });
}

// the field: what Enter writes for a list typed with spaces after its commas, as the placeholder shows it
{
  const block = objectWith(read("modules/ii/settings/pages/HyprlandConfig.qml"), "id: kbLayoutField");
  const wrote = [];
  const field = { value: "us, es ,latam ", Config: { options: { hyprland: { input: { kbLayout: "" } } } }, HyprlandXkb: { layoutCodes: ["us"] },
    HyprlandConfig: { set: (k, v) => wrote.push(`${k}=${v}`) } };
  for (const name of ["inUse", "typed"]) {
    const expr = qmlProperty(block, name);
    if (expr) Object.defineProperty(field, name, { get: inScope(field, "", `return (${expr});`) });
  }
  const at = block.indexOf("confirmButtonVisible:");
  Object.defineProperty(field, "confirmButtonVisible", { get: inScope(field, "", `return (${readExpression(block, at + 21).expr});`) });
  const handler = readExpression(block, block.indexOf("onConfirmClicked:") + 17).expr;
  inScope(field, "", handler.slice(1, -1))();
  check('"us, es ,latam " is written as us,es,latam', wrote.join() === "input:kb_layout=us,es,latam" && field.Config.options.hyprland.input.kbLayout === "us,es,latam",
    `wrote ${wrote.join(", ") || "nothing"}, saved ${JSON.stringify(field.Config.options.hyprland.input.kbLayout)}`);
}
done();
