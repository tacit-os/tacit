// Enter on the numeric keypad does what Return does in Graphis (Go to file and Search, the project picker, the file
// tree) and in Activity (rows, tabs, buttons). Qt sends it as Key_Enter, which Keys.onReturnPressed never sees: the
// Finder's own key lines run under qmltestrunner offscreen with a keypad Enter, and every Keys.onReturnPressed in these
// files is read for a Keys.onEnterPressed beside it that does the same.
import { logged, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the keypad's Enter does what Return does (Graphis, Activity)");
const files = ["modules/code/Finder.qml", "modules/code/ProjectPicker.qml", "modules/code/CodeTree.qml",
  "modules/activity/Line.qml", "modules/activity/Verb.qml", "modules/activity/Tabs.qml", "activity.qml"];
for (const f of files) {
  const lines = read(f).split("\n");
  lines.forEach((l, i) => {
    const m = /^\s*Keys\.onReturnPressed:\s*(.*)$/.exec(l);
    if (!m) return;
    const near = [lines[i - 1], lines[i + 1]].map(x => /^\s*Keys\.onEnterPressed:\s*(.*)$/.exec(x ?? "")?.[1]);
    check(`${f}:${i + 1} Enter as Return (${m[1].trim().slice(0, 50)})`, near.includes(m[1]), "no Keys.onEnterPressed beside it");
  });
}

// the Go to file box: its Keys lines, with the Finder's choose() written down
const finder = read("modules/code/Finder.qml").split("\n");
const at = finder.findIndex(l => /Keys\.onReturnPressed: finder\.choose/.test(l));
const keyLines = finder.slice(Math.max(0, at - 1), at + 2).filter(l => /^\s*Keys\.on(Return|Enter)Pressed:/.test(l)).join("\n");
const scene = `import QtQuick
import QtTest
Item {
    width: 300; height: 100
    QtObject { id: finder; property var chose: []; function choose(i) { chose = chose.concat([i]) } }
    QtObject { id: list; property int currentIndex: 2 }
    TextInput {
        id: box
        width: 300; height: 30
        focus: true
        text: "Finder.qml"
${keyLines}
    }
    TestCase {
        name: "keypad"; when: windowShown
        function test_enter() {
            box.forceActiveFocus();
            keyClick(Qt.Key_Enter, Qt.KeypadModifier);
            keyClick(Qt.Key_Return);
            console.log("KEYPAD " + JSON.stringify(finder.chose));
        }
    }
}
`;
try {
  const chose = logged(runScene({ "tst_keypad.qml": scene }), "KEYPAD");
  check("in Go to file, the keypad's Enter opens the row as Return does", chose.length === 2 && chose.every(i => i === 2), `choose() ran with ${JSON.stringify(chose)}`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
