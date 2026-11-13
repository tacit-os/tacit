// Your apps (store.qml) lists only the apps Apps got itself: the page's own list binding under node, on what the backend
// (scripts/store/stored.py info, tests/lib/store_cases.py yours) says of GIMP installed with pacman and of an app got
// here as a bundle.
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { inScope, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

console.log("== Your apps lists only what Apps got (store.qml, scripts/store/stored.py)");
const r = spawnSync("python3", ["-I", join(dirname(fileURLToPath(import.meta.url)), "lib", "store_cases.py"), tree, "yours"], { encoding: "utf8" });
if (r.status !== 0) throw new Error(r.stderr);
const { pacman, bundle } = JSON.parse(r.stdout);
const qml = read("store.qml");
const at = qml.indexOf("readonly property var list:", qml.indexOf("id: yoursPage"));
const expr = readExpression(qml, at + "readonly property var list:".length).expr;
const apps = { gimp: pacman, krita: bundle };
const listed = installed => inScope({ root: { home: { installed }, appOf: p => apps[p] ?? null } }, "", `return (${expr});`)().map(a => a.pkg);
const both = listed(["gimp", "krita"]);
check("GIMP from pacman is not in Your apps; the app got here is", JSON.stringify(both) === JSON.stringify(["krita"]), JSON.stringify(both));
const lineAt = qml.indexOf("line:", qml.indexOf("PageHead {", at));
const line = list => inScope({ root: { home: {} }, yoursPage: { list } }, "", `return (${readExpression(qml, lineAt + "line:".length).expr});`)();
check("with only apps got elsewhere, the page has none and says so", listed(["gimp"]).length === 0 && /^None yet/.test(line(listed(["gimp"]))),
  `${JSON.stringify(listed(["gimp"]))}: "${line(listed(["gimp"]))}"`);
done();
