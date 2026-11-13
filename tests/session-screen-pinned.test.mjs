// The Session screen stays on the screen it opened on (modules/ii/sessionScreen/SessionScreen.qml): the file's own
// top-level properties and bindings, and its window's screen and size bindings in a Loader as the file has it, run under
// Qt's qml tool offscreen with stand-ins for Quickshell's screens and Hyprland's focused monitor, two monitors.
import { readExpression } from "./lib/qml.mjs";
import { logged, module, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Session screen when the focus moves to another monitor (SessionScreen.qml)");
const src = read("modules/ii/sessionScreen/SessionScreen.qml");
// the Scope's own lines, before its Loader
const top = src.slice(src.indexOf("    id: root\n") + "    id: root\n".length, src.indexOf("    Loader {"));
const win = src.slice(src.indexOf("sourceComponent: PanelWindow {"));
const line = key => readExpression(win, win.indexOf(`\n            ${key}:`) + key.length + 14).expr;

const files = {
  ...module("qs", { GlobalStates: `QtObject { property bool sessionOpen: false }` }),
  ...module("qs.services", { WM: `QtObject { property string compositor: "hyprland" }`, NiriBackend: `QtObject { property var focusedMonitor: null }` }),
  ...module("Quickshell", { Quickshell: `QtObject { property var screens: [{ name: "eDP-1", width: 1920, height: 1080 }, { name: "DP-2", width: 2560, height: 1440 }] }` }),
  ...module("Quickshell.Hyprland", { Hyprland: `QtObject { property var focusedMonitor: ({ name: "eDP-1" }) }` }),
};
const scene = `import QtQuick
import qs
import qs.services
import Quickshell
import Quickshell.Hyprland
Item {
    id: root
    ${top}
    Loader {
        id: sessionLoader
        active: GlobalStates.sessionOpen
        sourceComponent: QtObject {
            property var screen: ${line("screen")}
            property real implicitWidth: ${line("implicitWidth")}
        }
    }
    property var seen: []
    function note(what) { seen.push({ what, screen: sessionLoader.item?.screen?.name ?? null, width: sessionLoader.item?.implicitWidth ?? 0 }) }
    Timer { interval: 50; running: true; onTriggered: GlobalStates.sessionOpen = true }
    Timer { interval: 100; running: true; onTriggered: { root.note("opened"); Hyprland.focusedMonitor = { name: "DP-2" } } }
    Timer { interval: 150; running: true; onTriggered: { root.note("focus moved"); GlobalStates.sessionOpen = false } }
    Timer { interval: 200; running: true; onTriggered: GlobalStates.sessionOpen = true }
    Timer { interval: 250; running: true; onTriggered: { root.note("opened again"); console.log("SESSION " + JSON.stringify(root.seen)); Qt.quit() } }
}
`;
try {
  const [opened, moved, again] = logged(runScene({ "session.qml": scene, ...files }), "SESSION");
  const say = s => `${s.screen} at ${s.width} wide`;
  check("it opens on the focused monitor", opened.screen === "eDP-1" && opened.width === 1920, say(opened));
  check("and stays there when the focus moves to the other monitor", moved.screen === "eDP-1" && moved.width === 1920, say(moved));
  check("opened again, it opens where the focus is now", again.screen === "DP-2" && again.width === 2560, say(again));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
