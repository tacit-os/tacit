// On a touch screen a finger moves the Viewer as a touchpad's two do (modules/viewer/Viewer.qml): the Viewer's own
// one-finger DragHandler runs under qmltestrunner offscreen, whose touch points go through Qt's own delivery, with the
// roll's swipe, swipeEnd and inside written down: a sideways drag on a picture, an upward one on a PDF's page, and a
// sideways one on a zoomed picture; and a mouse drag, which moves nothing as before.
import { logged, runScene } from "./lib/qtscene.mjs";
import { matchBrace } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== a finger drags the Viewer's roll and pages (Viewer.qml)");
const src = read("modules/viewer/Viewer.qml");
// the root's DragHandler, the one after its PinchHandler
const at = src.indexOf("DragHandler {", src.indexOf("    PinchHandler {"));
const handler = src.slice(at, matchBrace(src, src.indexOf("{", at)) + 1);
function drag(kind, zoom, dx, dy, mouse = false) {
  const scene = `import QtQuick
import QtTest
Item {
    id: vw
    width: 800; height: 600
    property string kind: "${kind}"
    property real zoom: ${zoom}
    property bool bare: true
    property real panX: 0
    property var did: []
    function swipe(dx, phase, now) { did = did.concat([["swipe", dx]]) }
    function swipeEnd() { did = did.concat([["end", 0]]) }
    function inside(dy, touch) { did = did.concat([["inside", dy]]) }
    function clampPan() {}
    ${handler}
    TestCase {
        name: "touch"; when: windowShown
        function test_drag() {
            if (${mouse}) {
                mousePress(vw, 400, 300);
                for (let k = 1; k <= 10; k++) { mouseMove(vw, 400 + ${dx} * k / 10, 300 + ${dy} * k / 10); wait(10); }
                mouseRelease(vw, 400 + ${dx}, 300 + ${dy});
            } else {
                const t = touchEvent(vw);
                t.press(0, vw, 400, 300).commit();
                for (let k = 1; k <= 10; k++) { t.move(0, vw, 400 + ${dx} * k / 10, 300 + ${dy} * k / 10).commit(); wait(10); }
                t.release(0, vw, 400 + ${dx}, 300 + ${dy}).commit();
            }
            wait(20);
            const sum = name => vw.did.filter(d => d[0] === name).reduce((a, d) => a + d[1], 0);
            console.log("TOUCH " + JSON.stringify({ swipe: sum("swipe"), inside: sum("inside"), ends: vw.did.filter(d => d[0] === "end").length, panX: vw.panX }));
        }
    }
}
`;
  return logged(runScene({ "tst_touch.qml": scene }), "TOUCH");
}
try {
  const r = drag("image", 1, -240, 0);
  check("a finger drawn left over a picture steps the roll on, as a touchpad swipe does", r.swipe < -100 && r.inside === 0, JSON.stringify(r));
  check("and lifting it lets the roll settle", r.ends >= 1, JSON.stringify(r));
} catch (e) {
  check("the scene ran (picture)", false, String(e.message ?? e));
}
try {
  const r = drag("pdf", 1, 0, -240);
  check("a finger drawn up over a PDF scrolls its pages", r.inside < -150 && r.swipe === 0, JSON.stringify(r));
} catch (e) {
  check("the scene ran (PDF)", false, String(e.message ?? e));
}
try {
  const r = drag("image", 2, -240, 0);
  check("on a zoomed picture it pans instead", r.panX < -150 && r.swipe === 0, JSON.stringify(r));
} catch (e) {
  check("the scene ran (zoomed)", false, String(e.message ?? e));
}
try {
  const r = drag("image", 1, -240, 0, true);
  check("a mouse drag still moves nothing (a touchpad or the arrows step the roll)", r.swipe === 0 && r.inside === 0 && r.ends === 0, JSON.stringify(r));
} catch (e) {
  check("the scene ran (mouse)", false, String(e.message ?? e));
}
done();
