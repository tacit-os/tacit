// A click away from the screen-share picker (modules/ii/sharePicker/SharePickerContent.qml): its list step, the slab
// without its list and buttons, runs under qmltestrunner offscreen on a 1200 x 800 monitor, with and without the
// asking window's rectangle; Qt's own delivery decides which item takes each click.
import { logged, module, objectWith, runScene, without } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a click away from the share picker (SharePickerContent.qml)");
const src = read("modules/ii/sharePicker/SharePickerContent.qml");
const listStep = without(objectWith(src, 'visible: root.step === "list"'), "ColumnLayout");

const scene = `import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.functions
Item {
    id: root
    width: 1200; height: 800
    property var askRect: null
    property string step: "list"
    property bool entered: true
    readonly property color slab: "#202020"
    property int backedOut: 0
    signal cancelled()
    onCancelled: backedOut++
    QtObject { id: chrome; property real wantH: 300 }
    ${listStep}
    TestCase {
        name: "away"; when: windowShown
        function test_away() {
            const out = {}
            // no asking window: the slab sits in the middle (340..860 x 230..570)
            mouseClick(root, 600, 400); out.slabAlone = root.backedOut
            mouseClick(root, 50, 50); out.desktop = root.backedOut
            // the asker at 100,100 600x500: the slab over it (140..660 x 180..520)
            root.askRect = Qt.rect(100, 100, 600, 500)
            wait(20)
            mouseClick(root, 400, 350); out.slab = root.backedOut
            mouseClick(root, 110, 110); out.asker = root.backedOut
            mouseClick(root, 1100, 700); out.elsewhere = root.backedOut
            console.log("AWAY " + JSON.stringify(out))
        }
    }
}
`;
try {
  const r = logged(runScene({
    "tst_away.qml": scene,
    ...module("qs.modules.common", { Appearance: `QtObject { property var colors: ({ colScrim: "#000000", colOnLayer0: "#ffffff" }) }` }),
    ...module("qs.modules.common.functions", { ColorUtils: `QtObject { function transparentize(c, a) { return c } }` }),
  }), "AWAY");
  check("a click on the slab is not a click away", r.slabAlone === 0 && r.slab === r.desktop, JSON.stringify(r));
  check("with no asking window, a click on the desktop backs out", r.desktop === 1, `backed out ${r.desktop} times`);
  check("a click on the asking window backs out, as before", r.asker === r.slab + 1, JSON.stringify(r));
  check("a click on the monitor outside the asking window backs out", r.elsewhere === r.asker + 1, JSON.stringify(r));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
