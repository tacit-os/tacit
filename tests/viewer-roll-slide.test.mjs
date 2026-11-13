// The Viewer's roll lands on the framed file after the list's window slides along a big folder
// (modules/viewer/Viewer.qml): the roll's own Behavior on pos and relist's branch for a slid window run under
// qmltestrunner offscreen, with the shell's own Anim, 120 ms into a step's 300 ms animation, as relistLater fires.
import { logged, module, runScene } from "./lib/qtscene.mjs";
import { matchBrace } from "./lib/qml.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the Viewer's roll lands after its list's window slides (Viewer.qml)");
const src = read("modules/viewer/Viewer.qml");
const behavior = src.split("\n").find(l => /^\s*Behavior on pos \{/.test(l));
const at = src.indexOf("{", src.indexOf("} else if (slid) {") + 2);
const slid = src.slice(at + 1, matchBrace(src, at));
const scene = `import QtQuick
import QtTest
import qs.modules.common.widgets
Item {
    id: vw
    property real pos: 0
    property int cur: 0
    property bool animate: true
    property bool touching: false
    property int landed: -1
    ${behavior}
    function land() { landed = cur }
    onPosChanged: if (!touching && pos === cur) land()
    // relist with the window moved by shift: the framed file is now at i
    function slide(shift, i) {
        cur = i;
        ${slid}
    }
    TestCase {
        name: "roll"; when: windowShown
        function test_slide() {
            vw.animate = false; vw.cur = 4400; vw.pos = 4400; vw.landed = 4400; vw.animate = true;   // at rest on file 4400
            wait(50);
            vw.cur = 4401; vw.pos = 4401;           // a step to the next file, 300 ms of roll
            wait(120);                              // relistLater: the window slides by 500
            vw.slide(-500, 3901);
            wait(500);
            console.log("ROLL " + JSON.stringify({ pos: vw.pos, cur: vw.cur, landed: vw.landed }));
        }
    }
}
`;
const anim = read("modules/common/widgets/Anim.qml");
const curves = (anim.match(/curves\.(\w+)/g) ?? []).map(c => c.slice(7)).filter((c, i, a) => a.indexOf(c) === i);
const stubs = {
  ...module("qs.modules.common", { Appearance: `QtObject { property QtObject animationCurves: QtObject {
${curves.map(c => /Duration$/.test(c) ? `        property int ${c}: 300` : `        property list<real> ${c}: [0.34, 0.88, 0.34, 1.00, 1, 1]`).join("\n")}
    } }` }),
  ...module("qs.modules.common.widgets", {}, { Anim: anim.replace(/^import QtQuick\n/, "") }),
};
try {
  const r = logged(runScene({ "tst_roll.qml": scene, ...stubs }), "ROLL");
  // the dwell that grows the picture to the window waits for exactly this (vw.pos === vw.cur)
  check("the roll comes to rest on the framed file", r.pos === r.cur, `pos ${r.pos}, the framed file ${r.cur}`);
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
