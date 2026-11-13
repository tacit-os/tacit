// Removing an app in Apps: Your apps' rows (store.qml) run on what the backend (scripts/store/stored.py) says of each
// app, and a Remove pressed on an app that is open, through stored.py and bundle.py to the window's words. Remove is
// offered only on what Apps got itself; the backend refuses any other (#53), and an app got here only once it is closed.
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { inScope, qmlProperty, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

const helper = join(dirname(fileURLToPath(import.meta.url)), "lib", "store_cases.py");
function store(name) {
  const r = spawnSync("python3", ["-I", helper, tree, name], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  return JSON.parse(r.stdout);
}
const qml = read("store.qml");

console.log("== removing an app (store.qml, scripts/store)");
{
  // the binding Your apps gives each row's removable, on the backend's answer for that app
  const row = qml.indexOf("ListRow {", qml.indexOf("id: yoursPage"));
  const expr = readExpression(qml, qml.indexOf("removable:", row) + "removable:".length).expr;
  const removable = modelData => !!inScope({ modelData }, "", `return (${expr});`)();
  const { pacman, bundle } = store("yours");
  check("GIMP installed with pacman has no Remove in Your apps", !removable(pacman), `removable: ${expr}`);
  check("an app Apps got has", removable(bundle));
}
{
  // Blender open with a document: its sandbox has the bundle's folder laid over /usr
  const r = store("remove-open");
  check("Remove on an open app is refused as open, and its folder and launcher stay", r.open.result === "running" && r.kept,
    `backend said ${JSON.stringify(r.open)}, folder and launcher ${r.kept ? "kept" : "gone"}`);
  check("once it is closed, Remove removes it", r.closed.result === "ok" && r.gone, JSON.stringify(r.closed));
  // the window's handler keeps a removal's result as outcome[pkg]; ListRow and the app page say outcomeWords[it]
  const at = qml.indexOf("o[root.work.pkg] =");
  const kept = inScope({ root: { work: { pkg: "blender", kind: "remove" } }, msg: r.open }, "",
    `return (${readExpression(qml, at + "o[root.work.pkg] =".length).expr});`)();
  const words = (inScope({}, "", `return (${qmlProperty(qml, "outcomeWords")});`)()[kept] ?? []).join(". ");
  check("the window says it is open and to close it first", /open/i.test(words) && /close/i.test(words), `"${kept}": "${words}"`);
}
done();
