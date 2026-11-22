// Files as a picker hands over every selected file on Enter (modules/ii/files/FilesWindow.qml): openIndex() run under
// node with four files selected for a page's upload, as Choose already did; one file opened alone is still that file.
import { inScope, qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Enter on several selected files in a pick chooses them all (FilesWindow.qml)");
const src = read("modules/ii/files/FilesWindow.qml");
const rows = ["/h/a.jpg", "/h/b.jpg", "/h/c.jpg", "/h/d.jpg", "/h/e.jpg"];
let sent = null;
const win = { forPick: true, selectedPaths: [], pickDone: p => { sent = p; } };
Object.defineProperty(win, "pickPaths", { get: () => win.selectedPaths });
const scope = { win, Files: { picking: { dir: false } }, Things: { open() {} },
  folderModel: { count: rows.length, get: (i, k) => k === "fileIsDir" ? false : rows[i] } };
const f = qmlFunction(src, "openIndex");
const openIndex = inScope(scope, f.params, f.body);

win.selectedPaths = rows.slice(0, 4);
openIndex(2);
check("Enter on one of four selected files sends all four", JSON.stringify(sent) === JSON.stringify(rows.slice(0, 4)), JSON.stringify(sent));
win.selectedPaths = [rows[0]];
openIndex(0);
check("one selected file sends that file", JSON.stringify(sent) === JSON.stringify([rows[0]]), JSON.stringify(sent));
win.selectedPaths = rows.slice(0, 2);
openIndex(4);
check("a file outside the selection sends only itself", JSON.stringify(sent) === JSON.stringify([rows[4]]), JSON.stringify(sent));
done();
