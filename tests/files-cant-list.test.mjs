// Where Qt's folder model can't list a folder because its path holds # or ?, Pinax's list, its Columns view and Save
// As's folder browser say so in place of rows (services/Files.qml cantList). Qt 6.12's FolderListModel reads the path
// as a url again, so a # or ? ends it: it lists nothing, or another folder ("#2024" comes out as the folder above).
// Each place's own blocks run under qmltestrunner offscreen with a real FolderListModel over folders named "C# stuff",
// "what?", "#2024" and "plain": the line shows for the first three and not for the plain one, and no other folder's
// rows show.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a folder Qt can't list for its # or ? says so (FilesWindow.qml, FilesColumns.qml, SaveWindow.qml)");
const words = "Files can't list a folder with # or ? in its name yet";
// the tree's own function, for a stand-in; one an older tree lacks says nothing
const fn = (src, name) => {
  const f = qmlFunction(src, name);
  return f ? `function ${name}(${f.params}) {${f.body}}` : `function ${name}() { return "" }`;
};
const stubs = {
  ...module("qs.services", {
    Files: `QtObject { property var driveTrashes: []; function placeName(p) { return p.split("/").pop() }
      function parent(p) { return p.substring(0, p.lastIndexOf("/")) || "/" } ${fn(read("services/Files.qml"), "cantList")} }`,
    Things: `QtObject { function describe(p) { return { glyph: "" } } function kindOf(n) { return "" } }`,
  }),
  ...module("qs.modules.common", {
    Tacit: `QtObject { property var space: ({ l: 16, xl: 24, xxl: 32 }) }`,
    Appearance: `QtObject { property var colors: ({ colSubtext: "gray" }) }`,
  }),
  ...module("qs.modules.common.functions", { FileUtils: `QtObject { ${fn(read("modules/common/functions/FileUtils.qml"), "fileUrl")} }` }),
  ...module("qs.modules.common.widgets", {}, { GlideWheel: "Item { property var view }", StyledText: "Text {}" }),
  ...module("Tacit.Kit", { Kit: `QtObject { property var tokens: ({ space: { l: 16, m: 12 }, hairline: "gray", inkMeta: "gray" }) }` }, {
    ListRow: "Item { property string glyph; property string picture; property string name; property bool selected; property bool focusable; signal clicked(); signal activated(); height: 44 }",
    Symbol: "Item { property string text; property color color }",
    PageState: "Item { property string text; property bool failure; property string action; property real maxWidth; signal activated() }",
  }),
};
const imports = `import QtQuick
import QtQuick.Layouts
import QtTest
import Qt.labs.folderlistmodel
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Tacit.Kit as K`;
// what Qt's model holds, the rows shown and the line said, for each folder in turn
const report = (model, shown, says) => `{ const listed = []; for (let k = 0; k < ${model}.count; k++) listed.push(${model}.get(k, "fileName"));
                out.push({ listed, rows: ${shown}, says: ${says} }); }`;

