// Esc in the control panel while a pill holds the keyboard: the panel's own Loader handler (modules/ii/sidebarRight/
// SidebarRight.qml) around the content's body handler (SidebarRightContent.qml), with a focused button standing for the
// pill, under qmltestrunner offscreen; Qt's own key delivery carries each Esc up from the pill.
import { matchBrace } from "./lib/qml.mjs";
import { logged, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== Esc in the control panel with a pill focused (SidebarRightContent.qml)");
const handlerAfter = (src, marker) => {
  const at = src.indexOf("Keys.onPressed:", src.indexOf(marker)), open = src.indexOf("{", src.indexOf("=>", at));
  return src.slice(at, matchBrace(src, open) + 1);
};
const loaderKeys = handlerAfter(read("modules/ii/sidebarRight/SidebarRight.qml"), "id: sidebarContentLoader");
const bodyKeys = handlerAfter(read("modules/ii/sidebarRight/SidebarRightContent.qml"), "id: body");

const scene = `import QtQuick
import QtTest
Item {
    width: 400; height: 400
    QtObject { id: panelWindow; property int hidden: 0; function hide() { hidden++ } }
    Item {
        id: sidebarContentLoader
        anchors.fill: parent
        ${loaderKeys}
        Item {
            id: root
            anchors.fill: parent
            property var sectionFlags: ["showWifiDialog", "showVpn"]
            property bool showWifiDialog: false
            property bool showVpn: false
            property bool drawerOpen: false
            property bool editMode: false
            function doUndo() {}
            Item {
                id: body
                anchors.fill: parent
                ${bodyKeys}
                Rectangle { id: pill; width: 40; height: 40 }
            }
        }
    }
    TestCase {
        name: "esc"; when: windowShown
        function test_esc() {
            const out = {}
            root.showWifiDialog = true; root.drawerOpen = true; root.editMode = true
            pill.forceActiveFocus()
            keyClick(Qt.Key_Escape); out.section = [root.showWifiDialog, panelWindow.hidden]
            keyClick(Qt.Key_Escape); out.drawer = [root.drawerOpen, panelWindow.hidden]
            keyClick(Qt.Key_Escape); out.edit = [root.editMode, panelWindow.hidden]
            keyClick(Qt.Key_Escape); out.nothing = panelWindow.hidden
            console.log("ESC " + JSON.stringify(out))
        }
    }
}
`;
try {
  const r = logged(runScene({ "tst_esc.qml": scene }), "ESC");
  check("the first Esc folds the open section, the panel stays", r.section[0] === false && r.section[1] === 0, JSON.stringify(r.section));
  check("the next folds the drawer", r.drawer[0] === false && r.drawer[1] === 0, JSON.stringify(r.drawer));
  check("the next ends edit mode", r.edit[0] === false && r.edit[1] === 0, JSON.stringify(r.edit));
  check("and with nothing left to fold, Esc closes the panel", r.nothing === 1, `the panel was closed ${r.nothing} times`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
