// A drop in the Trash is a trash, with the record Put back needs (modules/ii/files/FilesWindow.qml dropIn, FilesRow.qml):
// on a trashed folder's row, on a drive's trash listed at the Trash's root, or on the ground inside a drive's trash, as
// on the Trash's own ground. A folder row in the Trash takes no drop of its own, and a drive's trash row is neither
// dragged out nor cut. The window's own dropIn, trashOf, isDriveTrash, uriList and copySelection, and the row's drop
// binding with the window's delegate binding, run under node.
import { check, done, read } from "./lib/check.mjs";
import { inScope, matchBrace, qmlFunction } from "./lib/qml.mjs";

console.log("== a drop in the Trash goes to the trash (FilesWindow.qml dropIn, FilesRow.qml)");
const src = read("modules/ii/files/FilesWindow.qml"), rowSrc = read("modules/ii/files/FilesRow.qml");
const home = "/home/u", trashDir = `${home}/.local/share/Trash/files`, stickTrash = "/run/media/u/USB/.Trash-1000/files";
const ran = [], brought = [];
const Files = { trashDir, driveTrashes: [{ name: "USB 14.9G", path: stickTrash, count: 2 }], clip: null };
const win = { trashDir, folder: trashDir, selectedPaths: [], selectedMap: {}, pendingTrash: [], reason: "",
  run: (op, items) => ran.push([op, items]), bring: (op, paths, dest) => brought.push([op, paths, dest]) };
const scope = { win, Files, FileUtils: { trimFileProtocol: s => (s.startsWith("file://") ? s.slice(7) : s) }, Qt: { ControlModifier: 1, ShiftModifier: 2 },
  Quickshell: { execDetached() {} }, StringUtils: { shellSingleQuoteEscape: s => s }, Voice: { count: (k, w) => `${k} ${w}s` }, reasonTimer: { restart() {} } };
for (const name of ["decodePath", "fileUrl", "trashOf", "isDriveTrash", "dropIn", "uriList", "copySelection"]) {
  const f = qmlFunction(src, name);
  if (f) win[name] = inScope(scope, f.params, f.body);
}
win.pathAt = i => win.rows[i];
Object.defineProperty(win, "inTrash", { get: () => win.trashOf(win.folder).length > 0 });

const url = p => "file://" + p.split("/").map(encodeURIComponent).join("/");
const drop = (folder, dest, paths) => {
  win.folder = folder; ran.length = 0; brought.length = 0;
  win.dropIn(paths.map(url), 0, true, dest);
  return { ran: JSON.stringify(ran), brought: JSON.stringify(brought) };
};
const notes = `${home}/Documents/notes #1.txt`;
let r = drop(trashDir, `${trashDir}/old folder`, [notes]);
check("at the Trash's root, a drop on a trashed folder's row is a trash", r.ran === JSON.stringify([["trash", [notes]]]) && r.brought === "[]", JSON.stringify(r));
r = drop(trashDir, stickTrash, [notes]);
check("and so is one on a drive's trash listed there", r.ran === JSON.stringify([["trash", [notes]]]) && r.brought === "[]", JSON.stringify(r));
r = drop(stickTrash, stickTrash, [notes]);
check("and one on the ground inside a drive's trash", r.ran === JSON.stringify([["trash", [notes]]]) && r.brought === "[]", JSON.stringify(r));
r = drop(trashDir, trashDir, [notes]);
check("as one on the Trash's own ground is", r.ran === JSON.stringify([["trash", [notes]]]), JSON.stringify(r));
r = drop(stickTrash, stickTrash, [`${stickTrash}/a.txt`, `${trashDir}/b.txt`]);
check("what is already in a trash is not trashed again", r.ran === "[]" && r.brought === "[]", JSON.stringify(r));
r = drop(`${home}/Documents`, `${home}/Documents/Work`, [`${home}/Desktop/x.txt`]);
check("outside the Trash a drop on a folder's row still goes into it", r.ran === "[]" && r.brought === JSON.stringify([["move", [`${home}/Desktop/x.txt`], `${home}/Documents/Work`]]), JSON.stringify(r));

// the row's DropArea: enabled by its own binding, which the window's delegate may set
const intoAt = rowSrc.indexOf("id: into");
const into = rowSrc.slice(rowSrc.lastIndexOf("DropArea {", intoAt), matchBrace(rowSrc, rowSrc.lastIndexOf("{", intoAt)) + 1);
const enabledExpr = /enabled:\s*(.+)/.exec(into)?.[1] ?? "true";
const rowDefault = /property bool takesDrops:\s*([^\n/]+)/.exec(rowSrc)?.[1];
const delAt = src.indexOf("delegate: FilesRow {");
const delegate = src.slice(delAt, matchBrace(src, src.indexOf("{", delAt)) + 1);
const delegateExpr = /\btakesDrops:\s*([^\n/]+)/.exec(delegate)?.[1];
const takes = (folder, fileIsDir) => {
  win.folder = folder;
  const row = { fileIsDir };
  const bound = delegateExpr ?? rowDefault;
  if (bound) row.takesDrops = inScope({ win, row, fileIsDir }, "", `return (${bound});`)();
  return inScope({ row }, "", `return (${enabledExpr});`)();
};
check("a folder row in the Trash takes no drop of its own", takes(trashDir, true) === false && takes(stickTrash, true) === false,
  `enabled: ${enabledExpr}; delegate: ${delegateExpr}`);
check("a folder row elsewhere does, and a file's row does not", takes(`${home}/Documents`, true) === true && takes(`${home}/Documents`, false) === false);

// the drive's trash row, at the Trash's root
win.folder = trashDir; win.rows = [stickTrash, `${trashDir}/old.txt`];
win.selectedPaths = [stickTrash, `${trashDir}/old.txt`]; win.selectedMap = { [stickTrash]: true, [`${trashDir}/old.txt`]: true };
check("a drive's trash is not in what a drag of the selection carries", win.uriList(0) === url(`${trashDir}/old.txt`), JSON.stringify(win.uriList(0)));
win.selectedMap = {}; win.selectedPaths = [];
check("nor dragged alone", win.uriList(0) === "", JSON.stringify(win.uriList(0)));
win.selectedPaths = [stickTrash, `${trashDir}/old.txt`];
win.copySelection(true);
check("and a cut leaves it out", JSON.stringify(Files.clip?.paths) === JSON.stringify([`${trashDir}/old.txt`]), JSON.stringify(Files.clip));
done();