const root = mkdtempSync(join(tmpdir(), "tacit-cant-list-"));
try {
  const names = ["plain", "C# stuff", "what?", "#2024"];
  for (const n of names) {
    mkdirSync(join(root, n, "inside"), { recursive: true });
    writeFileSync(join(root, n, "notes.txt"), "");
  }
  const paths = JSON.stringify(names.map(n => join(root, n)));
  // a folder at a time, as the window and Save As go to it
  const walk = (folder, model, shown, says) => `
        function test_walk() {
            const out = [];
            for (const f of ${paths}) {
                ${folder} = f;
                for (let k = 0; k < 20 && ${model}.status === FolderListModel.Loading; k++) wait(50);
                wait(150);
                ${report(model, shown, says)}
            }
            console.log("SAID " + JSON.stringify(out));
        }`;

  const win = read("modules/ii/files/FilesWindow.qml");
  const windowScene = `${imports}
Item {
    width: 900; height: 600
    QtObject {
        id: win
        property string folder: ${JSON.stringify(join(root, "plain"))}
        property int reloads: 0
        property bool showHidden: false
        property string view: "list"
        property bool gridFiltering: false
        property string query: ""
        property bool probed: true
        property string selectPath: ""
        property var twins: ({})
        property var rowByPath: ({})
        property var dirPaths: ({})
        property var names: ({})
        property int shownCount: 0
        property bool pictureFolder: false
        property bool searching: false
        property string gone: ""
        property bool unreadable: false
        property bool filterActive: false
        property int historyIndex: 0
        property string trashDir: "/nowhere"
        ${fn(win, "fileUrl")}
        ${fn(win, "relist")}
        function nameShown(n) { return true }
        function kindGroup(k) { return "Other" }
        function passesFilter(r) { return true }
        function compareRows(a, b) { return a.fileName < b.fileName ? -1 : 1 }
        function pruneSelection() {}
        function decideView() {}
        function tryRevealEdit() {}
    }
    QtObject { id: existsProbe; property bool running }
    QtObject { id: twinProc; property bool running }
    QtObject { id: rowsSoon; function restart() {} }
    Item { id: filesArea }
    ${objectWith(win, "id: folderModel")}
    ${objectWith(win, "id: raw")}
    ${objectWith(win, "target: raw")}
    ${objectWith(win, "id: pageState")}
    TestCase { name: "window"; when: windowShown ${walk("win.folder", "raw", "folderModel.rows.length", 'pageState.visible ? pageState.text : ""')} }
}
`;

  const columnScene = `${imports}
Item {
    width: 1200; height: 600
    QtObject {
        id: columns
        property bool showHidden: false
        readonly property real columnWidth: 250
        property var levels: []
        function pictureFor(p, d) { return "" }
        function goTo(p) {}
        function revealIn(p) {}
    }
    Item { id: strip; height: 500 }
    Repeater { id: ancestors; model: ${paths}; delegate: ${objectWith(read("modules/ii/files/FilesColumns.qml"), "id: col\n")} }
    TestCase {
        name: "columns"; when: windowShown
        function test_columns() {
            const out = [], parts = [];
            for (let i = 0; i < ancestors.count; i++) {
                const c = ancestors.itemAt(i), p = { col: c, says: null };
                for (const o of c.resources) if (o.nameFilters !== undefined) p.dir = o;
                for (const o of c.children) if (o.maxWidth !== undefined) p.says = o;
                parts.push(p);
            }
            // the plain one and "#2024" (its folder above) are listed: wait for those
            for (let k = 0; k < 40 && !(parts[0].dir.status === FolderListModel.Ready && parts[3].dir.status === FolderListModel.Ready); k++) wait(50);
            wait(100);
            for (const p of parts) ${report("p.dir", "p.col.list.count", 'p.says && p.says.visible ? p.says.text : ""')}
            console.log("SAID " + JSON.stringify(out));
        }
    }
}
`;

  const save = read("modules/ii/files/SaveWindow.qml");
  const saveScene = `${imports}
Item {
    width: 900; height: 600
    component Row2: Item { property string glyph; property string label; property bool on; property bool dim; signal clicked(); height: 38 }
    QtObject {
        id: win
        property string folder: ${JSON.stringify(join(root, "plain"))}
        property bool forFolder: false
        property string name: ""
        function relist() {}
        function go(p) {}
    }
    QtObject { id: focusTimer; function restart() {} }
    ${objectWith(save, "id: here")}
    RowLayout { width: 800; height: 400
        ${objectWith(save, "id: listing")}
    }
    TestCase { name: "save"; when: windowShown ${walk("win.folder", "here", "listing.count", 'listing.footerItem && listing.footerItem.visible ? listing.footerItem.text : ""')} }
}
`;

  for (const [place, scene] of [["Pinax's list", windowScene], ["the Columns view's column", columnScene], ["Save As's folder browser", saveScene]]) {
    let said;
    try {
      said = logged(runScene({ "tst_cant_list.qml": scene, ...stubs }), "SAID");
    } catch (e) {
      check(`the scene for ${place} ran`, false, String(e.message ?? e));
      continue;
    }
    names.forEach((n, i) => {
      const s = said[i], why = JSON.stringify(s);
      if (n === "plain") {
        check(`${place}: "plain" is listed`, s.listed.join() === "inside,notes.txt" && s.rows === 2, why);
        check(`${place}: "plain" says nothing`, s.says === "", why);
        return;
      }
      // what Qt itself does there, so the test knows the case it guards
      if (n === "#2024") check(`Qt's model in ${place} lists the folder above for "${n}"`, s.listed.includes("#2024"), why);
      else check(`Qt's model in ${place} lists nothing for "${n}"`, s.listed.length === 0, why);
      check(`${place}: "${n}" shows no rows`, s.rows === 0, why);
      check(`${place}: "${n}" says “${words}”`, s.says === words, why);
    });
  }
} finally {
  rmSync(root, { recursive: true, force: true });
}
done();
