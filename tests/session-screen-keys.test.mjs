// The Session screen's keys after a click on one of its buttons (modules/ii/sessionScreen/SessionScreen.qml): the file's
// own key handler (the `keys` item), its BigAction and SmallAction on the tree's RippleButton, under Qt's qmltestrunner
// offscreen, which delivers the clicks and keys as a person's: Qt decides who has the keyboard after the click.
import { matchBrace } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Session screen's Esc and arrows after a click (SessionScreen.qml)");
const src = read("modules/ii/sessionScreen/SessionScreen.qml");
const component = name => { const at = src.indexOf(`component ${name}:`); return src.slice(at, matchBrace(src, src.indexOf("{", at)) + 1); };
const keys = objectWith(src, "id: keys");

const colors = ["colLayer1Hover", "colPrimary", "colPrimaryHover", "colLayer1Active", "colPrimaryActive", "colOutlineVariant", "colLayer2",
  "colOnPrimary", "colOnSurface", "colSubtext"];
const files = {
  ...module("qs.modules.common", {
    Appearance: `QtObject {
    property var colors: (${JSON.stringify(Object.fromEntries(colors.map(c => [c, "#808080"])))})
    property var rounding: ({ small: 4, full: 999 })
    property var font: ({ pixelSize: { smaller: 12 } })
    property var animation: ({ elementMoveEnter: { type: 0 }, elementMoveFast: { colorAnimation: { createObject: () => null } } })
    property var animationCurves: ({ standardDecel: [0, 0, 1, 1, 1, 1] })
}`,
  }),
  ...module("qs.modules.common.functions", { ColorUtils: `QtObject { function transparentize(c, a) { return c } }` }),
  ...module("qs.modules.common.widgets", {}, { StyledText: `Text {}`, MaterialSymbol: `Text { property real iconSize }` }),
  "qs/modules/common/widgets/RippleButton.qml": read("modules/common/widgets/RippleButton.qml"),
};
files["qs/modules/common/widgets/qmldir"] += "RippleButton 1.0 RippleButton.qml\n";

const scene = `import QtQuick
import QtTest
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
Item {
    id: top
    width: 600; height: 300
    // the sheet's state and actions, as PanelWindow sessionRoot has them
    QtObject {
        id: sessionRoot
        property var actions: [0, 1, 2, 3, 4, 5, 6, 7].map(i => ({ icon: "x", label: "action " + i }))
        property int focusIndex: 3
        property int armedIndex: -1
        property string waitingFor: ""
        property int hidden: 0
        function hide() { hidden++ }
        function activate(i) { armedIndex = i; focusIndex = i }
        function shown(i) { return true }
    }
    ${keys}
    Row {
        y: 100
        spacing: 20
        BigAction { id: shutDown; actionIndex: 0 }
        SmallAction { id: logOut; actionIndex: 4; implicitWidth: 80 }
    }
    ${component("BigAction")}
    ${component("SmallAction")}
    TestCase {
        name: "keys"; when: windowShown
        function test_keys() {
            const out = {}
            keyClick(Qt.Key_Left)
            out.before = sessionRoot.focusIndex
            mouseClick(shutDown)
            out.armed = sessionRoot.armedIndex
            keyClick(Qt.Key_Right)
            out.right = sessionRoot.focusIndex
            keyClick(Qt.Key_Escape)
            out.escAfterBig = sessionRoot.hidden
            mouseClick(logOut)
            keyClick(Qt.Key_Escape)
            out.escAfterSmall = sessionRoot.hidden
            console.log("KEYS " + JSON.stringify(out))
        }
    }
}
`;
try {
  const r = logged(runScene({ "tst_keys.qml": scene, ...files }), "KEYS");
  check("before any click, Left moves from Lock to Sleep", r.before === 2, `focus on ${r.before}`);
  check("a click on Shut down arms it", r.armed === 0, `armed ${r.armed}`);
  check("then Right moves to the next action", r.right === 1, `focus on ${r.right}`);
  check("and Esc cancels", r.escAfterBig === 1, `Esc closed it ${r.escAfterBig} times`);
  check("Esc cancels after a click on Log out too", r.escAfterSmall === 2, `Esc closed it ${r.escAfterSmall} times in all`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
