// A folder whose name holds #, ? or %XX is listed as itself in Pinax's list, its Columns view, Save As's folder browser
// and the Viewer's roll (modules/common/functions/FileUtils.qml folderUrl). Qt 6.12's FolderListModel turns its url into
// a path and reads that as a url again: "C# stuff" listed nothing, "#2024" the folder above, "My%20Files" "My Files", and
// what Files showed, selected and deleted there were another folder's. Where even folderUrl can't serve it (a folder in
// / with such a name), the lists say so in place of rows (services/Files.qml cantList) and the Viewer frames the file
// alone. Each place's own blocks run under qmltestrunner offscreen with a real FolderListModel over real folders, beside
// a "C", a "what", a "My Files" and a file above them, which the old url listed in their place.
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { qmlFunction } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a folder with #, ? or % in its name lists its own files (FilesWindow, FilesColumns, SaveWindow, Viewer)");
const words = "Files can't list a folder with #, ? or % in its path yet";
// the tree's own function, for a stand-in; one an older tree lacks says nothing
const fn = (src, name) => {
  const f = qmlFunction(src, name);
  return f ? `function ${name}(${f.params}) {${f.body}}` : `function ${name}() { return "" }`;
};
const utils = read("modules/common/functions/FileUtils.qml");
const stubs = {
  ...module("qs.services", {
    Files: `import qs.modules.common.functions
QtObject { property var driveTrashes: []; function placeName(p) { return p.split("/").pop() }
      function parent(p) { return p.substring(0, p.lastIndexOf("/")) || "/" } ${fn(read("services/Files.qml"), "cantList")} }`,
    Things: `QtObject { function describe(p) { return { glyph: "" } } function kindOf(n) { return "" } }`,
  }),
  ...module("qs.modules.common", {
    Tacit: `QtObject { property var space: ({ l: 16, xl: 24, xxl: 32 }) }`,
    Appearance: `QtObject { property var colors: ({ colSubtext: "gray" }) }`,
  }),
  ...module("qs.modules.common.functions", { FileUtils: `QtObject { id: root; ${["fileUrl", "folderUrl", "listedPath"].map(n => fn(utils, n)).join("\n")} }` }),
  ...module("qs.modules.common.widgets", {}, { GlideWheel: "Item { property var view }", StyledText: "Text {}" }),
  ...module("Tacit.Kit", { Kit: `QtObject { property var tokens: ({ space: { l: 16, m: 12 }, hairline: "gray", inkMeta: "gray" }) }` }, {
    ListRow: "Item { property string glyph; property string picture; property string name; property bool selected; property bool focusable; signal clicked(); signal activated(); height: 44 }",
    Symbol: "Item { property string text; property color color }",
    PageState: "Item { property string text; property bool failure; property string action; property real maxWidth; signal activated() }",
  }),
  "Info.js": `.pragma library\nfunction patterns() { return ["*"]; }\nfunction kindOf(p) { return "image"; }\n`,
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
// what each place shows: the rows' paths (as the views take them) and the line it says
const report = (shown, says) => `out.push({ rows: ${shown}, says: ${says} });`;

const root = mkdtempSync(join(tmpdir(), "tacit-cant-list-"));
try {
  // each with its own two; "C", "what", "My Files" and the folder above are what the old url listed for "C# stuff",
  // "what?", "My%20Files" and "#2024"
  const names = ["plain", "C# stuff", "what?", "#2024", "My%20Files", "100%"];
  for (const n of names.concat(["C", "what", "My Files"])) {
    mkdirSync(join(root, n, "inside"), { recursive: true });
    writeFileSync(join(root, n, `in ${n.replace(/\W/g, "")}.txt`), "");
  }
  writeFileSync(join(root, "above.txt"), "");
  // one Qt's model can't be given (its first name can't be a url's host): not created, it can only be refused
  const refused = "/tacit+test#1/sub";
  const own = n => [join(root, n, "inside"), join(root, n, `in ${n.replace(/\W/g, "")}.txt`)].sort();
  const folders = names.map(n => join(root, n)).concat([refused]);
  const paths = JSON.stringify(folders);
  const settle = model => `for (let k = 0; k < 20 && ${model}.status === FolderListModel.Loading; k++) wait(50); wait(150);`;
  // a folder at a time, as the window and Save As go to it
  const walk = (folder, model, shown, says) => `
        function test_walk() {
            const out = [];
            for (const f of ${paths}) {
                ${folder} = f;
                ${settle(model)}
                ${report(shown, says)}
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
    TestCase { name: "window"; when: windowShown ${walk("win.folder", "raw", "folderModel.rows.map(r => r.filePath)", 'pageState.visible ? pageState.text : ""')} }
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
            wait(600);
            for (const p of parts) {
                // the rows' paths as the delegate takes them (its own path, or Qt's filePath on a tree without one)
                const rows = [];
                for (let k = 0; k < p.col.list.count; k++) { const r = p.col.list.itemAtIndex(k); if (r) rows.push(r.path ?? r.filePath); }
                ${report("rows", 'p.says && p.says.visible ? p.says.text : ""')}
            }
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
        property string went: ""
        function relist() {}
        function go(p) { win.went = p }
    }
    QtObject { id: focusTimer; function restart() {} }
    ${objectWith(save, "id: here")}
    RowLayout { width: 800; height: 2000
        ${objectWith(save, "id: listing")}
    }
    TestCase {
        name: "save"; when: windowShown
        function test_walk() {
            const out = [];
            for (const f of ${paths}) {
                win.folder = f;
                ${settle("here")}
                // where each row leads: a folder's row goes there, a file's gives its name
                const rows = [];
                for (let k = 0; k < listing.count; k++) {
                    const r = listing.itemAtIndex(k);
                    if (!r) continue;
                    win.went = ""; win.name = "";
                    r.clicked();
                    rows.push(win.went || f + "/" + win.name);
                }
                ${report("rows", 'listing.footerItem && listing.footerItem.visible ? listing.footerItem.text : ""')}
            }
            console.log("SAID " + JSON.stringify(out));
        }
    }
}
`;

  const viewer = read("modules/viewer/Viewer.qml");
  const viewerScene = `import QtQuick
import QtTest
import Qt.labs.folderlistmodel
import qs.modules.common.functions
import "Info.js" as Info
Item {
    id: vw
    property string folder: ""
    property string wantPath: ""
    property var entries: []
    property int cur: 0
    property string asked: ""
    readonly property int maxListed: 5000
    property int listStart: 0
    property int listTotal: 0
    property string aimPath: ""
    property int landed: -1
    property bool released: false
    property bool animate: true
    property real pos: 0
    property real settle: 0
    property bool touching: false
    property bool bare: true
    property var resume: null
    property string kind: "image"
    property bool wantPlay: false
    function loadOrigins() {}
    function land() {}
    function applyResume() {}
    QtObject { id: dwell; function restart() {} }
    ${fn(viewer, "urlOf")}
    ${fn(viewer, "open")}
    ${fn(viewer, "relist")}
    ${objectWith(viewer, "id: entriesFor")}
    ${objectWith(viewer, "id: relistLater")}
    TestCase {
        name: "viewer"; when: windowShown
        function test_walk() {
            const out = [];
            for (const f of ${paths}) {
                const framed = f + "/" + (f.startsWith("/tacit") ? "a.jpg" : "in " + f.split("/").pop().replace(/\\W/g, "") + ".txt");
                vw.open(framed);
                ${settle("entriesFor")}
                wait(200);   // relistLater
                ${report("vw.entries.map(e => e.path)", '""')}
            }
            console.log("SAID " + JSON.stringify(out));
        }
    }
}
`;

  const places = [["Pinax's list", windowScene, true], ["the Columns view's column", columnScene, true],
    ["Save As's folder browser", saveScene, true], ["the Viewer's roll", viewerScene, false]];
  for (const [place, scene, says] of places) {
    let said;
    try {
      said = logged(runScene({ "tst_cant_list.qml": scene, ...stubs }), "SAID");
    } catch (e) {
      check(`the scene for ${place} ran`, false, String(e.message ?? e));
      continue;
    }
    names.forEach((n, i) => {
      const s = said[i], why = JSON.stringify(s);
      // the Viewer lists files only (showDirs false)
      const want = says ? own(n) : own(n).filter(p => !p.endsWith("/inside"));
      check(`${place}: "${n}" lists its own and nothing else`, JSON.stringify([...s.rows].sort()) === JSON.stringify(want), why);
      if (says) check(`${place}: "${n}" says nothing`, s.says === "", why);
    });
    const s = said[names.length], why = JSON.stringify(s);
    if (says) {
      check(`${place}: a folder Qt can't be given shows no rows`, s.rows.length === 0, why);
      check(`${place}: and says “${words}”`, s.says === words, why);
    } else {
      check(`${place}: a folder Qt can't be given frames the file alone`, JSON.stringify(s.rows) === JSON.stringify([`${refused}/a.jpg`]), why);
    }
  }
} finally {
  rmSync(root, { recursive: true, force: true });
}
done();
