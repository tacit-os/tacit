// The control panel's sliders over 100% (modules/ii/sidebarRight/SidebarRightContent.qml): the file's LineSlider runs
// under Qt's qml tool offscreen around a stand-in for the kit's Slider, whose value runs from 0 to 1 and draws its bar
// and knob at that fraction of the track (Tacit.Kit Slider.qml), at volumes of 1.3, 1 and 0.42.
import { matchBrace } from "./lib/qml.mjs";
import { logged, module, runScene } from "./lib/qtscene.mjs";
import { check, done, read } from "./lib/check.mjs";

console.log("== the control panel's volume bar over 100% (SidebarRightContent.qml)");
const src = read("modules/ii/sidebarRight/SidebarRightContent.qml");
const at = src.indexOf("component LineSlider:");
const lineSlider = src.slice(at, matchBrace(src, src.indexOf("{", at)) + 1);

const scene = `import QtQuick
import QtQuick.Layouts
import stand.ins
Item {
    width: 400; height: 100
    component Symbol: Text { property real size }
    // the kit's Slider: its bar is track.width * value wide, so a value past 1 runs out of the track
    component Slider: Item {
        property real value: 0
        property string word: ""
        property string label
        signal moved(real value)
        implicitWidth: 260; implicitHeight: 28
    }
    ${lineSlider}
    Column {
        LineSlider { id: over; label: "Volume"; value: 1.3 }
        LineSlider { id: full; label: "Volume"; value: 1 }
        LineSlider { id: part; label: "Volume"; value: 0.42 }
    }
    Timer {
        interval: 50; running: true
        onTriggered: {
            const bar = l => l.children.find(c => c.word !== undefined)
            console.log("BARS " + JSON.stringify([over, full, part].map(l => ({ value: bar(l).value, word: bar(l).word }))))
            Qt.quit()
        }
    }
}
`;
try {
  const [over, full, part] = logged(runScene({
    "scene.qml": scene,
    ...module("stand.ins", { Kit: `QtObject { property var tokens: ({ space: { s: 8 }, icon: { row: 20 } }) }`, Tacit: `QtObject { property color inkMain: "white" }` }),
  }), "BARS");
  check("at 130% the bar is full, not past its track", over.value === 1, `the kit's Slider is given ${over.value}`);
  check("and its word says 130%", over.word === "130%", over.word);
  check("at 100% and 42% the bar and word are as before", full.value === 1 && full.word === "100%" && Math.abs(part.value - 0.42) < 1e-6 && part.word === "42%",
    JSON.stringify([full, part]));
} catch (e) {
  check("the scene ran", false, String(e.message ?? e));
}
done();
