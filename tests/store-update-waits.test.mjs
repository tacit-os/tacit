// An app got from Apps that is left open over Tacit's updates keeps running the bundle it started on until its next start
// (scripts/store/bundle.py run), and Your apps says so on its row: "Updates when you next open it". stored.py's own home()
// in a home of its own, over bundle.py's own list run as stored.py runs it (tests/lib/store_cases.py), then the row's
// bindings in store.qml under node.
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import { inScope, matchBrace, readExpression } from "./lib/qml.mjs";
import { check, done, read, tree } from "./lib/check.mjs";

const helper = join(dirname(fileURLToPath(import.meta.url)), "lib", "store_cases.py");
function waiting(name) {
  const r = spawnSync("python3", ["-I", helper, tree, name], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr);
  return JSON.stringify(JSON.parse(r.stdout).waiting);
}

console.log("== an app left open over Tacit's updates (scripts/store/bundle.py, stored.py)");
const w = Object.fromEntries(["open-newer", "open-shared-changed", "open-same", "closed-newer", "open-newer-not-updated"].map(n => [n, waiting(n)]));
check("Discord open after Tacit's updates, 0.0.112 in the system's lists: Your apps is told its update waits", w["open-newer"] === '["discord"]', w["open-newer"]);
check("and so when a system package it shares changed", w["open-shared-changed"] === '["discord"]', w["open-shared-changed"]);
check("not when there is nothing newer for it", w["open-same"] === "[]", w["open-same"]);
check("nor when it is closed", w["closed-newer"] === "[]", w["closed-newer"]);
check("nor while Tacit's updates are not installed, as its next start does not bring it then", w["open-newer-not-updated"] === "[]", w["open-newer-not-updated"]);

console.log("== its row in Your apps (store.qml)");
const qml = read("store.qml");
const rowAt = qml.indexOf("ListRow {", qml.indexOf("id: yoursPage"));
const row = qml.slice(rowAt, matchBrace(qml, rowAt + "ListRow ".length) + 1);
const bind = /\bupdateWaits\s*:\s*/.exec(row);
const comp = qml.indexOf("component ListRow:");
const listRow = qml.slice(comp, matchBrace(qml, qml.indexOf("{", comp)) + 1);
const lineAt = listRow.indexOf('"Updates when you next open it"');
const smallAt = listRow.lastIndexOf("Small {", lineAt);
const small = lineAt < 0 ? "" : listRow.slice(smallAt, matchBrace(listRow, smallAt + "Small ".length) + 1);
const visible = /\bvisible\s*:\s*/.exec(small);
const said = (home, pkg, outcome = "") => {
  const updateWaits = bind ? !!inScope({ root: { home }, modelData: { pkg } }, "", `return (${readExpression(row, bind.index + bind[0].length).expr});`)() : false;
  return visible ? !!inScope({ lr: { updateWaits, said: outcome } }, "", `return (${readExpression(small, visible.index + visible[0].length).expr});`)() : false;
};
const home = { waiting: JSON.parse(w["open-newer"]) };
check("Discord's row says \"Updates when you next open it\", in the row's quiet line", said(home, "discord") && said(home, "discord", "ok") && !/\bcolor\s*:/.test(small), small);
check("the row of an app with no update waiting does not, nor any row before the backend has answered", !said(home, "krita") && !said(null, "discord"));
// a row (84 px) has room for its name, its line and one more
check("Remove pressed on it while it is open: the row says that instead", !said(home, "discord", "r-running"));
done();
