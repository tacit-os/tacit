// A click on the control panel's open submenu card (modules/ii/sidebarRight/SidebarRightContent.qml): the file's
// submenuLayer, the backdrop and the card without its sections, runs under qmltestrunner offscreen with the Wi-Fi card
// open; Qt's own delivery decides whether the card or the backdrop takes each click.
import { logged, module, objectWith, runScene, without } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a click on the control panel's open card (SidebarRightContent.qml)");
const src = read("modules/ii/sidebarRight/SidebarRightContent.qml");
const layer = without(objectWith(src, "id: submenuLayer"), "ColumnLayout");

const scene = `import QtQuick
import QtTest
import stand.ins
Item {
    id: root
    width: 400; height: 700
    property var sectionFlags: ["showWifiDialog", "showVpn"]
    property bool showWifiDialog: true
    property bool showVpn: false
    property real sidebarPadding: 16
    property real togglesWidth: 360
    Item { id: togglesBlock; width: 360; height: 100 }
    // the sections' column: the card is its height and the padding round it (16..376 x 108..340)
    QtObject { id: submenuColumn; property real implicitHeight: 200 }
    ${layer}
    TestCase {
        name: "card"; when: windowShown
        function test_card() {
            const out = {}
            wait(50)
            mouseClick(root, 22, 114); out.padding = root.showWifiDialog
            root.showWifiDialog = true; wait(20)
            mouseClick(root, 200, 220); out.middle = root.showWifiDialog
            root.showWifiDialog = true; wait(20)
            mouseClick(root, 200, 600); out.outside = root.showWifiDialog
            console.log("CARD " + JSON.stringify(out))
        }
    }
}
`;
try {
  const r = logged(runScene({
    "tst_card.qml": scene,
    ...module("stand.ins", {
      Kit: `QtObject { property var tokens: ({ space: { m: 8 }, radius: { panel: 16 } }); function ms(x) { return 0 } function motion(n) { return { ms: 0 } } }`,
      Appearance: `QtObject { property var colors: ({ colLayer3Base: "#303030" }) }`,
    }),
  }), "CARD");
  check("a click on the card's padding keeps it open", r.padding === true, JSON.stringify(r));
  check("so does one on the card's empty middle (a heading, the space under a short list)", r.middle === true, JSON.stringify(r));
  check("a click outside the card still closes it", r.outside === false, JSON.stringify(r));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
