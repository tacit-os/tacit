// Pinax's drops (FilesWindow.qml's dropZone, FilesRow.qml's DropArea "into"): both blocks taken from the tree and put in
// a window run by Qt's own qml tool offscreen, with the list and the folder area's ground in the order FilesWindow
// declares them, and a drag dropped on a folder row, a file row and the ground under the rows. A drop on a folder row
// goes into that folder; elsewhere, into the folder shown. Qt decides which DropArea gets a drag, so Qt runs it here.
import { spawnSync } from "child_process";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { matchBrace } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a drop on a folder row in Pinax goes into that folder (FilesWindow.qml, FilesRow.qml)");
const win = read("modules/ii/files/FilesWindow.qml"), row = read("modules/ii/files/FilesRow.qml");
// the "DropArea {" block holding `id`
const dropArea = (src, id) => { const at = src.lastIndexOf("DropArea {", src.indexOf(`id: ${id}`)); return src.slice(at, matchBrace(src, at + "DropArea ".length) + 1); };
const zone = dropArea(win, "dropZone"), into = dropArea(row, "into");
const zoneFirst = win.indexOf("id: dropZone") < win.indexOf("id: list\n");
const scene = `import QtQuick
Window {
    id: root
    width: 400; height: 400; visible: true
    property var got: []
    QtObject { id: win; property string folder: "/home/a/Documents"; function dropIn(urls, mods, internal, dest) { root.got.push(dest); } }
    Item {
        id: filesArea
        anchors.fill: parent
        ${zoneFirst ? zone : ""}
        ListView {
            id: list
            anchors.fill: parent
            model: ["notes.txt", "Projects", "photo.jpg"]
            delegate: Item {
                id: row
                required property int index
                required property string modelData
                readonly property bool fileIsDir: modelData === "Projects"
                signal droppedInto(int index, var urls, int modifiers, bool internal)
                onDroppedInto: (i, urls, mods, internal) => win.dropIn(urls, mods, internal, win.folder + "/" + modelData)
                width: 400; height: 40
                ${into}
            }
        }
        ${zoneFirst ? "" : zone}
    }
    Item { id: dragger; width: 10; height: 10; Drag.keys: ["text/uri-list"]; Drag.hotSpot.x: 5; Drag.hotSpot.y: 5 }
    function dropAt(x, y) { dragger.x = 200; dragger.y = 395; dragger.Drag.active = true; dragger.x = x - 5; dragger.y = y - 5; dragger.Drag.drop(); dragger.Drag.active = false; }
    Timer {
        interval: 100; running: true
        onTriggered: {
            root.dropAt(50, 60);    // Projects, a folder
            root.dropAt(50, 20);    // notes.txt, a file
            root.dropAt(50, 300);   // the ground under the rows
            console.log("DROPS " + JSON.stringify(root.got));
            Qt.quit();
        }
    }
}
`;
const qml = ["/usr/lib/qt6/bin/qml", ...(process.env.PATH ?? "").split(":").map(d => join(d, "qml"))].find(existsSync);
const tmp = mkdtempSync(join(tmpdir(), "tacit-drop-"));
try {
  writeFileSync(join(tmp, "drop.qml"), scene);
  const r = spawnSync(qml ?? "qml", [join(tmp, "drop.qml")], { encoding: "utf8", timeout: 20000,
    env: { PATH: process.env.PATH, HOME: tmp, QT_QPA_PLATFORM: "offscreen", QT_FORCE_STDERR_LOGGING: "1" } });
  const line = `${r.stdout}${r.stderr}`.split("\n").find(l => l.includes("DROPS "));
  if (!line) throw new Error(`qml said: ${(r.error?.message ?? `${r.stdout}${r.stderr}`).trim().split("\n").slice(0, 3).join(" | ")}`);
  const [onFolder, onFile, onGround] = JSON.parse(line.slice(line.indexOf("DROPS ") + 6));
  check("a drop on the Projects row goes into Projects", onFolder === "/home/a/Documents/Projects", `it went to ${onFolder}`);
  check("a drop on a file's row goes into the folder shown", onFile === "/home/a/Documents", `it went to ${onFile}`);
  check("a drop on the ground under the rows goes into the folder shown", onGround === "/home/a/Documents", `it went to ${onGround}`);
} catch (e) {
  check("the window ran", false, String(e.message ?? e));
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
done();
