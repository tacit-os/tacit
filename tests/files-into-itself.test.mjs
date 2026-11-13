// A folder pasted or dropped into itself, or into one of its own folders, says it can't go there
// (modules/ii/files/FilesWindow.qml): the window's own bring() runs under node with a copy and a cut of ~/Project put
// into ~/Project and ~/Project/src, and a cut put back where it is.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a folder can't go inside itself, and says so (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
const parent = qmlFunction(read("services/Files.qml"), "parent");
function bring(op, paths, dest) {
  const Files = { clip: { op }, trim: p => p.replace(/\/+$/, "") || "/" };
  Files.parent = inScope({ root: Files }, parent.params, parent.body);
  const win = { folder: dest, reason: "", nameTaken: () => false, bringChecked: () => { win.reason = "brought"; } };
  const f = qmlFunction(src, "bring");
  inScope({ win, Files, reasonTimer: { restart() {} }, clashProbe: {} }, f.params, f.body)(op, paths, dest);
  return win.reason;
}
const p = "/home/a/Project";
check("a copy pasted into its own subfolder says why nothing happened", bring("copy", [p], `${p}/src`) === "A folder can't go inside itself", `it says "${bring("copy", [p], `${p}/src`)}"`);
check("a copy pasted into itself says the same", bring("copy", [p], p) === "A folder can't go inside itself", `it says "${bring("copy", [p], p)}"`);
check("a cut pasted into its own subfolder says that, not 'Already here'", bring("move", [p], `${p}/src`) === "A folder can't go inside itself", `it says "${bring("move", [p], `${p}/src`)}"`);
check("a cut pasted where it already is still says 'Already here'", bring("move", [p], "/home/a") === "Already here", `it says "${bring("move", [p], "/home/a")}"`);
check("a copy into another folder goes ahead", bring("copy", [p], "/home/a/Backup") === "brought");
done();
