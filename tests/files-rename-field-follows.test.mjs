// The rename field in Pinax stays on the file it was opened on when a file lands above it
// (modules/ii/files/FilesWindow.qml): the window's own renameAt, rename and relist, its editing properties and the list
// row's editing binding run under node on Downloads (newest first), where each row keeps its file and takes a new
// index when a download lands at the top, as the list's ScriptModel keeps them.
import { inScope, qmlFunction, qmlProperty, readExpression } from "./lib/qml.mjs";
import { objectWith } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the rename field stays on its file when rows move (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
const dl = n => `/home/a/Downloads/${n}`;
let rows = [];
const ran = [];
const folderModel = { get count() { return rows.length; }, get: (i, role) => (role === "filePath" ? rows[i] && dl(rows[i]) : role === "fileName" ? rows[i] : role === "fileIsDir" ? false : undefined), rebuild() {} };
const win = { query: "", queryLower: "", gridFiltering: false, selectedMap: {}, cursorPath: "", anchorPath: "", view: "list", searching: false,
  isDriveTrash: () => false, run: (op, args) => ran.push(`${op} ${args.join(" ")}`) };
const scope = { win, folderModel, Things: { kindOf: () => "document" }, Files: { parent: p => p.slice(0, p.lastIndexOf("/")) } };
for (const name of ["pathAt", "selectOnly", "rowShown", "nameShown", "relist", "renameAt", "rename"]) {
  const f = qmlFunction(src, name);
  win[name] = inScope(scope, f.params, f.body);
}
for (const name of ["cursor", "anchorIndex", "editingIndex"]) {
  if (!new RegExp(`readonly property int ${name}:`).test(src)) { win[name] = -1; continue; }
  Object.defineProperty(win, name, { get: inScope(scope, "", `return (${qmlProperty(src, name)});`) });
}
const row = objectWith(src, "delegate: FilesRow {");
const editingExpr = readExpression(row, row.indexOf("editing:") + "editing:".length).expr;
const editing = (filePath, index) => inScope({ ...scope, filePath, index }, "", `return (${editingExpr});`)();

rows = ["a.pdf", "b.pdf", "c.pdf"];
win.relist();
win.renameAt(0);                                   // F2 on a.pdf
rows = ["new.pdf", "a.pdf", "b.pdf", "c.pdf"];     // a download lands at the top; a.pdf's row is now the second
win.relist();
const open = rows.map((n, i) => (editing(dl(n), i) ? n : null)).filter(Boolean);
check("after a download lands above, the field is still on a.pdf", open.join() === "a.pdf", `the field is on ${open.join() || "no row"}`);
// Enter in the open field: the row hands its own index to rename()
const at = rows.findIndex((n, i) => editing(dl(n), i));
if (at >= 0) win.rename(at, "final.pdf");
check("and the name typed renames a.pdf", ran.join() === `rename ${dl("a.pdf")} final.pdf`, ran.join() || "nothing renamed");
done();
