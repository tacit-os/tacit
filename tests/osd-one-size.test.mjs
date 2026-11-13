// The volume OSD's window keeps one size when the volume protection's message appears in it (modules/ii/onScreenDisplay/
// OnScreenDisplay.qml): the window's own size bindings and its content block, laid out by Qt's qml tool offscreen, with a
// stand-in meter of OsdValueIndicator's size and a stand-in for the shell's text and symbol types. Hyprland animates a
// layer window that changes size, so the pill would stretch and swing as the message came.
import { readExpression } from "./lib/qml.mjs";
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the volume OSD's window when the protection message comes (OnScreenDisplay.qml)");
const src = read("modules/ii/onScreenDisplay/OnScreenDisplay.qml");
const win = objectWith(src, "id: osdRoot");
const line = key => { const m = new RegExp(`^ {12}${key}:\\s*`, "m").exec(win); return readExpression(win, m.index + m[0].length).expr; };
const content = objectWith(win, "id: columnLayout");
const stubs = {
  ...module("qs", { GlobalStates: `QtObject { property bool osdVolumeOpen: true }` }),
  ...module("qs.modules.common", { Appearance: `QtObject {
    property var m3colors: ({ m3error: "#a33", m3onError: "#fff" })
    property var font: ({ pixelSize: { hugeass: 23 } })
    property var rounding: ({ normal: 12 })
}` }),
  ...module("qs.modules.common.widgets", {}, {
    StyledText: `Text { font.pixelSize: 15 }`,
    MaterialSymbol: `Text { property real iconSize: 16; font.pixelSize: iconSize }`,
    StyledRectangularShadow: `Item { property var target }`,
  }),
  // OsdValueIndicator's size: osdWidth 180 + 4 elevation margins + 80, a 40 px row in its margins
  "indicators/VolumeIndicator.qml": `import QtQuick\nItem { implicitWidth: 300; implicitHeight: 56 }\n`,
};
const scene = `import QtQuick
import QtQuick.Layouts
import qs
import qs.modules.common
import qs.modules.common.widgets
Item {
    width: 600; height: 400
    QtObject {
        id: root
        property string protectionMessage: ""
        property string currentIndicator: "volume"
        property var indicators: [{ id: "volume", sourceUrl: "indicators/VolumeIndicator.qml" }]
    }
    Item {
        id: osdRoot
        implicitWidth: ${line("implicitWidth")}
        implicitHeight: ${line("implicitHeight")}
        ${content}
    }
    property var sizes: []
    function measure(next) { sizes.push({ w: osdRoot.implicitWidth, h: osdRoot.implicitHeight, shown: osdValuesWrapper.implicitHeight }); root.protectionMessage = next }
    Timer { interval: 100; running: true; onTriggered: measure("a jump over 10%") }
    Timer { interval: 200; running: true; onTriggered: measure("the limit is 100%, and far more words than one line of the pill can hold") }
    Timer { interval: 300; running: true; onTriggered: { measure(""); console.log("OSD " + JSON.stringify(sizes)); Qt.quit() } }
}
`;
try {
  const [before, short, long] = logged(runScene({ "osd.qml": scene, ...stubs }), "OSD");
  const say = s => `${s.w} x ${s.h}`;
  check("the window is the same size before and with the message", say(before) === say(short), `${say(before)}, then ${say(short)}`);
  check("and with a message too long for one line", say(before) === say(long), `${say(before)}, then ${say(long)}`);
  check("the message still shows, under the pill", short.shown > before.shown, `the part shown is ${before.shown} px tall, then ${short.shown}`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
