// What the shell holds (panelFamilies/IllogicalImpulseFamily.qml's holdTacit(): the notch on with its volume and
// brightness, the grid overview, Tacit's lock) has no control in the legacy panel (`settings legacy`,
// modules/ii/settings/), since holdTacit() turns any change straight back: each value it sets back is looked for as an
// assignment in the panel's files.
import { readdirSync } from "fs";
import { join } from "path";
import { qmlFunction } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== the legacy panel and the values the shell holds (IllogicalImpulseFamily.qml)");
const hold = qmlFunction(read("panelFamilies/IllogicalImpulseFamily.qml"), "holdTacit");
const held = [...new Set([...hold.body.matchAll(/\bo\.([\w.]+)\s*=(?!=)/g)].map(m => m[1]))];
check("holdTacit() holds the notch, its volume and brightness, the overview and the lock", held.length >= 5, held.join(", "));

const files = [];
for (const dir of ["modules/ii/settings", "modules/ii/settings/pages"])
  for (const f of readdirSync(join(tree, dir))) if (f.endsWith(".qml")) files.push(`${dir}/${f}`);
for (const key of held) {
  const re = new RegExp(`Config\\.options\\.${key.replace(/\./g, "\\.")}\\s*=(?!=)`);
  const writers = files.filter(f => re.test(read(f))).map(f => f.replace(/.*\//, ""));
  check(`nothing in the legacy panel sets ${key}`, writers.length === 0, `set in ${writers.join(", ")}, and turned back at once`);
}
done();
