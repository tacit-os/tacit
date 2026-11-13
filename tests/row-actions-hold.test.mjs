// The control panel's Bluetooth and VPN rows open their actions (Cancel, Trusted, Forget, "On when not trusted") without
// a right click: the tree's RippleButton runs under qmltestrunner offscreen, with altOnHold on as those rows set it,
// beside one without it; Qt's own delivery carries the held press, the right click and the keys.
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Bluetooth and VPN rows' actions by touch and keyboard (RippleButton.qml)");
for (const file of ["modules/ii/sidebarRight/bluetoothDevices/BluetoothSection.qml", "modules/ii/sidebarRight/vpn/VpnSection.qml"]) {
  const line = objectWith(read(file), "altAction: () => { row.more = !row.more; }");
  check(`${file.replace(/.*\//, "")}: the row whose right click opens its actions also opens them on a hold`, /\baltOnHold:\s*true\b/.test(line), "no altOnHold");
}

const colors = ["colLayer1Hover", "colPrimary", "colPrimaryHover", "colLayer1Active", "colPrimaryActive", "colOutlineVariant"];
const files = {
  ...module("qs.modules.common", {
    Appearance: `QtObject {
    property var colors: (${JSON.stringify(Object.fromEntries(colors.map(c => [c, "#808080"])))})
    property var rounding: ({ small: 4 })
    property var animation: ({ elementMoveEnter: { type: 0 }, elementMoveFast: { colorAnimation: { createObject: () => null } } })
    property var animationCurves: ({ standardDecel: [0, 0, 1, 1, 1, 1] })
}`,
  }),
  ...module("qs.modules.common.functions", { ColorUtils: `QtObject { function transparentize(c, a) { return c } }` }),
  ...module("qs.modules.common.widgets", {}, { StyledText: `Text {}` }),
  "qs/modules/common/widgets/RippleButton.qml": read("modules/common/widgets/RippleButton.qml"),
};
files["qs/modules/common/widgets/qmldir"] += "RippleButton 1.0 RippleButton.qml\n";

const scene = `import QtQuick
import QtTest
import qs.modules.common.widgets
Item {
    width: 400; height: 300
    RippleButton { id: row; width: 300; height: 40; property int clicks: 0; property int alts: 0; onClicked: clicks++; altAction: () => { alts++ } }
    RippleButton { id: plain; y: 100; width: 300; height: 40; property int clicks: 0; property int alts: 0; onClicked: clicks++; altAction: () => { alts++ } }
    // a button with keys of its own, as the panel's pills move by the arrows
    RippleButton { id: pill; y: 200; width: 40; height: 40; property int lefts: 0; Keys.onPressed: event => { if (event.key === Qt.Key_Left) { lefts++; event.accepted = true } } }
    TestCase {
        name: "hold"; when: windowShown
        function test_hold() {
            if ("altOnHold" in row) row.altOnHold = true   // as the Bluetooth and VPN rows set it
            const out = {}, at = b => [b.clicks, b.alts]
            mousePress(row, 50, 20); wait(1100); mouseRelease(row, 50, 20); out.hold = at(row)
            mouseClick(row, 50, 20); out.click = at(row)
            mousePress(row, 50, 20, Qt.RightButton); wait(1100); mouseRelease(row, 50, 20, Qt.RightButton); out.right = at(row)
            row.forceActiveFocus(Qt.TabFocusReason)
            keyClick(Qt.Key_Menu); out.menu = at(row)
            keyClick(Qt.Key_F10, Qt.ShiftModifier); out.shiftF10 = at(row)
            mousePress(plain, 50, 20); wait(1100); mouseRelease(plain, 50, 20); out.plain = at(plain)
            pill.forceActiveFocus(Qt.TabFocusReason); keyClick(Qt.Key_Left); out.ownKeys = pill.lefts
            console.log("HOLD " + JSON.stringify(out))
        }
    }
}
`;
try {
  const r = logged(runScene({ "tst_hold.qml": scene, ...files }), "HOLD");
  const is = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  check("a held press opens the row's actions, and its release clicks nothing", is(r.hold, [0, 1]), `clicks, actions: ${r.hold}`);
  check("a short click is still a click", is(r.click, [1, 1]), `${r.click}`);
  check("a right click, held or not, opens them once, as before", is(r.right, [1, 2]), `${r.right}`);
  check("with the keyboard on the row, the Menu key opens them", is(r.menu, [1, 3]), `${r.menu}`);
  check("and so does Shift+F10", is(r.shiftF10, [1, 4]), `${r.shiftF10}`);
  check("a button without altOnHold clicks on a held press, as every other button did", is(r.plain, [1, 0]), `${r.plain}`);
  check("and a button's own key handler still runs", r.ownKeys === 1, `Left heard ${r.ownKeys} times`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
