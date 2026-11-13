// Pinax's Columns view lists an ancestor's own folder in its column when the ancestor's name holds '#', '?' or '%'
// (modules/ii/files/FilesColumns.qml): the column's own FolderListModel block runs under qmltestrunner offscreen, with
// FileUtils' own functions, on folders named "C# stuff", "Why?", "Sale %40 off" and "100%". Qt 6.12's FolderListModel
// reads the decoded path as a URL again ('#' starts a fragment, '%40' is decoded twice), so the first three need
// FileUtils.folderUrl's form; given the plain url they listed nothing.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Columns view lists the folder itself for a name with # ? or % (FilesColumns.qml)");
const block = objectWith(read("modules/ii/files/FilesColumns.qml"), "id: dir");
const utils = read("modules/common/functions/FileUtils.qml");
// the tree's own; one an older tree lacks gives nothing
const fns = ["fileUrl", "folderUrl", "listedPath"].map(n => { const f = qmlFunction(utils, n); return f ? `function ${n}(${f.params}) {${f.body}}` : ""; });
const root = mkdtempSync(join(tmpdir(), "tacit-columns-"));
try {
  const names = ["C# stuff", "Why?", "Sale %40 off", "100%"];
  for (const n of names) {
    mkdirSync(join(root, "Projects", n, "inside"), { recursive: true });
    writeFileSync(join(root, "Projects", n, "notes.txt"), "");
  }
  for (const n of names) {
    const scene = `import QtQuick
import QtTest
import Qt.labs.folderlistmodel
import qs.modules.common.functions
Item {
    QtObject { id: col; property string modelData: ${JSON.stringify(join(root, "Projects", n))} }
    QtObject { id: columns; property bool showHidden: false }
    QtObject { id: bring; function restart() {} }
    ${block}
    TestCase {
        name: "column"; when: windowShown
        function test_listed() {
            // a folder Qt cannot read stays Null, so this waits a while rather than for Ready
            for (let k = 0; k < 20 && dir.status !== FolderListModel.Ready; k++) wait(50);
            wait(50);
            const got = [];
            for (let i = 0; i < dir.count; i++) got.push(dir.get(i, "fileName"));
            console.log("COLUMN " + JSON.stringify(got));
        }
    }
}
`;
    const stubs = module("qs.modules.common.functions", { FileUtils: `QtObject { id: root; ${fns.join("\n")} }` });
    try {
      const got = logged(runScene({ "tst_column.qml": scene, ...stubs }), "COLUMN");
      check(`the column for "${n}" lists that folder`, got.join() === "inside,notes.txt", `it lists ${JSON.stringify(got)}`);
    } catch (e) {
      check(`the scene for "${n}" ran`, false, String(e.message ?? e));
    }
  }
} finally {
  rmSync(root, { recursive: true, force: true });
}
done();
