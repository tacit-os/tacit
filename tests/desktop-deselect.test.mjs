// A left click on the empty desktop lets go of the desktop's files (modules/ii/background/Background.qml): the
// background's own blocks (the widget canvas, which is the tree's WidgetCanvas.qml, the area under widgets kept above a
// video, desktopRightClickArea) run under Qt's qmltestrunner offscreen, which delivers the clicks, with and without a
// video wallpaper. Qt decides which of them takes the press.
import { logged, module, objectWith, runScene, without } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a click on the empty desktop lets go of the desktop's files (Background.qml)");
const bg = read("modules/ii/background/Background.qml");
const canvasFile = read("modules/common/widgets/widgetCanvas/WidgetCanvas.qml");
const videoArea = objectWith(bg, "enabled: bgRoot.widgetsAboveVideo\n");
const canvas = without(objectWith(bg, "id: widgetCanvas"), "FadeLoader");
const rightClick = objectWith(bg, "id: desktopRightClickArea");

const stubs = {
  ...module("qs", { GlobalStates: `QtObject { property bool desktopMenuOpen: false; property var desktopMenuScreen: null; property real desktopMenuX; property real desktopMenuY }` }),
  ...module("qs.services", { DesktopIcons: `QtObject { property int cleared: 0; function clear() { cleared++ } }` }),
  ...module("qs.modules.common", {
    Config: `QtObject { property var options: ({ background: { widgetsLocked: false, showGrid: false, showSnapLines: false } }) }`,
    Appearance: `QtObject {
    readonly property var none: ({ createObject: () => null })
    property var colors: ({ colPrimary: "#88f", colLayer0Border: "#444" })
    property var animation: ({ elementMoveFast: { colorAnimation: none, numberAnimation: none }, elementMove: { duration: 0, type: 0, bezierCurve: [] } })
}`,
  }),
};

function desk(video) {
  const scene = `import QtQuick
import QtTest
import qs
import qs.services
import qs.modules.common
Item {
    id: top
    width: 800; height: 600
    QtObject { id: bgRoot; property bool widgetsAboveVideo: ${video}; property var screen: ({ name: "eDP-1" }) }
    // the other window, the widgets' over the video: none of this one's clicks reach it
    Item { id: videoWidgets; property Item contentItem: videoContent; Item { id: videoContent } }
    Item {
        id: backgroundContent
        anchors.fill: parent
        ${videoArea}
        ${canvas}
        ${rightClick}
    }
    TestCase {
        name: "desk"; when: windowShown
        function test_clicks() {
            mouseClick(top, 400, 300, Qt.LeftButton)
            const left = DesktopIcons.cleared
            mouseClick(top, 400, 300, Qt.RightButton)
            console.log("DESK " + JSON.stringify({ left, menu: GlobalStates.desktopMenuOpen }))
        }
    }
}
`;
  return logged(runScene({ "tst_desk.qml": scene, "WidgetCanvas.qml": canvasFile, ...stubs }), "DESK");
}

for (const [video, where] of [[false, "on a picture wallpaper"], [true, "on a video wallpaper (widgets in their own window)"]]) {
  try {
    const r = desk(video);
    check(`${where}, a left click on the empty desktop lets go of the files`, r.left === 1, `DesktopIcons.clear() ran ${r.left} times`);
    check(`${where}, a right click there still opens the desktop menu`, r.menu, "the menu stayed shut");
  } catch (e) {
    check(`${where}, the scene ran`, false, String(e.message ?? e));
  }
}
done();
