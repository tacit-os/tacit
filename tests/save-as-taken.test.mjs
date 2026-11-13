// Save As never hands an app a path that is already taken without asking (modules/ii/files/SaveWindow.qml): the
// name is checked on disk before it goes back, so neither a folder model that lists another folder (a # ? or %XX in
// a name, before FileUtils.folderUrl), nor one still holding the last folder's names, nor one Files can't list lets
// Save or Keep both write over a file. Save As's own blocks (its folder model, names, accept, Keep both and the disk
// check) run under qmltestrunner offscreen with a real FolderListModel over real folders named "C#", "a?b" and
// "My%20Files" beside the "C", "a" and "My Files" the old url listed instead; the check's own bash command is run on
// those folders here and its answers given to a stand-in Process, as Quickshell's gives them (exited, then not running).
import { spawnSync } from "child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { inScope, qmlFunction, readExpression } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Save As asks before a name already in the folder (SaveWindow.qml)");
const save = read("modules/ii/files/SaveWindow.qml");
const utils = read("modules/common/functions/FileUtils.qml");
const fn = (src, name) => { const f = qmlFunction(src, name); return f ? `function ${name}(${f.params}) {${f.body}}` : ""; };
// the window's own declarations, from the name typed to the path it would give
const decl = save.slice(save.indexOf("readonly property string trimmed"), save.indexOf("\n", save.indexOf("readonly property string target")));
const keepBoth = /label: "Keep both"; onClicked: (.*) \}\s*$/m.exec(save)?.[1] ?? "";
const procAt = save.indexOf("id: onDisk");
const proc = procAt < 0 ? "" : objectWith(save, "id: onDisk");

const root = mkdtempSync(join(tmpdir(), "tacit-save-as-"));
try {
  const names = ["plain", "C#", "a?b", "My%20Files"];
  for (const n of names) {
    mkdirSync(join(root, n, "inside"), { recursive: true });
    for (const f of ["notes.md", "notes 2.md"]) writeFileSync(join(root, n, f), "the old one\n");
  }
  for (const n of ["C", "a", "My Files"]) {
    mkdirSync(join(root, n), { recursive: true });
    writeFileSync(join(root, n, "other.txt"), "");
  }
  // what the tree's own check says of each path asked here, run on the real folders
  const codes = {};
  if (proc) {
    const cmd = readExpression(proc, proc.indexOf("command:") + "command:".length).expr;
    for (const n of names)
      for (const f of ["notes.md", "notes 2.md", "notes 3.md", "fresh.md", "inside"]) {
        const path = join(root, n, f);
        const argv = inScope({ onDisk: { path } }, "", `return (${cmd});`)();
        codes[path] = spawnSync(argv[0], argv.slice(1)).status;
      }
  }
  const stubs = {
    ...module("qs.modules.common.functions", { FileUtils: `QtObject { id: root; ${["fileUrl", "folderUrl", "listedPath"].map(n => fn(utils, n)).join("\n")} }` }),
    ...module("Quickshell.Io", { FakeDisk: `QtObject { property var codes: (${JSON.stringify(codes)}); property var unknown: [] }` }, {
      // as Quickshell 0.3.2's: the process is gone (not running) when exited comes
      Process: `Item {
    property var command: []
    property bool running: false
    signal exited(int code, int status)
    onRunningChanged: if (running) Qt.callLater(() => {
        const p = command[command.length - 1], c = FakeDisk.codes[p];
        if (c === undefined) FakeDisk.unknown.push(p);
        running = false;
        exited(c === undefined ? 99 : c, 0);
    })
}`,
    }),
  };
  const scene = `import QtQuick
import QtTest
import Qt.labs.folderlistmodel
import Quickshell.Io
import qs.modules.common.functions
Item {
    QtObject {
        id: win
        property string folder: ${JSON.stringify(join(root, "plain"))}
        property bool forFolder: false
        property string name: ""
        property bool asking: false
        property bool answered: false
        property var answers: []
        ${decl}
        ${fn(save, "relist")}
        ${fn(save, "keepName")}
        ${fn(save, "accept")}
        ${fn(save, "keepBoth")}
        ${fn(save, "answerFree")}
        function answer(paths) { win.answers = win.answers.concat([paths]) }
        function pressKeepBoth() { ${keepBoth} }
    }
    ${objectWith(save, "id: here")}
    ${proc}
    TestCase {
        name: "save"; when: windowShown
        function at(f, name, cleared, press) {
            win.answers = []; win.asking = false; win.name = name;
            // the list as a folder still being read, or one Files can't list, gives it: nothing
            if (cleared) { win.names = ({}); win.dirs = ({}); }
            press();
            wait(150);
            return { asking: win.asking, answers: win.answers, isFolder: win.isFolder };
        }
        function test_walk() {
            const out = [];
            for (const n of ${JSON.stringify(names)}) {
                const f = ${JSON.stringify(root)} + "/" + n;
                win.folder = f;
                for (let k = 0; k < 20 && here.status === FolderListModel.Loading; k++) wait(50);
                wait(200);
                out.push({
                    listed: at(f, "notes.md", false, () => win.accept()),
                    unlisted: at(f, "notes.md", true, () => win.accept()),
                    keepBoth: at(f, "notes.md", true, () => win.pressKeepBoth()),
                    fresh: at(f, "fresh.md", false, () => win.accept()),
                    folder: at(f, "inside", true, () => win.accept()),
                });
            }
            console.log("SAID " + JSON.stringify({ out, unknown: FakeDisk.unknown }));
        }
    }
}
`;
  let said;
  try {
    said = logged(runScene({ "tst_save_as.qml": scene, ...stubs }), "SAID");
  } catch (e) {
    check("the scene ran", false, String(e.message ?? e));
  }
  if (said) {
    names.forEach((n, i) => {
      const s = said.out[i], f = join(root, n);
      check(`"${n}": Save on notes.md asks Replace / Keep both and gives nothing yet`, s.listed.asking && s.listed.answers.length === 0, JSON.stringify(s.listed));
      check(`"${n}": so it does with the list empty (a folder still being read, or one Files can't list)`, s.unlisted.asking && s.unlisted.answers.length === 0, JSON.stringify(s.unlisted));
      check(`"${n}": Keep both with the list empty gives notes 3.md, the first name free on disk`,
        JSON.stringify(s.keepBoth.answers) === JSON.stringify([[join(f, "notes 3.md")]]), JSON.stringify(s.keepBoth));
      check(`"${n}": a new name is saved at once`, !s.fresh.asking && JSON.stringify(s.fresh.answers) === JSON.stringify([[join(f, "fresh.md")]]), JSON.stringify(s.fresh));
      check(`"${n}": a folder's name with the list empty gives nothing and reads as a folder`, s.folder.answers.length === 0 && !s.folder.asking && s.folder.isFolder,
        JSON.stringify(s.folder));
    });
    check("every path checked was one the test ran the check on", said.unknown.length === 0, JSON.stringify(said.unknown));
  }
} finally {
  rmSync(root, { recursive: true, force: true });
}
done();
