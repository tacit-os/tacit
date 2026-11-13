// The volume OSD stays up when it opens under a pointer resting there (modules/ii/onScreenDisplay/OnScreenDisplay.qml):
// the meter's own MouseArea, made by a Loader as the OSD's window is made per open, runs under Qt's qmltestrunner
// offscreen. The pointer is put where the meter will be and the meter opens under it, and Qt delivers what a still
// pointer gets when something appears under it (Qt 6.12: an enter and a position, both where the pointer is); then the
// pointer moves over it, and later comes into it from outside.
import { logged, module, objectWith, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the volume OSD opening under a resting pointer (OnScreenDisplay.qml)");
const src = read("modules/ii/onScreenDisplay/OnScreenDisplay.qml");
const area = objectWith(src.slice(src.indexOf("id: osdValuesWrapper")), "hoverEnabled: true");
const scene = `import QtQuick
import QtTest
import qs
Item {
    id: top
    width: 800; height: 300
    Loader {
        active: GlobalStates.osdVolumeOpen
        x: 250; width: 300; height: 56
        sourceComponent: Item {
            id: osdValuesWrapper
            width: 300; height: 56
            ${area}
        }
    }
    TestCase {
        name: "osd"; when: windowShown
        function test_resting() {
            mouseMove(top, 400, 30)          // resting where the meter opens
            wait(100)
            GlobalStates.osdVolumeOpen = true
            wait(300)
            const stayed = GlobalStates.osdVolumeOpen
            mouseMove(top, 420, 35)          // then moved over it
            wait(100)
            const movedAway = !GlobalStates.osdVolumeOpen
            mouseMove(top, 400, 200)         // away, the meter opened again, and the pointer passing into it
            wait(100)
            GlobalStates.osdVolumeOpen = true
            wait(300)
            mouseMove(top, 400, 50); mouseMove(top, 404, 40); mouseMove(top, 408, 30)
            wait(100)
            console.log("OSD " + JSON.stringify({ stayed, movedAway, passedIn: !GlobalStates.osdVolumeOpen }))
        }
    }
}
`;
try {
  const r = logged(runScene({ "tst_osd.qml": scene, ...module("qs", { GlobalStates: `QtObject { property bool osdVolumeOpen: false }` }) }), "OSD");
  check("opened under a resting pointer, the meter stays up", r.stayed, "it closed as it opened");
  check("the pointer then moving over it puts it away, as before", r.movedAway, "it stayed up");
  check("and so does a pointer coming in from outside", r.passedIn, "it stayed up");
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
