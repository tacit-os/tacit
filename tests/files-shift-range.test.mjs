// Shift-click in Pinax ranges from the file clicked first, however the rows moved since
// (modules/ii/files/FilesWindow.qml): the window's own selectOnly, selectRange, relist and the cursor's and anchor's
// properties run under node on Downloads, where a new download lands above the clicked file, and where the clicked
// file is deleted.
import { inScope, qmlFunction, qmlProperty } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Shift-click ranges from the file clicked, after rows move (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
let rows = [];
const folderModel = { get count() { return rows.length; }, get: (i, role) => (role === "filePath" ? rows[i] && `/home/a/Downloads/${rows[i]}` : role === "fileName" ? rows[i] : role === "fileIsDir" ? false : undefined), rebuild() {} };
const win = { query: "", queryLower: "", gridFiltering: false, selectedMap: {}, cursorPath: "" };
const scope = { win, folderModel, Things: { kindOf: () => "document" } };
for (const name of ["pathAt", "selectOnly", "toggle", "selectRange", "rowShown", "nameShown", "relist"]) {
  const f = qmlFunction(src, name);
  win[name] = inScope(scope, f.params, f.body);
}
// the derived properties, as QML keeps them up to date; a plain one is a field the functions write
for (const name of ["cursor", "anchorIndex"]) {
  if (!new RegExp(`readonly property int ${name}:`).test(src)) { win[name] = -1; continue; }
  const get = inScope(scope, "", `return (${qmlProperty(src, name)});`);
  Object.defineProperty(win, name, { get });
}
const chosen = () => Object.keys(win.selectedMap).map(p => p.split("/").pop()).sort();

rows = ["a.pdf", "b.pdf", "c.pdf", "d.pdf"];
win.relist();
win.selectOnly(1);                                   // b.pdf clicked
rows = ["new.pdf", "a.pdf", "b.pdf", "c.pdf", "d.pdf"];   // a download lands at the top (newest first)
win.relist();
win.selectRange(3);                                  // Shift-click on c.pdf
check("after a download lands above, Shift-click on c.pdf selects b.pdf to c.pdf", chosen().join() === "b.pdf,c.pdf", chosen().join());

rows = ["a.pdf", "b.pdf", "c.pdf", "d.pdf", "e.pdf"];
win.relist();
win.selectOnly(4);                                   // e.pdf clicked
rows = ["a.pdf", "b.pdf", "c.pdf"];                  // d.pdf and e.pdf deleted elsewhere
win.relist();
win.selectRange(0);
check("with the clicked file gone, Shift-click selects no empty path", !("" in win.selectedMap) && chosen().join() === "a.pdf",
  JSON.stringify(Object.keys(win.selectedMap)));
done();
