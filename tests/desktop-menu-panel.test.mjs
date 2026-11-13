// A press on the desktop menu's side panel that misses its controls does not close the menu
// (modules/ii/desktopMenu/DesktopMenu.qml): the menu window's own click-away area and its submenuLoader, in the order the
// file declares them, run under Qt's qmltestrunner offscreen, which delivers the clicks. The panel loaded is a stand-in
// with the shape of WidgetsPanel.qml and WallpaperPanel.qml: a ground, a heading, rows 2 px apart, 14 px of padding.
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a press on the desktop menu's side panel (DesktopMenu.qml)");
const src = read("modules/ii/desktopMenu/DesktopMenu.qml");
const away = objectWith(src, "onClicked: GlobalStates.desktopMenuOpen = false");
const loader = objectWith(src, "id: submenuLoader");
const stubs = {
  ...module("qs", { GlobalStates: `QtObject { property bool desktopMenuOpen: true }` }),
  ...module("qs.modules.common", { Appearance: `QtObject {
    readonly property var none: ({ createObject: () => null })
    property var animation: ({ elementMoveEnter: { numberAnimation: none }, elementMoveFast: { numberAnimation: none } })
}` }),
};
const scene = `import QtQuick
import QtQuick.Layouts
import QtTest
import qs
import qs.modules.common
Item {
    id: menuWindow
    width: 1000; height: 700
    property Component openSubmenuComponent: panel
    property real submenuWidth: 284
    property real submenuAnchorY: 100
    property var rows: []
    Timer { id: submenuCloseTimer; interval: 250 }
    Component {
        id: panel
        Item {
            implicitHeight: col.implicitHeight + 28
            Rectangle { anchors.fill: parent; color: "#223" }
            ColumnLayout {
                id: col
                anchors { fill: parent; margins: 14 }
                spacing: 8
                Text { text: "On the desktop"; Layout.preferredHeight: 20 }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    MouseArea { Layout.fillWidth: true; Layout.preferredHeight: 40; onClicked: menuWindow.rows.push(1) }
                    MouseArea { Layout.fillWidth: true; Layout.preferredHeight: 40; onClicked: menuWindow.rows.push(2) }
                }
            }
        }
    }
    ${away}
    Rectangle { id: menuCard; x: 300; y: 100; width: 348; height: 300 }
    ${loader}
    TestCase {
        name: "panel"; when: windowShown
        function test_presses() {
            tryVerify(() => submenuLoader.item !== null)
            const out = {}
            // in the panel: its heading, the 2 px between its rows, its left padding, a row; and the desktop past it
            for (const [what, x, y] of [["heading", 100, 24], ["gap", 100, 83], ["padding", 5, 60], ["row", 100, 60], ["outside", -400, 450]]) {
                GlobalStates.desktopMenuOpen = true
                mouseClick(menuWindow, submenuLoader.x + x, submenuLoader.y + y, Qt.LeftButton)
                out[what] = GlobalStates.desktopMenuOpen
            }
            out.rows = menuWindow.rows
            console.log("PANEL " + JSON.stringify(out))
        }
    }
}
`;
try {
  const r = logged(runScene({ "tst_panel.qml": scene, ...stubs }), "PANEL");
  for (const what of ["heading", "gap", "padding"])
    check(`a press on the panel's ${what === "gap" ? "gap between two rows" : what} leaves the menu open`, r[what] === true, "the menu closed");
  check("a press on a row is that row's", r.row === true && r.rows.join() === "1", `rows clicked: ${r.rows.join(", ") || "none"}`);
  check("a press on the desktop past the panel still closes the menu", r.outside === false, "it stayed open");
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
